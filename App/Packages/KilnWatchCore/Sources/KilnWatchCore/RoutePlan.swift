import Foundation
import Observation
import os

/// Exactly the P1 body this app sends: no start, depart, budget or kiln IDs, so the server defaults apply.
public struct RoutePlanRequest: Codable, Sendable, Equatable {
    public let district: String
    public let priority: String
    public let maxStops: Int
    public init(district: String) { self.district = district; priority = "people"; maxStops = 8 }
}

public enum RoutePlanError: Error, Sendable, Equatable {
    case service(status: Int, detail: AskServiceError?)
    /// The stage throttle's own 429 body, with no `error.code`.
    case gatewayThrottled
    case transport(URLError.Code)
    case malformedResponse
    case cancelled

    /// Never the server message or provider text.
    public func message(district: String) -> String {
        switch self {
        case .service(400, _): "The plan request was rejected."
        case .service(404, let detail) where detail?.code == "no_kilns": "No flagged kilns with population estimates in \(district) to plan."
        case .service(404, _): "Route planning returned no plan."
        case .service(429, let detail) where detail?.code == "daily_cap_reached":
            "Route planning has reached today's limit. It resets at 05:30 IST (00:00 UTC)."
        case .gatewayThrottled, .service(429, _): "Too many requests. Wait a moment."
        case .service(503, _): "Route planning is unavailable right now."
        case .service: "Route planning failed. Try again later."
        case .transport(.timedOut): "The plan took too long to arrive. Check your connection and try again."
        case .transport: "You're offline. Reconnect to plan a route."
        case .malformedResponse: "The plan could not be read."
        case .cancelled: "Planning was interrupted. It may still count toward today's limit."
        }
    }

    /// Manual retry only; nothing here retries automatically.
    public var canRetry: Bool {
        switch self {
        case .service(400, _), .service(404, _), .malformedResponse: false
        case .service(429, let detail) where detail?.code == "daily_cap_reached": false
        case .service(let status, let detail): detail?.retryable ?? (status >= 500)
        case .gatewayThrottled, .transport, .cancelled: true
        }
    }

    public var isDailyCap: Bool {
        if case .service(429, let detail) = self { return detail?.code == "daily_cap_reached" }
        return false
    }
}

extension KilnWatchAPI {
    /// Cost-bearing public POST. Exactly one attempt; no Authorization, no backoff, no caching.
    public func planRoute(district: String) async throws(RoutePlanError) -> Route {
        var request = URLRequest(url: baseURL.appending(path: "routes/plan"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 35)
        request.httpMethod = "POST"
        request.httpBody = try? JSONEncoder.kilnWatch.encode(RoutePlanRequest(district: district))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw .cancelled }
            throw .transport((error as? URLError)?.code ?? .unknown)
        }
        guard let response = response as? HTTPURLResponse else { throw .malformedResponse }
        guard response.statusCode == 200 else {
            let detail = (try? JSONDecoder().decode(AskErrorEnvelope.self, from: data))?.error
            if response.statusCode == 429, detail == nil { throw .gatewayThrottled }
            throw .service(status: response.statusCode, detail: detail)
        }
        guard let route = try? JSONDecoder.kilnWatch.decode(Route.self, from: data), !route.stops.isEmpty else { throw .malformedResponse }
        return route
    }
}

/// Plans only on an explicit call, one at a time. A plan replaces the saved one only after it succeeds.
@MainActor @Observable public final class RoutePlanner {
    public private(set) var isPlanning = false
    public private(set) var failure: RoutePlanError?
    /// Every POST started in this process, including failures. Each may count toward the shared daily cap.
    public private(set) var attempts = 0
    public let district: String
    @ObservationIgnored private var failedAt: Date?
    @ObservationIgnored private let api: KilnWatchAPI?
    @ObservationIgnored private let cache: RouteCache
    @ObservationIgnored private var rejected = 0
    @ObservationIgnored private let log = Logger(subsystem: "KilnWatch", category: "RoutePlan")

