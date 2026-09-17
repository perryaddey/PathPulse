import CoreLocation
import Observation

@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var isLoading = false
    private(set) var message: String?
    private(set) var isAuthorized = false
    private(set) var recenterVersion = 0

    private let manager = CLLocationManager()
    private var hasRequestedLocation = false

    /**
     * Configures foreground location requests without prompting for permission.
     */
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /**
     * Requests permission if needed, then requests one location fix.
     * Reports unavailable access through the observable message property.
     */
    func requestLocation() {
        hasRequestedLocation = true
        guard !isLoading else { return }
        message = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()

        case .authorizedWhenInUse, .authorizedAlways:
            isAuthorized = true
            isLoading = true
            manager.requestLocation()

        case .denied:
            isAuthorized = false
            coordinate = nil
            message = "Allow location access in Settings to center the map."

        case .restricted:
            isAuthorized = false
            coordinate = nil
            message = "Location access is restricted on this device."

        @unknown default:
            isAuthorized = false
            coordinate = nil
            message = "Location access is unavailable."
        }
    }

    /**
     * Updates permission state and resumes a requested location lookup.
     *
     * @param manager The location manager reporting authorization changes.
     */
    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        isAuthorized =
            manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways

        if !isAuthorized {
            coordinate = nil
            isLoading = false
        }

        if hasRequestedLocation {
            requestLocation()
        }
    }

    /**
     * Publishes a recent valid location and requests a map recenter.
     *
     * @param manager The location manager supplying the update.
     * @param locations The locations supplied by Core Location.
     */
    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        isLoading = false

        guard isAuthorized else { return }

        guard let location = locations.last(where: {
            $0.horizontalAccuracy >= 0
                && abs($0.timestamp.timeIntervalSinceNow) <= 60
                && CLLocationCoordinate2DIsValid($0.coordinate)
        }) else {
            message = "A recent location is unavailable. Try My location again."
            return
        }

        coordinate = location.coordinate
        message = nil
        recenterVersion += 1
    }

    /**
     * Ends a failed lookup and exposes a retry message.
     *
     * @param manager The location manager reporting the failure.
     * @param error The error returned by Core Location.
     */
    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        isLoading = false
        message = "Couldn't get your location. Check location access and try again."
    }
}
