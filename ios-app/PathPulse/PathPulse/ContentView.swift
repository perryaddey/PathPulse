//
//  ContentView.swift
//  PathPulse
//
//  Created by Perry Addey on 9/16/26.
//

import SwiftUI
import CoreLocation

struct ContentView: View {
    let mapsConfigured: Bool
    let bluetooth: BluetoothService

    @State private var location = LocationService()
    @State private var guidance = NavigationGuidanceSession()
    @State private var rerouteTask: Task<Void, Never>?
    @State private var search = DestinationSearchService()
    @State private var routeService = GoogleWalkingRouteService(
        key: Bundle.main.object(forInfoDictionaryKey: "GoogleMapsSDKKey") as? String
    )
    @State private var query = ""
    @State private var destination: Destination?
    @State private var walkingRoute: WalkingRoute?
    @State private var routeMessage: String?
    @State private var isNavigationStarted = false
    @State private var isSelecting = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if mapsConfigured {
                    if isNavigationStarted, let walkingRoute {
                        RouteDirectionsView(route: walkingRoute,
                                            guidanceStatus: guidance.status,
                                            nextInstruction: guidance.nextInstruction,
                                            locationMessage: location.message) {
                            endNavigation()
                        }
                    } else {
                        VStack(spacing: 0) {
                            VStack(spacing: 8) {
                                if destination == nil {
                                TextField("Where do you want to go?", text: $query)
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .foregroundStyle(.white)
                                    .background(PathPulseBrand.card)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(PathPulseBrand.accent.opacity(0.28), lineWidth: 1)
                                    }
                                    .onChange(of: query) { _, value in
                                        search.search(query: value, origin: location.coordinate)
                                    }
                                    .accessibilityLabel("Destination")

                                if search.isSearching { ProgressView("Searching…") }
                                if let message = search.message {
                                    Text(message).font(.callout).foregroundStyle(.secondary)
                                }

                                ForEach(search.suggestions) { suggestion in
                                    Button {
                                        isSelecting = true
                                        Task {
                                            defer { isSelecting = false }
                                            do {
                                                let selected = try await search.select(suggestion)
                                                search.endSession()
                                                query = ""
                                                isNavigationStarted = false
                                                destination = selected
                                            } catch {
                                                search.show(error: error)
                                            }
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.name).font(.headline)
                                            Text(suggestion.address).font(.subheadline).foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isSelecting)
                                    .accessibilityElement(children: .combine)
                                }
                            }

                            if let destination {
                                HStack {
                                    Label(destination.name, systemImage: "mappin.and.ellipse")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button("Clear") {
                                        self.destination = nil
                                        walkingRoute = nil
                                        isNavigationStarted = false
                                        query = ""
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        GoogleMapView(
                            coordinate: location.coordinate,
                            destination: destination,
                            route: walkingRoute,
                            isLocationEnabled: location.isAuthorized
                                && scenePhase == .active,
                            recenterVersion: location.recenterVersion
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal)
                        .padding(.vertical, 10)

                        if let walkingRoute {
                            if !isNavigationStarted {
                                VStack(spacing: 10) {
                                    Label(
                                        "Walking route: \(RouteFormatting.distance(walkingRoute.distanceMeters)), \(RouteFormatting.duration(walkingRoute.durationSeconds))",
                                        systemImage: "figure.walk"
                                    )
                                    .font(.callout)

                                    Button {
                                        startNavigation(for: walkingRoute)
                                    } label: {
                                        Label("Start", systemImage: "play.fill")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)

                                    if !bluetooth.left.isReady || !bluetooth.right.isReady {
                                        NavigationLink {
                                            BluetoothView(bluetooth: bluetooth)
                                        } label: {
                                            Label("Connect both wristbands", systemImage: "dot.radiowaves.left.and.right")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    if let routeMessage {
                                        Text(routeMessage)
                                            .font(.callout)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 10)
                            }
                        }

                        VStack(spacing: 12) {
                            if let message = location.message {
                                Text(message)
                                    .font(.callout)
                                    .multilineTextAlignment(.center)
                            }

                            if location.isLoading {
                                ProgressView("Finding your location…")
                            }

                            if let routeMessage {
                                Text(routeMessage)
                                    .font(.callout)
                                    .multilineTextAlignment(.center)
                            }

                            Button {
                                location.requestLocation()
                            } label: {
                                Label("My location", systemImage: "location")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(location.isLoading)
                            .accessibilityHint(
                                "Centers the map on your current location."
                            )
                        }
                        .padding()
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Map setup needed",
                        systemImage: "map",
                        description: Text(
                            "Configure your local Google Maps key and rebuild."
                        )
                    )
                }
            }
            .background(PathPulseBrand.background.ignoresSafeArea())
            .navigationTitle("Navigation")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if mapsConfigured {
                    location.requestLocation()
                }
            }
            .task(id: routeRequestID) {
                await loadWalkingRoute()
            }
            .onChange(of: scenePhase) { _, phase in
                if mapsConfigured && phase == .active {
                    if isNavigationStarted {
                        location.startNavigationUpdates()
                    } else {
                        location.requestLocation()
                    }
                }
            }
            .onChange(of: location.navigationFixVersion) { _, _ in
                guard isNavigationStarted, let fix = location.latestLocation else { return }
                if let origin = guidance.update(location: fix, bluetooth: bluetooth) {
                    requestReroute(from: origin)
                }
            }
            .onChange(of: bluetooth.left.isReady) { _, _ in
                guidance.checkConnections(bluetooth: bluetooth)
            }
            .onChange(of: bluetooth.right.isReady) { _, _ in
                guidance.checkConnections(bluetooth: bluetooth)
            }
        }
    }

    private var routeRequestID: String {
        if isNavigationStarted {
            return "active:\(destination?.id ?? "none")"
        }
        if let walkingRoute {
            return "\(walkingRoute.destination.id):\(walkingRoute.origin.latitude):\(walkingRoute.origin.longitude)"
        }
        guard let destination else { return "none" }
        let coordinate = location.coordinate
        return "\(destination.id):\(coordinate?.latitude ?? 0):\(coordinate?.longitude ?? 0)"
    }

    /**
     * Starts navigation only when both wristbands and route tracking are ready.
     * @param route The walking route to follow.
     */
    private func startNavigation(for route: WalkingRoute) {
        routeMessage = nil
        guard guidance.start(route: route, bluetooth: bluetooth) else {
            routeMessage = guidance.status
            return
        }
        isNavigationStarted = true
        location.startNavigationUpdates()
    }

    /** Stops location updates and wristband playback when navigation ends. */
    private func endNavigation() {
        rerouteTask?.cancel()
        rerouteTask = nil
        location.stopNavigationUpdates()
        guidance.stop(bluetooth: bluetooth)
        isNavigationStarted = false
    }

    /**
     * Requests a replacement walking route from a confirmed off-route location.
     * @param origin The latest usable user coordinate.
     */
    private func requestReroute(from origin: Coordinate) {
        guard let destination, isNavigationStarted else { return }
        rerouteTask?.cancel()
        rerouteTask = Task {
            do {
                let updatedRoute = try await routeService.route(from: origin, to: destination)
                guard !Task.isCancelled, isNavigationStarted else { return }
                walkingRoute = updatedRoute
                _ = guidance.completeReroute(with: updatedRoute, bluetooth: bluetooth)
                routeMessage = nil
                rerouteTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                let detail = (error as? LocalizedError)?.errorDescription
                    ?? "The route request failed."
                guidance.failReroute(message: "Couldn't reroute. Guidance paused. \(detail)",
                                     bluetooth: bluetooth)
                rerouteTask = nil
            }
        }
    }

    /**
     * Loads a walking route for the current location and selected destination.
     *
     * @return Nothing; updates the displayed route or an explanatory message.
     */
    private func loadWalkingRoute() async {
        guard !isNavigationStarted, walkingRoute == nil else { return }
        walkingRoute = nil
        routeMessage = nil
        guard let destination, let coordinate = location.coordinate else { return }

        routeMessage = "Loading walking route…"
        do {
            walkingRoute = try await routeService.route(from: Coordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ), to: destination)
            routeMessage = nil
        } catch is CancellationError {
            return
        } catch {
            routeMessage = (error as? LocalizedError)?.errorDescription
                ?? "The walking route could not be loaded. Please try again."
        }
    }
}

#Preview {
    ContentView(mapsConfigured: false, bluetooth: BluetoothService())
}
