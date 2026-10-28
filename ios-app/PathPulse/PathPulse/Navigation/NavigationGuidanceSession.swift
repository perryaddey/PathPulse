import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class NavigationGuidanceSession {
    private(set) var status = "Connect both wristbands before starting guidance."
    private(set) var nextInstruction = ""
    private(set) var isActive = false

    private var route: WalkingRoute?
    private var tracker: RouteProgressTracker?
    private var nextStepIndex = 0
    private var offRouteFixDates: [Date] = []
    private var rerouteInProgress = false
    private var lastRerouteRequestDate: Date?

    /**
     * Starts foreground route guidance after validating both wristband connections.
     * @param route The route whose steps will drive vibration cues.
     * @param bluetooth The app's shared wristband connection service.
     * @return Whether guidance started successfully.
     */
    func start(route: WalkingRoute, bluetooth: BluetoothService) -> Bool {
        guard bluetooth.left.isReady, bluetooth.right.isReady else {
            status = "Connect both wristbands in Bluetooth before starting guidance."
            return false
        }
        guard let tracker = RouteProgressTracker(route: route) else {
            status = "This route has no usable walking geometry. Reload the route to try again."
            return false
        }
        self.route = route
        self.tracker = tracker
        nextStepIndex = 0
        offRouteFixDates = []
        rerouteInProgress = false
        lastRerouteRequestDate = nil
        isActive = true
        status = "Guidance is active. Keep PathPulse open in the foreground for this trial."
        updateNextInstruction(progress: 0)
        return true
    }

    /**
     * Processes one fresh location, sends a due cue, or requests an off-route reroute.
     * @param location The latest Core Location fix.
     * @param bluetooth The app's shared wristband connection service.
     * @return The current coordinate when a confirmed off-route reroute should begin.
     */
    func update(location: CLLocation, bluetooth: BluetoothService) -> Coordinate? {
        guard isActive, !rerouteInProgress, let route, var tracker else { return nil }
        guard bluetooth.left.isReady, bluetooth.right.isReady else {
            pause(message: "A wristband disconnected. Guidance paused.", bluetooth: bluetooth)
            return nil
        }

        let assessment = tracker.update(location: location)
        guard case .onRoute(let reading) = assessment else {
            if case .offRoute = assessment {
                offRouteFixDates.append(location.timestamp)
                offRouteFixDates = offRouteFixDates.filter {
                    location.timestamp.timeIntervalSince($0) <= 10
                }
                let span = offRouteFixDates.last!.timeIntervalSince(offRouteFixDates.first!)
                status = "Checking off-route position (\(offRouteFixDates.count)/3)."
                if offRouteFixDates.count >= 3, span >= 5,
                   lastRerouteRequestDate.map({ Date().timeIntervalSince($0) >= 10 }) ?? true {
                    rerouteInProgress = true
                    lastRerouteRequestDate = Date()
                    status = "You appear off route. Getting an updated route…"
                    return Coordinate(latitude: location.coordinate.latitude,
                                      longitude: location.coordinate.longitude)
                }
            } else {
                status = "Waiting for a clear, recent location fix."
            }
            return nil
        }
        offRouteFixDates = []
        self.tracker = tracker

        guard isActive else { return nil }
        /*
         * A passed cue point is not enough to conclude that the wearer left the route.
         * Continue tracking along the planned geometry and reroute only after confirmed
         * off-route fixes.
         */
        while nextStepIndex < route.steps.count {
            let step = route.steps[nextStepIndex]
            guard let maneuverStart = tracker.startMeters(forStep: nextStepIndex) else {
                pause(message: "Route progress is unavailable. Guidance paused.", bluetooth: bluetooth)
                return nil
            }
            let remainingMeters = maneuverStart - reading.metersAlongRoute
            let disposition = NavigationCueMapper.disposition(for: step.maneuver)

            if case .noCue = disposition {
                if remainingMeters <= 0 {
                    nextStepIndex += 1
                    continue
                }
                status = "Following route."
                updateNextInstruction(progress: reading.metersAlongRoute)
                return nil
            }

            if remainingMeters < -max(5, reading.horizontalAccuracy) {
                if case .cue = disposition {
                    nextStepIndex += 1
                    status = "Turn point passed. Checking your route position."
                    updateNextInstruction(progress: reading.metersAlongRoute)
                    return nil
                }
                if case .unsupported = disposition {
                    pause(message: "Unsupported maneuver passed: \(step.instruction). Guidance paused.",
                          bluetooth: bluetooth)
                    return nil
                }
            }

            if remainingMeters > 10 {
                status = "Following route."
                updateNextInstruction(progress: reading.metersAlongRoute)
                return nil
            }

            switch disposition {
            case .cue(let cue):
                for wrist in cue.wrists {
                    bluetooth.send(cue.command, to: bluetoothWrist(for: wrist))
                }
                nextStepIndex += 1
                status = "Turn cue sent: \(step.instruction)"
                updateNextInstruction(progress: reading.metersAlongRoute)
                return nil
            case .unsupported:
                pause(message: "Unsupported maneuver: \(step.instruction). Guidance paused.",
                      bluetooth: bluetooth)
                return nil
            case .noCue:
                break
            }
        }

        if tracker.metersRemaining <= 10 {
            status = "Near the destination."
            nextInstruction = ""
        } else {
            status = "Following the final route segment."
            nextInstruction = "Continue to destination · about \(RouteFormatting.distance(Int(tracker.metersRemaining.rounded())))"
        }
        return nil
    }

    /**
     * Replaces the active route after a successful request from the user's location.
     * @param route The newly calculated route to the selected destination.
     * @return Whether the route has usable geometry and guidance remains active.
     */
    func completeReroute(with route: WalkingRoute, bluetooth: BluetoothService) -> Bool {
        guard isActive, rerouteInProgress, let tracker = RouteProgressTracker(route: route) else {
            failReroute(message: "The updated route could not be followed.", bluetooth: bluetooth)
            return false
        }
        self.route = route
        self.tracker = tracker
        nextStepIndex = 0
        offRouteFixDates = []
        rerouteInProgress = false
        status = "Route updated from your current location."
        updateNextInstruction(progress: 0)
        return true
    }

    /**
     * Pauses guidance after a reroute request fails.
     * @param message The route error shown to the user.
     * @param bluetooth The app's shared wristband connection service.
     */
    func failReroute(message: String, bluetooth: BluetoothService) {
        guard rerouteInProgress else { return }
        rerouteInProgress = false
        pause(message: message, bluetooth: bluetooth)
    }

    /**
     * Stops guidance and sends stop commands to every connected wristband.
     * @param bluetooth The app's shared wristband connection service.
     */
    func stop(bluetooth: BluetoothService) {
        bluetooth.stopAll()
        isActive = false
        route = nil
        tracker = nil
        nextStepIndex = 0
        offRouteFixDates = []
        rerouteInProgress = false
        nextInstruction = ""
        status = "Guidance ended."
    }

    /**
     * Pauses active guidance if either wristband is no longer ready.
     * @param bluetooth The app's shared wristband connection service.
     */
    func checkConnections(bluetooth: BluetoothService) {
        guard isActive, !bluetooth.left.isReady || !bluetooth.right.isReady else { return }
        pause(message: "A wristband disconnected. Guidance paused.", bluetooth: bluetooth)
    }

    /**
     * Stops active cues and records a pause message.
     * @param message The reason shown in the navigation screen.
     * @param bluetooth The app's shared wristband connection service.
     */
    private func pause(message: String, bluetooth: BluetoothService) {
        bluetooth.stopAll()
        isActive = false
        rerouteInProgress = false
        status = message
    }

    /**
     * Updates the displayed next step and remaining route distance.
     * @param progress Current matched distance along the route in meters.
     */
    private func updateNextInstruction(progress: Double) {
        guard let route, let tracker, nextStepIndex < route.steps.count,
              let start = tracker.startMeters(forStep: nextStepIndex) else {
            nextInstruction = ""
            return
        }
        let step = route.steps[nextStepIndex]
        let disposition = NavigationCueMapper.disposition(for: step.maneuver)
        guard case .noCue = disposition else {
            let remaining = max(0, Int((start - progress).rounded()))
            nextInstruction = "Next: \(step.instruction) · about \(RouteFormatting.distance(remaining))"
            return
        }
        nextInstruction = "Following route."
    }

    /**
     * Converts the navigation-layer wrist designation to its Bluetooth connection.
     * @param wrist The wrist selected by the maneuver mapping.
     * @return The corresponding Bluetooth service wrist.
     */
    private func bluetoothWrist(for wrist: NavigationWrist) -> BluetoothService.Wrist {
        wrist == .left ? .left : .right
    }
}
