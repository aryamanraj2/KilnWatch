import Foundation

extension Route {
    /// Uses server order. Bad references remain in the payload, but cannot be browsed or navigated.
    public var usableStops: [Stop] {
        var seen = Set<String>()
        return stops.sorted { $0.order < $1.order }.filter { stop in
            seen.insert(stop.kilnId).inserted && kilns.contains { $0.kilnId == stop.kilnId && $0.footprint.centroid.isValid }
        }
    }

    public func destination(for stop: Stop) -> Coordinate? {
        if let point = stop.access?.coordinate, point.isValid { return point }
        return kilns.first { $0.kilnId == stop.kilnId }?.footprint.centroid.isValid == true
            ? kilns.first { $0.kilnId == stop.kilnId }?.footprint.centroid : nil
    }

    /// No source: Apple Maps starts at the user's location. Repeated waypoints retain server order.
    public func mapsURL(startingAt id: String?) -> URL? {
        let ordered = usableStops
        guard !ordered.isEmpty else { return nil }
        let first: Int
        if let id {
            guard let index = ordered.firstIndex(where: { $0.kilnId == id }) else { return nil }
            first = index
        } else { first = 0 }
        let destinations = ordered.dropFirst(first).compactMap { destination(for: $0) }
        guard let last = destinations.last else { return nil }
        func pair(_ coordinate: Coordinate) -> String { "\(coordinate.latitude),\(coordinate.longitude)" }
        var url = URLComponents()
        url.scheme = "https"; url.host = "maps.apple.com"; url.path = "/directions"
        url.queryItems = destinations.dropLast().map { URLQueryItem(name: "waypoint", value: pair($0)) }
            + [URLQueryItem(name: "destination", value: pair(last)), URLQueryItem(name: "mode", value: "driving")]
        return url.url
    }

    public func driveSeconds(for id: String) -> Double? {
        guard let seconds = legs?.first(where: { $0.toKilnId == id })?.durationS,
              seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }

    /// Only complete, valid drive and service metadata can produce a predicted total.
    public var predictedSeconds: Double? {
        guard !stops.isEmpty else { return nil }
        var total = 0.0
        for stop in stops {
            guard let drive = driveSeconds(for: stop.kilnId), let service = stop.serviceMin, service >= 0 else { return nil }
            total += drive + Double(service) * 60
        }
        return total.isFinite ? total : nil
    }
}
