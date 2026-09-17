import Foundation

@MainActor
protocol WalkingRouteProviding {
    /**
     * Requests a walking route between an origin and a selected destination.
     *
     * @param origin The route's starting coordinate in degrees.
     * @param destination The selected destination and its geographic coordinate.
     * @return A walking route with geometry, ordered steps, and available warnings.
     * @throws An error if routing fails or the request is cancelled.
     */
    func route(from origin: Coordinate, to destination: Destination) async throws -> WalkingRoute
}

@MainActor
protocol RouteHTTPTransport {
    /**
     * Sends an HTTP request and retrieves its response.
     *
     * @param request The HTTP request to send.
     * @return The response body and HTTP response metadata.
     * @throws An error if transport fails or an HTTP response cannot be obtained.
     */
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionRouteTransport: RouteHTTPTransport {
    // No disk cache or persistent route history.
    private let session = URLSession(configuration: .ephemeral)

    /**
     * Sends a request using an ephemeral session without a persistent disk cache.
     *
     * @param request The HTTP request to send.
     * @return The response body and HTTP metadata, including non-success status codes.
     * @throws A URLSession error on transport failure or cancellation, or
     *         NavigationError.invalidResponse if the response is not HTTP.
     */
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NavigationError.invalidResponse }
        return (data, http)
    }
}

@MainActor
final class GoogleWalkingRouteService: WalkingRouteProviding {
    private let key: String?
    private let bundleID: String
    private let transport: any RouteHTTPTransport
    private var verifiedRestrictions = false

    /**
     * Configures the routing service without sending network requests.
     *
     * @param key The restricted Routes API key, or nil when routing is not configured.
     * @param bundleID The iOS bundle identifier sent with routing requests.
     * @param transport The HTTP transport used for routing and restriction checks,
     *                  or nil to create the default URLSession transport on the main actor.
     */
    init(
        key: String?,
        bundleID: String = Bundle.main.bundleIdentifier
            ?? "com.perryaddey.PathPulse",
        transport: (any RouteHTTPTransport)? = nil
    ) {
        self.key = key
        self.bundleID = bundleID
        self.transport = transport ?? URLSessionRouteTransport()
    }

