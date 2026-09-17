//
//  ContentView.swift
//  PathPulse
//
//  Created by Perry Addey on 9/16/26.
//

import SwiftUI

struct ContentView: View {
    let mapsConfigured: Bool

    @State private var location = LocationService()
    @State private var search = DestinationSearchService()
    @State private var routeService = GoogleWalkingRouteService(
        key: Bundle.main.object(forInfoDictionaryKey: "GoogleMapsSDKKey") as? String
    )
    @State private var query = ""
    @State private var destination: Destination?
    @State private var walkingRoute: WalkingRoute?
    @State private var routeMessage: String?
    @State private var isSelecting = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if mapsConfigured {
                    VStack(spacing: 0) {
                        VStack(spacing: 8) {
                            if destination == nil {
                                TextField("Where do you want to go?", text: $query)
                                    .textFieldStyle(.roundedBorder)
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
                                    Button("Clear") { self.destination = nil; query = "" }
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

                            if let walkingRoute {
                                Label(
                                    "Walking route: \(RouteFormatting.distance(walkingRoute.distanceMeters)), \(RouteFormatting.duration(walkingRoute.durationSeconds))",
                                    systemImage: "figure.walk"
                                )
                                .font(.callout)
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
            .navigationTitle("PathPulse")
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
                    location.requestLocation()
                }
            }
        }
    }

    private var routeRequestID: String {
        guard let destination else { return "none" }
        let coordinate = location.coordinate
        return "\(destination.id):\(coordinate?.latitude ?? 0):\(coordinate?.longitude ?? 0)"
    }

    /**
     * Loads a walking route for the current location and selected destination.
     *
     * @return Nothing; updates the displayed route or an explanatory message.
     */
    private func loadWalkingRoute() async {
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
    ContentView(mapsConfigured: false)
}
