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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if mapsConfigured {
                    VStack(spacing: 0) {
                        GoogleMapView(
                            coordinate: location.coordinate,
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
