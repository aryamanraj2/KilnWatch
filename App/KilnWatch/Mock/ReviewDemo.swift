import Foundation
import KilnWatchCore

/// Recorded public queue, with evidence hosts replaced before it entered the repository.
enum ReviewDemo {
    static var queue: ReviewQueue? {
        guard let url = Bundle.main.url(forResource: "ReviewRecorded", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.kilnWatch.decode(ReviewQueue.self, from: data)
    }
}
