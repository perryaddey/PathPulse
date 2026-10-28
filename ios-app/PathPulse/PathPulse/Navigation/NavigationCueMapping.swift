import Foundation

enum NavigationWrist: Hashable {
    case left
    case right
}

struct NavigationCue: Equatable {
    let command: UInt8
    let wrists: Set<NavigationWrist>
}

enum ManeuverCueDisposition: Equatable {
    case noCue
    case cue(NavigationCue)
    case unsupported
}

enum NavigationCueMapper {
    /**
     * Maps Google's raw maneuver value to an existing wristband command.
     * Unknown and unsupported maneuvers never produce a directional cue.
     * @param maneuver The raw maneuver returned for a route step.
     * @return Whether to skip vibration, send a supported cue, or pause as unsupported.
     */
    static func disposition(for maneuver: RouteManeuver) -> ManeuverCueDisposition {
        switch maneuver.rawValue {
        case "TURN_LEFT": .cue(NavigationCue(command: 1, wrists: [.left]))
        case "TURN_RIGHT": .cue(NavigationCue(command: 1, wrists: [.right]))
        case "TURN_SLIGHT_LEFT", "FORK_LEFT": .cue(NavigationCue(command: 2, wrists: [.left]))
        case "TURN_SLIGHT_RIGHT", "FORK_RIGHT": .cue(NavigationCue(command: 2, wrists: [.right]))
        case "TURN_SHARP_LEFT": .cue(NavigationCue(command: 5, wrists: [.left]))
        case "TURN_SHARP_RIGHT": .cue(NavigationCue(command: 5, wrists: [.right]))
        case "STRAIGHT": .cue(NavigationCue(command: 3, wrists: [.left, .right]))
        case "DEPART", "NAME_CHANGE": .noCue
        case "UTURN_LEFT", "UTURN_RIGHT", "RAMP_LEFT", "RAMP_RIGHT", "MERGE",
             "ROUNDABOUT_LEFT", "ROUNDABOUT_RIGHT", "FERRY", "FERRY_TRAIN",
             "MANEUVER_UNSPECIFIED": .unsupported
        default: .unsupported
        }
    }
}
