# Routing: handing the planned route to navigation

Researched 2026-10-09 against Apple's MapKit docs and the iOS 27 SDK headers (Xcode-beta).

## Recommendation

The **server owns the route**. It sends the stop order, the ETAs, a road-snapped **access point** per stop, and the **road geometry for every leg** (Amazon Location `CalculateRoutes`, as a GeoJSON LineString). The app draws that geometry itself with `MapPolyline`, caches it with the route, and never calls `MKDirections` to redraw it. For driving, the primary handoff is **one leg at a time**: a **Navigate** button on the current stop card opens Apple Maps with directions from the inspector's location to that stop's access point (`MKMapItem.openInMaps`). An inspector spends 30+ minutes on site between legs, and a multi-stop trip in Apple Maps reportedly can't be paused (unverified, see below). A secondary **"Open whole route in Maps"** uses the Unified Maps URL `https://maps.apple.com/directions?waypoint=…&destination=…&mode=driving` (iOS 18.4+), which does take multiple stops from a third-party app. Offline, the app shows the cached geometry, stops and evidence; MapKit's base tiles cannot be pre-downloaded.

## Can Apple Maps take multiple stops from our app?

- **`MKMapItem.openMaps(with:launchOptions:)`: no.** With a directions-mode launch option, "the `mapItems` array may have no more than two items". Two items means directions from the first to the second.
- **Unified Maps URLs: yes, since iOS 18.4.** The `/directions` path accepts `source`, `destination`, a repeatable `waypoint` ("you can use for multistop routing"), `mode=driving|walking|transit|cycling`, `avoid=tolls,highways,…` and `start=<seconds>`. Leaving out `source` starts from the user's location. Our deployment target is iOS 26.1, so no availability gate is needed.
- **iOS 26/27 SDK:** `MKDirections.Request` still has one `source` and one `destination`. iOS 26 added `MKMapItem(location:address:)`. A grep of the iOS 27 MapKit headers finds **no waypoint or offline API**; the only iOS 27 additions are new POI categories.
- Apple Maps limits: "up to 15" stops per multi-stop trip (a tip page updated Feb 2026). Two further claims, that multi-stop is driving-only and that the trip can't be saved or paused, come from 2022 press snippets I could not open (403 or unsupported site). Treat them as **unverified** and test on an iOS 27 device. Turn-by-turn navigation is listed for **India** on Apple's feature-availability page. "Multi-stop" is not listed separately, so test it in Hapur.
- Hand off the **access point**, not the kiln centroid. The centroid sits in a field, and Maps would route to the nearest road edge, which may be the wrong side of a canal.

## Draw it ourselves or use MKDirections?

| | Server polyline (recommended) | `MKDirections` on device |
|---|---|---|
| Matches the order and ETAs the solver used | Yes: same road network (Amazon Location) | No: Apple's graph can disagree with the plan |
| Works offline | Yes, cached with the route | No: it is a network call, and Apple throttles requests |
| Calls per day | 0 | N legs, re-requested on every relaunch |
| Turn-by-turn | No; Apple Maps handles that | No (the routes are not navigable in-app either) |

Amazon Location `CalculateRoutes` returns per-leg geometry as `LegGeometryFormat=FlexiblePolyline` (compact, needs a decoder) or `Simple` (plain coordinates). **Ask for `Simple`, simplify to about 5 m on the server, and ship GeoJSON `[lon, lat]` arrays**, which need no decoder on iOS. Use `MKDirections` only for an optional "from here to next stop" ETA refresh when the app is online.

## Offline

