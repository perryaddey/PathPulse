import SwiftUI
import CoreLocation
import GoogleMaps

struct GoogleMapView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D?
    let destination: Destination?
    let route: WalkingRoute?
    let isLocationEnabled: Bool
    let recenterVersion: Int

    final class Coordinator {
        var lastRecenterVersion = -1
        var lastDestinationID: String?
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
     * Updates location visibility, markers, route geometry, and camera requests.
     *
     * @param uiView The existing Google map.
     * @param context The SwiftUI context containing the map coordinator.
     */
    func updateUIView(_ uiView: GMSMapView, context: Context) {
        uiView.isMyLocationEnabled = isLocationEnabled
        uiView.clear()
        if let destination {
            let marker = GMSMarker(position: destination.coordinate.locationCoordinate)
            marker.title = destination.name
            marker.snippet = destination.address
            marker.map = uiView
        }

        if let route {
            let path = GMSMutablePath()
            route.geometry.forEach { path.add($0.locationCoordinate) }
            let polyline = GMSPolyline(path: path)
            polyline.strokeColor = .systemBlue
            polyline.strokeWidth = 6
            polyline.zIndex = 1
            polyline.map = uiView
        }

        if let coordinate,
           context.coordinator.lastRecenterVersion != recenterVersion {
            context.coordinator.lastRecenterVersion = recenterVersion
            uiView.animate(to: GMSCameraPosition(target: coordinate, zoom: 16))
        }

        let destinationChanged =
            context.coordinator.lastDestinationID != destination?.id

        guard destinationChanged else { return }
        context.coordinator.lastDestinationID = destination?.id

        if let destination {
            uiView.animate(to: GMSCameraPosition(
                target: destination.coordinate.locationCoordinate,
                zoom: 16
            ))
        }
    }
}
