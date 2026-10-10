import Foundation
import KilnWatchCore
import MapKit
import SwiftUI

extension AppModel {
    /// Arrival times are estimates everywhere: "Est. 09:13" or "Estimated arrival 09:13".
    func arrival(for stop: Stop, compact: Bool) -> String {
        route?.arrival(for: stop, compact: compact) ?? "\(compact ? "Est." : "Estimated arrival") \(Route.clock(stop.eta))"
    }
    var routeSummary: String {
        guard let route else { return isLoading ? "Loading route" : "No route" }
        return route.summary(stopCount: stops.count)
    }
    /// The plan's own day, for example "Tomorrow · Hapur", never an assumed "Today".
    var routeTitle: String { route.map { "\($0.dayLabel()) · \($0.district)" } ?? "Today" }
    var savedDate: String? {
        guard case .saved(let route, _) = routeState else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let planDate = route.depart ?? route.stops.first?.eta ?? route.generatedAt
        // A public plan is never refreshed automatically, so its saved date always shows.
        guard usesPublicRegistry || !calendar.isDate(planDate, inSameDayAs: .now) else { return nil }
        var style = Date.FormatStyle.dateTime.day().month().year()
        style.timeZone = calendar.timeZone
        return "Saved plan · \(planDate.formatted(style))"
    }
    var overview: MapCameraPosition {
        guard let route else { return .automatic }
        let points = stops.compactMap { kiln($0.kilnId)?.footprint.centroid }
            + (route.legs ?? []).flatMap { $0.geometry?.validatedCoordinates ?? [] }
        guard let first = points.first else { return .automatic }
        var rect = MKMapRect(origin: MKMapPoint(first.clLocation), size: MKMapSize(width: 1, height: 1))
        for point in points.dropFirst() { rect = rect.union(MKMapRect(origin: MKMapPoint(point.clLocation), size: MKMapSize(width: 1, height: 1))) }
        // The map's safe-area insets reserve room for the header and carousel.
        let padding = max(rect.size.width, rect.size.height) * 0.16 + 1_000
        return .rect(rect.insetBy(dx: -padding, dy: -padding))
    }
}

/// Shared by Today and the existing kiln Directions button. Opening Maps never advances a stop.
@MainActor @Observable
final class MapsHandoff {
    var confirmation: String?
    var error: String?
    private var pendingCoordinate: Coordinate?
    private var pendingName: String?
    private var pendingURL: URL?

    func navigate(id: String, model: AppModel) {
        let stop = model.stops.first { $0.kilnId == id }
        let access = stop?.access?.coordinate
        let destination = access?.isValid == true ? access : model.kiln(id)?.footprint.centroid
        guard let destination, destination.isValid else { error = "No usable location is available for this stop."; return }
        pendingCoordinate = destination; pendingName = id; pendingURL = nil
        if access?.isValid != true {
            confirmation = "No road access point is supplied. Maps will use the kiln location; confirm the entrance on site."
        } else { openPending() }
    }
    func wholeRoute(model: AppModel) {
        let start = model.routeActive ? model.currentStopId : model.stops.first?.kilnId
        guard let url = model.route?.mapsURL(startingAt: start) else { error = "No stops are available to open in Maps."; return }
        pendingURL = url; pendingCoordinate = nil
        let remaining = model.stops.drop { $0.kilnId != start }
        if remaining.contains(where: { $0.access?.coordinate.isValid != true }) {
            confirmation = "Some stops have no road access point. Maps will use their kiln locations; confirm entrances on site."
        } else { openPending() }
    }
    func openPending() {
        confirmation = nil
        if let url = pendingURL {
            UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                Task { @MainActor in if !opened { self?.error = "Maps could not open the route. Try Navigate for one stop." } }
            }
        } else if let coordinate = pendingCoordinate {
            let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
            item.name = pendingName
            if !item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]) {
                error = "Maps could not open this stop. Try again."
            }
        }
        pendingURL = nil; pendingCoordinate = nil
    }
    func cancel() { confirmation = nil; pendingURL = nil; pendingCoordinate = nil }
}
