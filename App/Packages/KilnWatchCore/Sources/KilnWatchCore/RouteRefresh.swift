import Foundation

public enum RouteRefresh: Sendable {
    case loaded(Route, cacheWarning: String?)
    case empty
    case offline(Route)
    case failure(String)

    /// File operations run away from the UI actor. A failed refresh never substitutes sample data.
    @concurrent public static func fetch(using api: KilnWatchAPI, cache: RouteCache) async throws -> RouteRefresh {
        do {
            let route = try await api.todayRoute()
            try Task.checkCancellation()
            if route.stops.isEmpty {
                try cache.clear()
                return .empty
            }
            do { try cache.save(route); return .loaded(route, cacheWarning: nil) }
            catch { return .loaded(route, cacheWarning: "Could not save this route for offline use.") }
        } catch let error as APIError {
            try Task.checkCancellation()
            switch error {
            case .status(404, _):
                try cache.clear()
                return .empty
            case .transport:
                do {
                    if let route = try cache.load(), !route.stops.isEmpty { return .offline(route) }
                    return .failure("No connection and no saved route. Try again when you have a signal.")
                } catch {
                    return .failure("The saved route could not be read. Reconnect and retry.")
                }
            case .token, .status(401, _), .status(403, _):
                return .failure("Route access could not be verified. Check your account and retry.")
            case .status(let code, _):
                return .failure("The route service returned \(code). Try again.")
            case .decoding:
                return .failure("The route response could not be read. Your saved route has been preserved.")
            }
        }
    }

    @concurrent public static func saved(in cache: RouteCache) async throws -> Route? { try cache.load() }
}
