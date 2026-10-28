import CoreLocation
import Foundation

struct RouteProgressReading {
    let metersAlongRoute: Double
    let horizontalAccuracy: Double
}

enum RouteProgressAssessment {
    case onRoute(RouteProgressReading)
    case offRoute(distanceFromRoute: Double, horizontalAccuracy: Double)
    case uncertain
}

struct RouteProgressTracker {
    private struct Segment {
        let start: Coordinate
        let end: Coordinate
        let startMeters: Double
        let lengthMeters: Double

        var endMeters: Double { startMeters + lengthMeters }
    }

    private struct Candidate {
        let metersAlongRoute: Double
        let distanceFromRoute: Double
    }

    private let segments: [Segment]
    private let stepStartMeters: [Double]
    private let routeLengthMeters: Double
    private(set) var metersAlongRoute = 0.0
    private var hasInitialMatch = false
    private var lastAcceptedTimestamp: Date?

    var metersRemaining: Double {
        max(0, routeLengthMeters - metersAlongRoute)
    }

    /**
     * Builds route-distance indexes for the route polyline and its ordered steps.
     * @param route The walking route whose geometry will be tracked.
     */
    init?(route: WalkingRoute) {
        guard route.geometry.count >= 2 else { return nil }
        var builtSegments: [Segment] = []
        var accumulatedMeters = 0.0
        for index in 1..<route.geometry.count {
            let start = route.geometry[index - 1]
            let end = route.geometry[index]
            let length = CLLocation(latitude: start.latitude, longitude: start.longitude)
                .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
            guard length.isFinite else { return nil }
            if length > 0 {
                builtSegments.append(Segment(start: start, end: end,
                                             startMeters: accumulatedMeters,
                                             lengthMeters: length))
                accumulatedMeters += length
            }
        }
        guard !builtSegments.isEmpty, accumulatedMeters > 0 else { return nil }

        let declaredStepDistance = route.steps.reduce(0.0) {
            $0 + Double(max(0, $1.distanceMeters))
        }
        var cumulativeStepDistance = 0.0
        var mappedStepStarts: [Double] = []
        for step in route.steps {
            let fraction = declaredStepDistance > 0
                ? cumulativeStepDistance / declaredStepDistance
                : Double(mappedStepStarts.count) / Double(max(route.steps.count, 1))
            mappedStepStarts.append(accumulatedMeters * fraction)
            cumulativeStepDistance += Double(max(0, step.distanceMeters))
        }
        stepStartMeters = mappedStepStarts
        segments = builtSegments
        routeLengthMeters = accumulatedMeters
    }

    /**
     * Classifies a location as on-route, off-route, or too uncertain to use.
     * @param location The Core Location fix to match against route geometry.
     * @return A route assessment; stale or ambiguous fixes never advance progress.
     */
    mutating func update(location: CLLocation) -> RouteProgressAssessment {
        let age = abs(location.timestamp.timeIntervalSinceNow)
        let accuracy = location.horizontalAccuracy
        guard CLLocationCoordinate2DIsValid(location.coordinate),
              accuracy >= 0, accuracy <= 10, age <= 5 else { return .uncertain }

        let lowerBound = hasInitialMatch ? max(0, metersAlongRoute - max(5, accuracy)) : 0
        let elapsed = lastAcceptedTimestamp.map {
            max(0, location.timestamp.timeIntervalSince($0))
        } ?? 0
        let estimatedSpeed = location.speed >= 0 ? min(location.speed, 4) : 1.5
        let forwardWindow = min(75, max(30, estimatedSpeed * elapsed + accuracy * 2 + 8))
        let upperBound = hasInitialMatch
            ? min(routeLengthMeters, metersAlongRoute + forwardWindow)
            : routeLengthMeters
        let candidates = segments.compactMap { segment -> Candidate? in
            guard segment.endMeters >= lowerBound, segment.startMeters <= upperBound else { return nil }
            let candidate = project(location.coordinate, onto: segment)
            guard candidate.metersAlongRoute >= lowerBound,
                  candidate.metersAlongRoute <= upperBound else { return nil }
            return candidate
        }.sorted { $0.distanceFromRoute < $1.distanceFromRoute }

        let wholeRouteCandidates = segments.map { project(location.coordinate, onto: $0) }
            .sorted { $0.distanceFromRoute < $1.distanceFromRoute }
        guard let nearestAnywhere = wholeRouteCandidates.first else { return .uncertain }
        let corridor = max(15, accuracy * 2)

        guard let best = candidates.first, best.distanceFromRoute <= corridor else {
            if nearestAnywhere.distanceFromRoute <= corridor {
                return .uncertain
            }
            return .offRoute(distanceFromRoute: nearestAnywhere.distanceFromRoute,
                             horizontalAccuracy: accuracy)
        }
        if let alternate = wholeRouteCandidates.dropFirst().first,
           alternate.distanceFromRoute <= best.distanceFromRoute + 2.5,
           abs(alternate.metersAlongRoute - best.metersAlongRoute) > 15 {
            return .uncertain
        }

        metersAlongRoute = hasInitialMatch
            ? max(metersAlongRoute, best.metersAlongRoute)
            : best.metersAlongRoute
        hasInitialMatch = true
        lastAcceptedTimestamp = location.timestamp
        return .onRoute(RouteProgressReading(metersAlongRoute: metersAlongRoute,
                                             horizontalAccuracy: accuracy))
    }

    /**
     * Returns the approximate route distance at which a route step begins.
     * @param index The zero-based step index.
     * @return Distance in meters from route origin, or nil for an invalid index.
     */
    func startMeters(forStep index: Int) -> Double? {
        guard stepStartMeters.indices.contains(index) else { return nil }
        return stepStartMeters[index]
    }

    /**
     * Projects a location onto one route segment using a local meter-based plane.
     * @param coordinate The user's current coordinate.
     * @param segment The route segment considered by the ordered matcher.
     * @return Along-route progress and perpendicular distance in meters.
     */
    private func project(_ coordinate: CLLocationCoordinate2D, onto segment: Segment) -> Candidate {
        let latitudeRadians = coordinate.latitude * .pi / 180
        let metersPerLatitudeDegree = 111_132.92
        let metersPerLongitudeDegree = 111_412.84 * cos(latitudeRadians)
        let startX = (segment.start.longitude - coordinate.longitude) * metersPerLongitudeDegree
        let startY = (segment.start.latitude - coordinate.latitude) * metersPerLatitudeDegree
        let endX = (segment.end.longitude - coordinate.longitude) * metersPerLongitudeDegree
        let endY = (segment.end.latitude - coordinate.latitude) * metersPerLatitudeDegree
        let deltaX = endX - startX
        let deltaY = endY - startY
        let denominator = deltaX * deltaX + deltaY * deltaY
        let fraction = denominator > 0
            ? min(1, max(0, -(startX * deltaX + startY * deltaY) / denominator))
            : 0
        let projectedX = startX + fraction * deltaX
        let projectedY = startY + fraction * deltaY
        return Candidate(metersAlongRoute: segment.startMeters + fraction * segment.lengthMeters,
                         distanceFromRoute: hypot(projectedX, projectedY))
    }
}
