//
//  PathPulseApp.swift
//  PathPulse
//
//  Created by Perry Addey on 9/16/26.
//

import SwiftUI
import GoogleMaps
import GooglePlaces

@main
struct PathPulseApp: App {
    private let mapsConfigured: Bool

    /**
     * Initializes Google's SDKs using the locally configured API key.
     */
    init() {
        let key = (Bundle.main.object(
            forInfoDictionaryKey: "GoogleMapsSDKKey"
        ) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if key.isEmpty || key.contains("$(") || key.hasPrefix("YOUR_") {
            mapsConfigured = false
        } else {
            mapsConfigured = GMSServices.provideAPIKey(key)
            GMSPlacesClient.provideAPIKey(key)
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView(mapsConfigured: mapsConfigured)
                .preferredColorScheme(.dark)
        }
    }
}
