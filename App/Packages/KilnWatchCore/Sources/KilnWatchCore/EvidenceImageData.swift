import Foundation

public enum EvidenceImageError: Error, Sendable, Equatable {
    case unsupportedURL, unavailable, oversized, invalidPNG
}

/// Small PNG evidence only. Local file URLs allow deterministic image-path testing.
public enum EvidenceImageData {
    @concurrent public static func load(from url: URL, session: URLSession = .shared) async throws -> Data {
        let data: Data
        if url.isFileURL {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 2_097_152 else { throw EvidenceImageError.oversized }
            data = try Data(contentsOf: url)
        } else {
            guard url.scheme == "https" else { throw EvidenceImageError.unsupportedURL }
            let response: URLResponse
            (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw EvidenceImageError.unavailable }
        }
        try Task.checkCancellation()
        guard data.count <= 2_097_152 else { throw EvidenceImageError.oversized }
        guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else { throw EvidenceImageError.invalidPNG }
        return data
    }
}
