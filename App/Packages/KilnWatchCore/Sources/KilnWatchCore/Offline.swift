import Foundation

private let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

extension URL {
    /// Application Support/KilnWatch. Not Caches: the system may purge Caches, and the outbox holds unsent work.
    public static var kilnWatchStore: URL { .applicationSupportDirectory.appending(path: "KilnWatch", directoryHint: .isDirectory) }
}

/// The last fetched route and its kilns, so the day works without signal.
public struct RouteCache: Sendable {
    public let fileURL: URL

    public init(directory: URL = .kilnWatchStore) {
        fileURL = directory.appending(path: "route.json")
    }

    public func save(_ route: Route) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.kilnWatch.encode(route).write(to: fileURL, options: writeOptions)
    }

    /// An authoritative empty response invalidates only the route, never verdict files.
    public func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
    }

    /// Nil when nothing has been cached yet.
    public func load() throws -> Route? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder.kilnWatch.decode(Route.self, from: Data(contentsOf: fileURL))
    }
}

/// Durable queue. Upload receipts and network errors never touch disk or UI.
public actor VerdictOutbox {
    public struct Entry: Codable, Sendable, Identifiable {
        public let verdict: Verdict
        public fileprivate(set) var attempts = 0
        public fileprivate(set) var lastError: String?
        public fileprivate(set) var rejected: Bool?
        public fileprivate(set) var retryAfter: Date?
        public var id: UUID { verdict.id }
    }

    public enum EnqueueError: Error { case missingPhotoData(Photo.ID), duplicateID }
    public enum DiscardError: Error { case notRejected }
    private struct SubmissionFailure: Error { let error: APIError }

    public private(set) var pending: [Entry]
    /// Successful deliveries awaiting one agreeing public read, persisted across relaunch.
    public private(set) var recorded: [Verdict]
    private let directory: URL
    private var isFlushing = false

    public init(directory: URL = URL.kilnWatchStore.appending(path: "Outbox", directoryHint: .isDirectory)) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let queueURL = directory.appending(path: "queue.json")
        var entries = FileManager.default.fileExists(atPath: queueURL.path)
            ? try JSONDecoder.kilnWatch.decode([Entry].self, from: Data(contentsOf: queueURL)) : []
        let recordedURL = directory.appending(path: "recorded.json")
        recorded = FileManager.default.fileExists(atPath: recordedURL.path)
            ? try JSONDecoder.kilnWatch.decode([Verdict].self, from: Data(contentsOf: recordedURL)) : []
        // Older versions persisted arbitrary error descriptions. Do not expose them after upgrade.
        for index in entries.indices where entries[index].lastError != nil && entries[index].rejected == nil && entries[index].retryAfter == nil {
            entries[index].lastError = "Verdict waiting to sync"
        }
        try JSONEncoder.kilnWatch.encode(entries).write(to: queueURL, options: writeOptions)
        pending = entries
    }

    public nonisolated func fileURL(for photo: Photo, of verdict: Verdict) -> URL {
        directory.appending(path: verdict.id.uuidString).appending(path: "\(photo.id.uuidString).jpg")
    }

    public func enqueue(_ verdict: Verdict, photos: [Photo.ID: Data]) throws {
        guard !pending.contains(where: { $0.id == verdict.id }) else { throw EnqueueError.duplicateID }
        for photo in verdict.photos where photos[photo.id] == nil { throw EnqueueError.missingPhotoData(photo.id) }
        let queue = pending + [Entry(verdict: verdict)]
        let encoded = try JSONEncoder.kilnWatch.encode(queue)
        try FileManager.default.createDirectory(at: directory.appending(path: verdict.id.uuidString), withIntermediateDirectories: true)
        for photo in verdict.photos {
            try photos[photo.id]!.write(to: fileURL(for: photo, of: verdict), options: writeOptions)
        }
        try encoded.write(to: directory.appending(path: "queue.json"), options: writeOptions)
        pending = queue
    }

    public func discard(_ id: UUID) throws {
        guard pending.first(where: { $0.id == id })?.rejected == true else { throw DiscardError.notRejected }
        let remaining = pending.filter { $0.id != id }
        try saveQueue(remaining)
        pending = remaining
        try? FileManager.default.removeItem(at: directory.appending(path: id.uuidString))
    }

    public func reconcile(_ kiln: Kiln) throws {
        guard let inspection = kiln.inspection else { return }
        let remaining = recorded.filter {
            !($0.kilnId == kiln.kilnId && inspection.recordedAt >= $0.recordedAt.addingTimeInterval(-0.001))
        }
        try JSONEncoder.kilnWatch.encode(remaining).write(to: directory.appending(path: "recorded.json"), options: writeOptions)
        recorded = remaining
    }

    /// Returns only newly completed deliveries. Skips rejected entries and daily-cap deferrals.
    @discardableResult public func flush(using api: KilnWatchAPI, now: Date = .now) async -> [Verdict] {
        guard !isFlushing, !pending.contains(where: { $0.retryAfter.map { $0 > now } ?? false }) else { return [] }
        isFlushing = true
        defer { isFlushing = false }
        var delivered: [Verdict] = []
        for entry in pending {
            guard entry.rejected != true, entry.retryAfter.map({ $0 <= now }) ?? true else { continue }
            do {
                try await send(entry.verdict, using: api)
                let acknowledgements = recorded.filter { $0.id != entry.id } + [entry.verdict]
                try JSONEncoder.kilnWatch.encode(acknowledgements).write(to: directory.appending(path: "recorded.json"), options: writeOptions)
                recorded = acknowledgements
                let remaining = pending.filter { $0.id != entry.id }
                try saveQueue(remaining)
                pending = remaining
                delivered.append(entry.verdict)
                try? FileManager.default.removeItem(at: directory.appending(path: entry.verdict.id.uuidString))
            } catch {
                guard let index = pending.firstIndex(where: { $0.id == entry.id }) else { continue }
                pending[index].attempts += 1
                pending[index].lastError = "Verdict waiting to sync"
                var stop = true
                if let submission = error as? SubmissionFailure {
                    switch submission.error {
                    case .status(let code, _) where [400, 404, 409].contains(code):
                        pending[index].rejected = true
                        pending[index].lastError = switch code {
                        case 404: "This kiln is no longer in the registry"
                        case 409: "This verdict ID already has different content"
                        default: "The verdict could not be accepted. Check its photo and note details"
                        }
                        stop = false
                    case .status(429, let body):
                        struct Envelope: Decodable { struct Detail: Decodable { let code: String }; let error: Detail }
                        if (try? JSONDecoder().decode(Envelope.self, from: body).error.code) == "daily_cap_reached" {
                            var calendar = Calendar(identifier: .gregorian)
                            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                            pending[index].retryAfter = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
                            pending[index].lastError = "Verdict limit reached for today · will send after 05:30 IST"
                        }
                    default: break
                    }
                }
                try? saveQueue(pending)
                if stop { break }
            }
        }
        return delivered
    }

    private func saveQueue(_ queue: [Entry]) throws {
        try JSONEncoder.kilnWatch.encode(queue).write(to: directory.appending(path: "queue.json"), options: writeOptions)
    }

    private func send(_ verdict: Verdict, using api: KilnWatchAPI) async throws {
        let receipt: VerdictReceipt
        do { receipt = try await api.submit(verdict) }
        catch { throw SubmissionFailure(error: error) }
        guard receipt.id == verdict.id, receipt.photoUploads.count == verdict.photos.count,
              Set(receipt.photoUploads.map(\.photoId)) == Set(verdict.photos.map(\.id)),
              receipt.photoUploads.allSatisfy({ KilnWatchAPI.isAllowedUploadURL($0.uploadUrl) }) else { throw APIError.invalidReceipt }
        for upload in receipt.photoUploads {
            guard let photo = verdict.photos.first(where: { $0.id == upload.photoId }) else { throw APIError.invalidReceipt }
            try await api.upload(Data(contentsOf: fileURL(for: photo, of: verdict)), to: upload.uploadUrl)
        }
    }
}
