import SwiftUI

struct HomeView: View {
    let mapsConfigured: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                PathPulseBrand.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        VStack(spacing: 14) {
                            Image("PathPulseLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 150, height: 150)
                                .accessibilityLabel("PathPulse logo")

                            HStack(spacing: 0) {
                                Text("Path")
                                    .foregroundStyle(.white)
                                Text("Pulse")
                                    .foregroundStyle(PathPulseBrand.accent)
                            }
                            .font(.system(size: 44, weight: .medium, design: .rounded))

                            Text("FIND YOUR NEXT STEP")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .tracking(4)
                                .foregroundStyle(PathPulseBrand.secondaryText)
                        }
                        .padding(.top, 28)

                        VStack(spacing: 14) {
                            menuLink(
                                title: "Navigation",
                                subtitle: "Plan a route and follow each step",
                                systemImage: "arrow.triangle.turn.up.right.diamond"
                            ) {
                                ContentView(mapsConfigured: mapsConfigured)
                            }

                            menuLink(
                                title: "Bluetooth",
                                subtitle: "Connect your PathPulse wristbands",
                                systemImage: "dot.radiowaves.left.and.right"
                            ) {
                                PlaceholderView(
                                    title: "Bluetooth",
                                    message: "Wristband connection setup is coming next."
                                )
                            }

                            menuLink(
                                title: "Settings",
                                subtitle: "Manage app preferences",
                                systemImage: "gearshape"
                            ) {
                                PlaceholderView(
                                    title: "Settings",
                                    message: "PathPulse settings will be available here."
                                )
                            }
                        }
                        .padding(.horizontal, 22)
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /**
     * Builds a branded navigation card for a home menu destination.
     *
     * @param title The primary label shown on the card.
     * @param subtitle The supporting description shown below the label.
     * @param systemImage The SF Symbol displayed beside the card text.
     * @param destination The screen opened when the card is selected.
     * @return A styled navigation link card.
     */
    @ViewBuilder
    private func menuLink<Destination: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundStyle(PathPulseBrand.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(PathPulseBrand.secondaryText)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .foregroundStyle(PathPulseBrand.secondaryText)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PathPulseBrand.card)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(PathPulseBrand.accent.opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

private struct PlaceholderView: View {
    let title: String
    let message: String

    var body: some View {
        ZStack {
            PathPulseBrand.background
                .ignoresSafeArea()
            ContentUnavailableView(title, systemImage: "ellipsis.circle", description: Text(message))
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum PathPulseBrand {
    static let background = Color(red: 0.055, green: 0.06, blue: 0.075)
    static let card = Color(red: 0.09, green: 0.09, blue: 0.13)
    static let accent = Color(red: 0.64, green: 0.39, blue: 1.0)
    static let secondaryText = Color(red: 0.62, green: 0.62, blue: 0.7)
}
