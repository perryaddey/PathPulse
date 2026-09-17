import SwiftUI

struct RouteDirectionsView: View {
    let route: WalkingRoute
    let onEnd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(route.destination.name)
                    .font(.headline)
                Text("Walking route · \(RouteFormatting.distance(route.distanceMeters)), \(RouteFormatting.duration(route.durationSeconds))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(route.steps) { step in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: stepIcon(for: step.maneuver.direction))
                                .frame(width: 24)
                                .foregroundStyle(.tint)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.instruction)
                                    .font(.body)
                                Text(RouteFormatting.distance(step.distanceMeters))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 10)

                        if step.id != route.steps.last?.id {
                            Divider()
                        }
                    }

                    Label("Arrive at \(route.destination.name)", systemImage: "mappin.and.ellipse")
                        .font(.body)
                        .padding(.vertical, 10)
                }
                .padding(.horizontal)
            }

            Button(action: onEnd) {
                Text("End navigation")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial)
        .accessibilityElement(children: .contain)
    }

    /**
     * Selects a directional icon for a route maneuver.
     *
     * @param direction The normalized maneuver direction from the route response.
     * @return The SF Symbol name used for the direction row.
     */
    private func stepIcon(for direction: RouteManeuver.Direction) -> String {
        switch direction {
        case .left: "arrow.turn.up.left"
        case .right: "arrow.turn.up.right"
        case .straight: "arrow.up"
        case .other: "arrow.up.right"
        }
    }
}