- **Base map tiles:** MapKit offers no API to prefetch tiles or to use the offline maps a user downloaded in Apple Maps (Apple DTS, Oct 2024: "not possible with the APIs available today"). No new API appears in the iOS 27 SDK. MapKit keeps its own transient tile cache, which we can't control. **Design for "no basemap"**: on a blank map the route line, the numbered stops and the user's location still render.
- **What we cache** (via KilnWatchCore's route cache): stops, access points, leg geometry, inspection sheets and evidence PNGs (see evidence-imagery.md). That is a few MB per day.
- **Handoff offline:** Apple Maps without data can still navigate inside regions the user has downloaded in Maps. Suggest in onboarding that inspectors download "Hapur" in Apple Maps (Maps → profile → Offline Maps). The app can't trigger or detect that download.
- Optional, later: an `MKMapSnapshotter` image of the day's route rendered while online could act as a static fallback. Check the MapKit terms before shipping that.

## Proposed route payload (extends `route_today.json` in docs/api-contract.md)

```json
{ "route_id": "2026-10-10-hapur-ins-17", "depart": "2026-10-10T09:00:00+05:30", "budget_min": 360,
  "stops": [ { "order": 1, "kiln_id": "KW-0412", "eta": "2026-10-10T09:34:00+05:30", "service_min": 35,
               "access": { "lat": 28.7311, "lon": 77.7795, "note": "Track off Garh Rd, north gate" } } ],
  "legs":  [ { "to_kiln_id": "KW-0412", "distance_m": 18240, "duration_s": 2040,
               "geometry": { "type": "LineString", "coordinates": [[77.7012, 28.7350], [77.7795, 28.7311]] } } ] }
```

## Client example (typechecked and run under Swift 6.4 / macOS 27)

```swift
struct Stop: Sendable { let kilnID: String; let order: Int; let access: CLLocationCoordinate2D }

@MainActor func navigate(to stop: Stop, of total: Int) {          // primary: one leg
    let item = MKMapItem(location: CLLocation(latitude: stop.access.latitude, longitude: stop.access.longitude), address: nil)
    item.name = "\(stop.kilnID) · stop \(stop.order) of \(total)"
    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
}

func fullRouteURL(_ remaining: [Stop]) -> URL {                // secondary: the rest of the day in Apple Maps
    func ll(_ c: CLLocationCoordinate2D) -> String { "\(c.latitude),\(c.longitude)" }
    var c = URLComponents(string: "https://maps.apple.com/directions")!
    c.queryItems = remaining.dropLast().map { URLQueryItem(name: "waypoint", value: ll($0.access)) }
        + [URLQueryItem(name: "destination", value: ll(remaining.last!.access)), URLQueryItem(name: "mode", value: "driving")]
    return c.url!   // open with @Environment(\.openURL); no source, so Maps starts from the current location
}

Map {   // in the Today view
    ForEach(legs, id: \.toKilnID) { leg in
        MapPolyline(coordinates: leg.geometry.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) })
            .stroke(Color("clay"), lineWidth: 4)
    }
}
```

The run produced `https://maps.apple.com/directions?waypoint=28.73,77.78&waypoint=28.75,77.8&destination=28.71,77.65&mode=driving`. I did not open it on a device.

## Evidence

- Unified Maps URLs (`/directions`, repeatable `waypoint`, iOS 18.4+): https://developer.apple.com/documentation/mapkit/unified-map-urls
- `openMaps(with:launchOptions:)`, at most two items with directions mode: https://developer.apple.com/documentation/mapkit/mkmapitem/openmaps(with:launchoptions:)
- `MKDirections.Request` (single source and destination): https://developer.apple.com/documentation/mapkit/mkdirections/request
- iOS 27 SDK headers: `MKMapItem.h` (`initWithLocation:address:` iOS 26), with no `offline` or `waypoint` symbols in MapKit headers or the swiftinterface.
- Apple DTS on offline maps in third-party apps (Oct 2024): https://developer.apple.com/forums/thread/765857
- Multi-stop limit of 15 (updated 2026-02-18): https://apple.lukezilioli.com/tips/multi-stop-routing-in-ios-16-apple-maps/
- Feature availability (turn-by-turn includes India): https://www.apple.com/ios/feature-availability/
- iOS 27 Maps changes (2026-07-01; nothing about multi-stop or MapKit APIs; offline-map label improvements only): https://www.macrumors.com/guide/ios-27-maps/
- Amazon Location `CalculateRoutes` `LegGeometryFormat`: https://docs.aws.amazon.com/location/latest/APIReference/API_CalculateRoutes.html
- Amazon Location `OptimizeWaypoints` (TSP with `AccessHours`, `ServiceDuration` and driver rest cycles): https://docs.aws.amazon.com/location/latest/developerguide/optimize-waypoints.html and https://docs.aws.amazon.com/location/latest/APIReference/API_OptimizeWaypoints.html

## Open questions for the backend owner

1. Can you compute an **access point** per kiln (the nearest drivable road point, ideally with a gate note from past visits)?
2. Leg geometry: `Simple`, simplified to GeoJSON (proposed), or `FlexiblePolyline` with a Swift decoder in KilnWatchCore?
3. OR-Tools vs Amazon Location `OptimizeWaypoints`: the latter orders a fixed set with time windows and service time, but it doesn't choose *which* kilns fit a 6-hour budget, "schools first". Keep OR-Tools for selection and consider `OptimizeWaypoints` for ordering only.
4. Confirm that Amazon Location route-matrix coverage and accuracy is acceptable on Hapur's rural roads (not verified here).
5. Re-planning mid-day (a skipped stop, a closed road): does the app call `plan_route` again with the remaining stops, or reorder locally?
