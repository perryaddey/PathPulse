import SwiftUI

struct VibrationTestingView: View {
    let bluetooth: BluetoothService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(bluetooth.status)
                } footer: {
                    Text("Tests play on PathPulse-Left only. Cues normally sent to both wrists play on this wristband during testing.")
                }

                Section("Directional cues") {
                    cueButton("Turn left", detail: "Two 400 ms pulses", icon: "arrow.turn.up.left", command: 1)
                    cueButton("Bear left / fork", detail: "One 400 ms pulse", icon: "arrow.up.left", command: 2)
                    cueButton("Continue straight", detail: "One 800 ms pulse", icon: "arrow.up", command: 3)
                    cueButton("Sharp left", detail: "Three 400 ms pulses", icon: "arrow.turn.down.left", command: 5)
                    cueButton("Turn around", detail: "Two 800 ms pulses · manual test only", icon: "arrow.uturn.backward", command: 6)
                }

                Section("Other cues") {
                    cueButton("Arrived", detail: "200 ms, 200 ms, then 800 ms", icon: "mappin.circle", command: 4)
                    cueButton("Guidance unavailable", detail: "800 ms, then two 200 ms pulses", icon: "location.slash", command: 7)
                    cueButton("Obstacle warning", detail: "Five 200 ms pulses", icon: "exclamationmark.triangle", command: 8)
                }

                Section {
                    if let message = bluetooth.commandStatus {
                        Text(message)
                    }
                    Text("An obstacle warning interrupts other patterns. While it plays, only Stop is accepted.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PathPulseBrand.background)
            .navigationTitle("Vibration tests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    bluetooth.send(0)
                } label: {
                    Label("Stop vibration", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!bluetooth.isReady)
                .padding()
                .background(PathPulseBrand.background)
            }
        }
        .tint(PathPulseBrand.accent)
    }

    /**
     * Builds a manual pattern test control for the connected left wristband.
     * @param title The cue's user-facing name.
     * @param detail Pulse timing and any test-only qualification.
     * @param icon The SF Symbol describing the cue.
     * @param command The binary firmware command from 1 through 8.
     * @return A labeled button disabled until the command service is ready.
     */
    private func cueButton(_ title: String, detail: String, icon: String, command: UInt8) -> some View {
        Button {
            bluetooth.send(command)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.fill")
            }
            .padding(.vertical, 4)
        }
        .disabled(!bluetooth.isReady)
        .accessibilityElement(children: .combine)
    }
}
