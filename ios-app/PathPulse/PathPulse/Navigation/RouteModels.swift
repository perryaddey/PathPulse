import Foundation
import CoreLocation

struct Coordinate: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
    }
}

struct DestinationSuggestion: Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
}

struct Destination: Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
    let coordinate: Coordinate
}

/// Preserve Google's vocabulary. Unknown maneuvers must never become a forward cue.
struct RouteManeuver: Equatable, Sendable {
    let rawValue: String

    enum Direction: Equatable {
        case left, right, straight, other
    }

    // Only exact basic maneuvers are categorized here. This is not a haptic policy.
    var direction: Direction {
        switch rawValue {
        case "TURN_LEFT": .left
        case "TURN_RIGHT": .right
        case "STRAIGHT": .straight
        default: .other
        }
    }
}

struct RouteStep: Identifiable, Equatable {
    let id: Int
    let maneuver: RouteManeuver
    let instruction: String
    let distanceMeters: Int
    let start: Coordinate
    let end: Coordinate
    let geometry: [Coordinate]
}

struct WalkingRoute: Identifiable, Equatable {
    let id: UUID
    let origin: Coordinate
    let destination: Destination
    let distanceMeters: Int
    let durationSeconds: TimeInterval
    let geometry: [Coordinate]
    let steps: [RouteStep]
    let warnings: [String]
}

enum NavigationError: LocalizedError {
    case missingSDKKey, missingRoutesKey, keychain, searchUnavailable, placeUnavailable
    case noRoute, invalidResponse, unauthorized, quotaExceeded, serverUnavailable
    case restrictionsNotEnforced

    var errorDescription: String? {
        switch self {
        case .missingSDKKey: "Maps are not configured yet. Follow the Google setup instructions in ios-app/README.md, then rebuild."
        case .missingRoutesKey: "Routing is not configured yet. Add the separate Routes API key using the setup instructions, then rebuild."
        case .keychain: "The routing credential could not be accessed securely. Unlock the phone and try again."
        case .searchUnavailable: "Destination search is unavailable. Check your connection and Maps configuration, then try again."
        case .placeUnavailable: "This destination could not be loaded. Search again or choose another result."
        case .noRoute: "No walking route was found. Try another nearby destination."
        case .invalidResponse: "The route response could not be read. Please try again."
        case .unauthorized: "Google rejected the routing request. Check the key, enabled APIs, billing, and iOS restrictions."
        case .quotaExceeded: "The routing request limit was reached. Try again later."
        case .serverUnavailable: "Routing is temporarily unavailable. Please try again."
        case .restrictionsNotEnforced: "Direct routing could not verify the key’s app restrictions. Check the Google setup instructions before enabling routing."
        }
    }
}

enum RouteFormatting {
    /**
     * Formats a distance for display using the user's locale and road-distance units.
     *
     * @param meters The distance in meters.
     * @return A localized distance string with an abbreviated unit.
     */
    static func distance(_ meters: Int) -> String {
        Measurement(value: Double(meters), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    /**
     * Formats a duration, rounding up to whole minutes with a one-minute minimum.
     *
     * @param seconds The duration in seconds.
     * @return A duration string in minutes, or hours and remaining minutes.
     */
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int(ceil(seconds / 60)))
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) hr \(minutes % 60) min"
    }
}
