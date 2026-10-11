#if DEBUG
import Foundation
import KilnWatchCore
import Synchronization

/// Test proof contains method/status counts only. Receipts and URLs are never persisted.
enum VerdictDiagnostics {
    private static let lock = Mutex(())
    nonisolated static func record(photo: Bool, code: Int) {
        lock.withLock { _ in
            let file = URL.kilnWatchStore.appending(path: "DebugVerdictHTTP.txt")
            var data = (try? Data(contentsOf: file)) ?? Data()
            data.append(Data("\(photo ? "PHOTO_PUT" : "POST") \(code) \(Date.now.timeIntervalSince1970)\n".utf8))
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
#endif