    /// No I/O: launch reads the saved plan separately and never plans.
    public init(api: KilnWatchAPI?, district: String, cache: RouteCache) {
        self.api = api; self.district = district; self.cache = cache
    }

    public var failureMessage: String? { failure?.message(district: district) }

    public func canPlan(now: Date = .now) -> Bool {
        guard api != nil, !isPlanning else { return false }
        guard let failure else { return true }
        if failure.isDailyCap, let failedAt {
            var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
            return utc.date(byAdding: .day, value: 1, to: utc.startOfDay(for: failedAt)).map { now >= $0 } ?? false
        }
        return failure.canRetry
    }

    /// One attempt. On failure the saved plan is untouched and `failure` explains why.
    public func plan() async -> (route: Route, cacheWarning: String?)? {
        guard canPlan(), let api else { return nil }
        isPlanning = true; failure = nil; attempts += 1
        defer { isPlanning = false }
        do {
            let route = try await api.planRoute(district: district)
            return (route, await Self.save(route, in: cache))
        } catch {
            failure = error; failedAt = .now
            if case .service(400, _) = error {
                rejected += 1
                log.error("Route plan request rejected; count \(self.rejected, privacy: .public)")
            }
            return nil
        }
    }

    @concurrent private static func save(_ route: Route, in cache: RouteCache) async -> String? {
        do { try cache.save(route); return nil } catch { return "Could not save this plan for offline use." }
    }
}

extension Route {
    static let planTimeZone = TimeZone(identifier: "Asia/Kolkata")!

    /// 24-hour plan time in Asia/Kolkata, for example "09:13".
    public static func clock(_ date: Date) -> String {
        date.formatted(Date.VerbatimFormatStyle(format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
                                                timeZone: planTimeZone, calendar: Calendar(identifier: .gregorian)))
    }

    /// The departure day, falling back to the earliest ordered stop or generation time.
    private var planDay: Date { depart ?? stops.min { $0.order < $1.order }?.eta ?? generatedAt }

    /// A plan expires only after its calendar day ends in Asia/Kolkata; never triggers planning.
    public func hasPassed(now: Date = .now) -> Bool {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = Self.planTimeZone
        return calendar.startOfDay(for: planDay) < calendar.startOfDay(for: now)
    }

    /// "Today", "Tomorrow" or a date such as "Sun 11 Oct", for the plan's departure day in Asia/Kolkata.
    public func dayLabel(now: Date = .now, locale: Locale = .autoupdatingCurrent) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = Self.planTimeZone
        let day = planDay
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) { return "Tomorrow" }
        return day.formatted(Date.VerbatimFormatStyle(format: "\(weekday: .abbreviated) \(day: .defaultDigits) \(month: .abbreviated)",
                                                      locale: locale, timeZone: Self.planTimeZone, calendar: calendar))
    }

    /// Arrival times are estimates: "Est. 09:13" (compact) or "Estimated arrival 09:13", never a bare ETA.
    public func arrival(for stop: Stop, compact: Bool) -> String {
        var text = "\(compact ? "Est." : "Estimated arrival") \(Self.clock(stop.eta))"
        if let seconds = driveSeconds(for: stop.kilnId), let minutes = Int(exactly: (seconds / 60).rounded(.up)) {
            text += " · \(minutes)\u{00A0}min drive"
        }
        return text
    }

    /// "8 stops · est. 6 h 10 m · leave 09:00". The total appears only when every leg and stop has valid durations.
    public func summary(stopCount: Int) -> String {
        var parts = ["\(stopCount) stops"]
        if let seconds = predictedSeconds, let minutes = Int(exactly: (seconds / 60).rounded(.up)) {
            parts.append("est. \(minutes / 60)\u{00A0}h \(minutes % 60)\u{00A0}m")
        }
        if let depart { parts.append("leave \(Self.clock(depart))") }
        return parts.joined(separator: " · ")
    }
}