    /**
     * Fetches a walking route after checking that the endpoint rejects missing and
     * incorrect app identifiers. Reuses successful verification for this service instance.
     *
     * @param origin The route's starting coordinate in degrees.
     * @param destination The selected destination and its geographic coordinate.
     * @return The decoded walking route, preserving Google's maneuver values.
     * @throws NavigationError for missing configuration, failed restriction checks,
     *         rejected requests, unavailable routes, or invalid responses;
     *         propagates transport and cancellation errors.
     */
    func route(from origin: Coordinate, to destination: Destination) async throws -> WalkingRoute {
        guard let key, !key.isEmpty else { throw NavigationError.missingRoutesKey }
        guard origin.isValid, destination.coordinate.isValid else { throw NavigationError.invalidResponse }
        let request = try Self.request(origin: origin, destination: destination, key: key, bundleID: bundleID)

        // Test the actual endpoint, with the same valid body. A generic HTTP error isn't proof:
        // invalid/missing identifiers must receive PERMISSION_DENIED, then the real call must succeed.
        if !verifiedRestrictions {
            for identifier: String? in [nil, "invalid.pathpulse.restriction-check"] {
                try Task.checkCancellation()
                var probe = request
                probe.setValue(identifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
                let (data, response) = try await transport.data(for: probe)
                let status = try? JSONDecoder().decode(GoogleErrorResponse.self, from: data).error.status
                guard response.statusCode == 403, status == "PERMISSION_DENIED" else {
                    throw NavigationError.restrictionsNotEnforced
                }
            }
        }

        try Task.checkCancellation()
        let (data, response) = try await transport.data(for: request)
        switch response.statusCode {
        case 200...299: break
        case 401, 403: throw NavigationError.unauthorized
        case 429: throw NavigationError.quotaExceeded
        case 500...599: throw NavigationError.serverUnavailable
        default: throw NavigationError.invalidResponse
        }
        let route = try Self.decode(data, origin: origin, destination: destination)
        verifiedRestrictions = true
        return route
    }

    /**
     * Builds a walking-route request with restricted response fields without sending it.
     *
     * @param origin The starting coordinate in degrees.
     * @param destination The destination whose coordinate is used as the route endpoint.
     * @param key The Routes API key placed in the authentication header.
     * @param bundleID The iOS bundle identifier placed in the app-restriction header.
     * @return A POST request for one walking route with geometry and maneuver steps.
     * @throws An encoding error if the request body cannot be serialized as JSON.
     */
    static func request(origin: Coordinate, destination: Destination, key: String, bundleID: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.setValue([
            "routes.distanceMeters", "routes.duration", "routes.polyline.encodedPolyline", "routes.warnings",
            "routes.legs.steps.distanceMeters", "routes.legs.steps.startLocation",
            "routes.legs.steps.endLocation", "routes.legs.steps.polyline.encodedPolyline",
            "routes.legs.steps.navigationInstruction"
        ].joined(separator: ","), forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = try JSONEncoder().encode(RouteRequest(
            origin: .init(location: .init(latLng: origin)),
            destination: .init(location: .init(latLng: destination.coordinate))))
        return request
    }

    /**
     * Validates and converts the first Google route response into app-owned models.
     *
     * @param data The JSON response body returned by the Routes API.
     * @param origin The requested starting coordinate, retained in the resulting route.
     * @param destination The selected destination, retained in the resulting route.
     * @return A walking route with decoded geometry, duration in seconds,
     *         distances in meters, and unmodified maneuver values.
     * @throws NavigationError.noRoute when no route is returned, or
     *         NavigationError.invalidResponse when response data or geometry is invalid.
     */
    static func decode(_ data: Data, origin: Coordinate, destination: Destination) throws -> WalkingRoute {
        let response: RoutesResponse
        do { response = try JSONDecoder().decode(RoutesResponse.self, from: data) }
        catch { throw NavigationError.invalidResponse }
        guard let route = response.routes?.first else { throw NavigationError.noRoute }
        guard route.distanceMeters >= 0, route.duration.hasSuffix("s"),
              let duration = Double(route.duration.dropLast()), duration.isFinite, duration >= 0 else {
            throw NavigationError.invalidResponse
        }
        let geometry = try PolylineDecoder.decode(route.polyline.encodedPolyline)
        guard geometry.count >= 2 else { throw NavigationError.invalidResponse }
        let steps = try route.legs.flatMap(\.steps).enumerated().map { index, step in
            guard step.startLocation.latLng.isValid, step.endLocation.latLng.isValid,
                  (step.distanceMeters ?? 0) >= 0 else { throw NavigationError.invalidResponse }
            return RouteStep(id: index,
                             maneuver: RouteManeuver(rawValue: step.navigationInstruction?.maneuver ?? "MANEUVER_UNSPECIFIED"),
                             instruction: step.navigationInstruction?.instructions ?? "Continue along the route",
                             distanceMeters: step.distanceMeters ?? 0,
                             start: step.startLocation.latLng, end: step.endLocation.latLng,
                             geometry: try PolylineDecoder.decode(step.polyline?.encodedPolyline ?? ""))
        }
        guard !steps.isEmpty else { throw NavigationError.invalidResponse }
        return WalkingRoute(id: UUID(), origin: origin, destination: destination,
                            distanceMeters: route.distanceMeters, durationSeconds: duration,
                            geometry: geometry, steps: steps, warnings: route.warnings ?? [])
    }
}

private struct RouteRequest: Encodable {
    struct Waypoint: Encodable { let location: RouteLocation }
    let origin: Waypoint
    let destination: Waypoint
    let travelMode = "WALK"
    let computeAlternativeRoutes = false
    let polylineQuality = "HIGH_QUALITY"
    let polylineEncoding = "ENCODED_POLYLINE"
}

private struct RouteLocation: Codable { let latLng: Coordinate }
private struct EncodedPolyline: Decodable { let encodedPolyline: String }
private struct GoogleErrorResponse: Decodable {
    struct APIError: Decodable { let status: String }
    let error: APIError
}

private struct RoutesResponse: Decodable {
    struct Route: Decodable {
        struct Leg: Decodable {
            struct Step: Decodable {
                struct Instruction: Decodable { let maneuver: String?; let instructions: String? }
                let distanceMeters: Int?
                let startLocation: RouteLocation
                let endLocation: RouteLocation
                let polyline: EncodedPolyline?
                let navigationInstruction: Instruction?
            }
            let steps: [Step]
        }
        let distanceMeters: Int
        let duration: String
        let polyline: EncodedPolyline
        let legs: [Leg]
        let warnings: [String]?
    }
    let routes: [Route]?
}
