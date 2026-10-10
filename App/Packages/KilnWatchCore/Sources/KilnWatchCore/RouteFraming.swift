#if canImport(MapKit)
import MapKit

extension Route {
    /// Tight bounds for exactly the pins and validated legs drawn by Today.
    /// SwiftUI's settled safe-area insets supply screen-space clearance for the overlays.
    public func overviewRect(stopCoordinates: [Coordinate]? = nil) -> MKMapRect? {
        let ids = Set(usableStops.map(\.kilnId))
        let points = (stopCoordinates ?? kilns.filter { ids.contains($0.kilnId) }.map(\.footprint.centroid))
            + (legs ?? []).filter { ids.contains($0.toKilnId) }.flatMap { $0.geometry?.validatedCoordinates ?? [] }
        let mapped = points.filter(\.isValid).map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
        guard let first = mapped.first else { return nil }
        let bounds = mapped.dropFirst().reduce(MKMapRect(x: first.x, y: first.y, width: 1, height: 1)) {
            $0.union(MKMapRect(x: $1.x, y: $1.y, width: 1, height: 1))
        }
        // Five percent, bounded to avoid a singleton collapsing or a long route gaining huge margins.
        let padding = min(2_000, max(200, max(bounds.width, bounds.height) * 0.05))
        return bounds.insetBy(dx: -padding, dy: -padding)
    }
}
#endif
