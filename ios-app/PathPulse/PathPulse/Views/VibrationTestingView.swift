import SwiftUI

struct VibrationTestingView: View {
    let bluetooth: BluetoothService
    @State private var recipient = Recipient.left

    private enum Recipient: String, CaseIterable, Identifiable {
        case left = "Left", right = "Right", both = "Both"
        var id: String { rawValue }
        var wrists: [BluetoothService.Wrist] {
            switch self {
            case .left: [.left]
            case .right: [.right]
            case .both: [.left, .right]
            }
        }
    }

    private var recipientsReady: Bool {
        recipient.wrists.allSatisfy { bluetooth.connection(for: $0).isReady }
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Recipient", selection: $recipient) {
                        ForEach(Recipient.allCases) { recipient in
                            Text(recipient.rawValue).tag(recipient)
                        }
                    }
                    .pickerStyle(.segmented)
                    ForEach(recipient.wrists) { wrist in
                        Text("\(wrist.rawValue): \(bluetooth.connection(for: wrist).status)")
                    }
                } footer: {
                    Text("Manual tests play on the selected wrist or wrists. Both requires two ready connections; playback is not precisely synchronized.")
                }

                Section("Directional cues") {
                    cueButton("Turn", detail: "Two 400 ms pulses", icon: "arrow.turn.up.left", command: 1)
                    cueButton("Bear / fork", detail: "One 400 ms pulse", icon: "arrow.up.left", command: 2)
                    cueButton("Continue straight", detail: "One 800 ms pulse", icon: "arrow.up", command: 3)
                    cueButton("Sharp turn", detail: "Three 400 ms pulses", icon: "arrow.turn.down.left", command: 5)
                    cueButton("Turn around", detail: "Two 800 ms pulses · manual test only", icon: "arrow.uturn.backward", command: 6)
                }

                Section("Other cues") {
                    cueButton("Arrived", detail: "200 ms, 200 ms, then 800 ms", icon: "mappin.circle", command: 4)
                    cueButton("Guidance unavailable", detail: "800 ms, then two 200 ms pulses", icon: "location.slash", command: 7)
                    cueButton("Obstacle warning", detail: "Five 200 ms pulses", icon: "exclamationmark.triangle", command: 8)
                }

                Section {
                    ForEach(recipient.wrists) { wrist in
                        if let message = bluetooth.connection(for: wrist).commandStatus {
                            Text("\(wrist.rawValue): \(message)")
                        }
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
                    bluetooth.stopAll()
                } label: {
                    Label("Stop all connected wristbands", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!bluetooth.left.isReady && !bluetooth.right.isReady)
                .padding()
                .background(PathPulseBrand.background)
            }
        }
        .tint(PathPulseBrand.accent)
    }

    /**
     * Builds a manual pattern test for the selected wrist or wrists.
     * @param title The cue's user-facing name.
     * @param detail Pulse timing and any test-only qualification.
     * @param icon The SF Symbol describing the cue.
     * @param command The binary firmware command from 1 through 8.
     * @return A labeled button disabled until all selected command services are ready.
     */
    private func cueButton(_ title: String, detail: String, icon: String, command: UInt8) -> some View {
        Button {
            guard recipientsReady else { return }
            for wrist in recipient.wrists { bluetooth.send(command, to: wrist) }
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
        .disabled(!recipientsReady)
        .accessibilityElement(children: .combine)
    }
}
