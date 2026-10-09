import CoreLocation
import SwiftUI

/// An intentional, one-shot location request; no background capability or continuous tracking.
@MainActor @Observable
final class ForegroundLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var awaitingAuthorization = false
    private var active = false
    private var requesting = false
    var authorized = false
    var notice: String?
    var settingsAvailable = false
    var coordinate: CLLocationCoordinate2D?
    var fixSerial = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorized = [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus)
    }
    func setActive(_ active: Bool) {
        self.active = active
        if !active { awaitingAuthorization = false; requesting = false; manager.stopUpdatingLocation() }
    }
    func recenter() {
        notice = nil; settingsAvailable = false
        guard active else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            notice = "Location services are turned off. You can still browse the route and open Maps."
            settingsAvailable = true; return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            awaitingAuthorization = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            requestFix()
        case .denied, .restricted:
            notice = "Location access is unavailable. You can still browse the route and open Maps."
            settingsAvailable = manager.authorizationStatus == .denied
        @unknown default:
            notice = "Location is temporarily unavailable. Try again."
        }
    }
    private func requestFix() {
        guard active else { return }
        requesting = true
        notice = "Finding your location…"
        manager.requestLocation()
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorized = [.authorizedAlways, .authorizedWhenInUse].contains(status)
            if self.awaitingAuthorization {
                self.awaitingAuthorization = false
                self.recenter()
            }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0 else { return }
        let latitude = fix.coordinate.latitude, longitude = fix.coordinate.longitude
        let approximate = manager.accuracyAuthorization == .reducedAccuracy
        Task { @MainActor [weak self] in
            guard let self, self.active, self.requesting else { return }
            self.requesting = false
            self.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            self.notice = approximate ? "Approximate location · route browsing remains available" : nil
            self.fixSerial += 1
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in
            guard let self, self.active, self.requesting else { return }
            self.requesting = false
            self.notice = "No location fix yet. Try again, or navigate with Maps."
        }
    }
}
