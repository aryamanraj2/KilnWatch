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

/// Verdicts recorded offline, persisted until the server has them and every photo.
/// Invariant: a verdict and its photos leave disk only after a successful submit and upload.
public actor VerdictOutbox {
    public struct Entry: Codable, Sendable, Identifiable {
        public let verdict: Verdict
        public fileprivate(set) var attempts = 0
        public fileprivate(set) var lastError: String?
        public var id: UUID { verdict.id }
    }

    public enum EnqueueError: Error {
        case missingPhotoData(Photo.ID)
    }

    /// Oldest first.
    public private(set) var pending: [Entry]
    private let directory: URL
    private var isFlushing = false

    /// Reloads whatever a previous launch left on disk.
    public init(directory: URL = URL.kilnWatchStore.appending(path: "Outbox", directoryHint: .isDirectory)) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let queueURL = directory.appending(path: "queue.json")
        pending = FileManager.default.fileExists(atPath: queueURL.path)
            ? try JSONDecoder.kilnWatch.decode([Entry].self, from: Data(contentsOf: queueURL))
            : []
    }

    /// Where a queued photo's JPEG lives.
    public nonisolated func fileURL(for photo: Photo, of verdict: Verdict) -> URL {
        directory.appending(path: verdict.id.uuidString).appending(path: "\(photo.id.uuidString).jpg")
    }

    /// Writes the photos, then the queue. When this returns, the verdict survives a crash.
    /// `photos` maps each `verdict.photos` id to its JPEG data.
    public func enqueue(_ verdict: Verdict, photos: [Photo.ID: Data]) throws {
        let queue = pending + [Entry(verdict: verdict)]
        let encoded = try JSONEncoder.kilnWatch.encode(queue) // fails on a NaN coordinate before anything touches disk
        try FileManager.default.createDirectory(at: directory.appending(path: verdict.id.uuidString), withIntermediateDirectories: true)
        for photo in verdict.photos {
            guard let data = photos[photo.id] else { throw EnqueueError.missingPhotoData(photo.id) }
            try data.write(to: fileURL(for: photo, of: verdict), options: writeOptions)
        }
        // ponytail: a crash between the photo writes and this line leaves orphan photos; sweep them if disk use matters.
        try encoded.write(to: directory.appending(path: "queue.json"), options: writeOptions)
        pending = queue
    }

    /// Sends pending verdicts oldest first. Stops at the first failure that would hit every verdict
    /// (offline, no token, server down); a rejection of one verdict is recorded and the rest still go.
    public func flush(using api: KilnWatchAPI) async {
        guard !isFlushing else { return } // actor reentrancy: one flush at a time
        isFlushing = true
        defer { isFlushing = false }

        for entry in pending {
            do {
                try await send(entry.verdict, using: api)
                let remaining = pending.filter { $0.id != entry.id }
                try JSONEncoder.kilnWatch.encode(remaining).write(to: directory.appending(path: "queue.json"), options: writeOptions)
                pending = remaining
                // Queue first, photos second: a crash in between leaks files, never loses a verdict.
                try? FileManager.default.removeItem(at: directory.appending(path: entry.verdict.id.uuidString))
            } catch {
                guard let index = pending.firstIndex(where: { $0.id == entry.id }) else { continue }
                pending[index].attempts += 1
                pending[index].lastError = String(describing: error)
                // Attempt counts are advisory; if this write fails the verdict is still safe in the older queue file.
                try? JSONEncoder.kilnWatch.encode(pending).write(to: directory.appending(path: "queue.json"), options: writeOptions)
                if (error as? APIError)?.isSystemic == true { break }
            }
        }
    }

    private func send(_ verdict: Verdict, using api: KilnWatchAPI) async throws {
        let receipt = try await api.submit(verdict)
        for upload in receipt.photoUploads {
            guard let photo = verdict.photos.first(where: { $0.id == upload.photoId }) else { continue }
            try await api.upload(Data(contentsOf: fileURL(for: photo, of: verdict)), to: upload.uploadUrl)
        }
    }
}
