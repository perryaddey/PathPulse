import CoreLocation
import GooglePlaces
import Observation

@MainActor
@Observable
final class DestinationSearchService {
    private(set) var suggestions: [DestinationSuggestion] = []
    private(set) var isSearching = false
    private(set) var message: String?

    private let client = GMSPlacesClient.shared()
    private var sessionToken = GMSAutocompleteSessionToken()
    private var searchTask: Task<Void, Never>?
    private var queryGeneration = 0

    /**
     * Starts a debounced destination search for the supplied text.
     *
     * @param query The partial destination text entered by the user.
     * @param origin The current phone coordinate used to bias suggestions, when available.
     */
    func search(query: String, origin: CLLocationCoordinate2D?) {
        searchTask?.cancel()
        queryGeneration += 1
        let generation = queryGeneration
        suggestions = []
        message = nil
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { isSearching = false; return }
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.fetchSuggestions(query: trimmedQuery, origin: origin, generation: generation)
        }
    }

    /**
     * Resolves a selected autocomplete suggestion into an app-owned destination.
     *
     * @param suggestion The suggestion selected by the user.
     * @return The resolved destination, including its coordinate.
     * @throws NavigationError.placeUnavailable when Google cannot resolve the place.
     */
    func select(_ suggestion: DestinationSuggestion) async throws -> Destination {
        let fields: [String] = [
            GMSPlaceProperty.placeID,
            GMSPlaceProperty.name,
            GMSPlaceProperty.formattedAddress,
            GMSPlaceProperty.coordinate
        ].map(\.rawValue)

        let request = GMSFetchPlaceRequest(
            placeID: suggestion.id,
            placeProperties: fields,
            sessionToken: sessionToken
        )
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Destination, Error>) in
            client.fetchPlace(with: request) { place, error in
                guard error == nil, let place, let placeID = place.placeID,
                      let name = place.name, CLLocationCoordinate2DIsValid(place.coordinate) else {
                    continuation.resume(throwing: NavigationError.placeUnavailable)
                    return
                }
                continuation.resume(returning: Destination(
                    id: placeID, name: name,
                    address: place.formattedAddress ?? suggestion.address,
                    coordinate: Coordinate(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
                ))
            }
        }
    }

    /**
     * Starts a fresh autocomplete billing session after a destination is selected.
     */
    func endSession() { sessionToken = GMSAutocompleteSessionToken() }

    /**
     * Publishes a user-facing error from a failed place selection.
     *
     * @param error The error whose localized message should be shown.
     */
    func show(error: Error) {
        message = error.localizedDescription
    }

    /**
     * Requests autocomplete suggestions and publishes only the latest response.
     *
     * @param query The debounced search text.
     * @param origin The optional coordinate used to bias results.
     * @param generation The request generation used to reject stale responses.
     */
    private func fetchSuggestions(query: String, origin: CLLocationCoordinate2D?, generation: Int) async {
        let request = GMSAutocompleteRequest(query: query)
        request.sessionToken = sessionToken
        if let origin {
            let filter = GMSAutocompleteFilter()
            filter.origin = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            request.filter = filter
        }
        client.fetchAutocompleteSuggestions(from: request) { [weak self] results, error in
            guard let self else { return }
            Task { @MainActor in
                guard generation == self.queryGeneration else { return }
                self.isSearching = false
                guard error == nil, let results else {
                    self.message = NavigationError.searchUnavailable.localizedDescription
                    return
                }
                self.suggestions = results.compactMap { result in
                    guard let place = result.placeSuggestion else { return nil }
                    return DestinationSuggestion(id: place.placeID,
                        name: place.attributedPrimaryText.string,
                        address: place.attributedSecondaryText?.string ?? "")
                }
            }
        }
    }
}
