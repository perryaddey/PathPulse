import SwiftUI
import GoogleMaps

struct GoogleMapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D?
    let isLocationEnabled: Bool
    let recenterVersion: Int

    final class Coordinator {
        var lastRecenterVersion = -1
    }

    /**
     * Creates storage for the last applied recenter request.
     *
     * @return The map's update coordinator.
     */
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /**
     * Creates an interactive map with its attribution visible.
     *
     * @param context The SwiftUI context for creating the map.
     * @return A Google map initially showing a world view.
     */
    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(
            latitude: 0,
            longitude: 0,
            zoom: 2
        )
        return GMSMapView(options: options)
    }

    /**
     * Updates location visibility and applies new recenter requests.
     *
     * @param uiView The existing Google map.
     * @param context The SwiftUI context containing the map coordinator.
     */
    func updateUIView(_ uiView: GMSMapView, context: Context) {
        uiView.isMyLocationEnabled = isLocationEnabled

        guard let coordinate,
              context.coordinator.lastRecenterVersion != recenterVersion
        else { return }

        context.coordinator.lastRecenterVersion = recenterVersion
        uiView.animate(to: GMSCameraPosition(
            target: coordinate,
            zoom: 16
        ))
    }
}
