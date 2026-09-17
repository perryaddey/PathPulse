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
    @State private var query = ""
    @State private var destination: Destination?
    @State private var isSelecting = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if mapsConfigured {
                    VStack(spacing: 0) {
                        VStack(spacing: 8) {
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
                                            destination = try await search.select(suggestion)
                                            query = destination?.name ?? suggestion.name
                                            search.endSession()
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
            .onChange(of: scenePhase) { _, phase in
                if mapsConfigured && phase == .active {
                    location.requestLocation()
                }
            }
        }
    }
}

#Preview {
    ContentView(mapsConfigured: false)
}
