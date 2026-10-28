import SwiftUI

struct VibrationTestingView: View {
    let bluetooth: BluetoothService
    @State private var recipient = Recipient.left
    @State private var trialTask: Task<Void, Never>?
    @State private var trialRunID: UUID?
    @State private var trialSequence: [BluetoothService.Wrist] = []
    @State private var trialNumber = 0
    @State private var currentTrialWrist: BluetoothService.Wrist?
    @State private var trialStatus = "Ready to run 100 trials."

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
                    .disabled(trialTask != nil)
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

                if recipient == .both {
                    Section("Left / right motor check") {
                        Text(trialStatus)
                        if let currentTrialWrist, trialTask != nil {
                            Text("Trial \(trialNumber) of 100 · target: \(currentTrialWrist.rawValue)")
                                .font(.headline)
                        }
                        Text("Sends command 1 to 50 randomly ordered trials on each wristband, with 3–6 seconds between cues. Record which wrist you feel for each trial.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if trialTask == nil {
                            Button {
                                startLeftRightTrials()
                            } label: {
                                Label("Start 100-trial check", systemImage: "play.fill")
                            }
                            .disabled(!bluetooth.left.isReady || !bluetooth.right.isReady)
                        } else {
                            Button(role: .destructive) {
                                stopLeftRightTrials()
                            } label: {
                                Label("Stop trial run", systemImage: "stop.fill")
                            }
                        }
                        if !bluetooth.left.isReady || !bluetooth.right.isReady {
                            Text("Connect both wristbands to start this check.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                    if trialTask != nil {
                        stopLeftRightTrials()
                    } else {
                        bluetooth.stopAll()
                    }
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
        .onDisappear { stopLeftRightTrials() }
    }

    /**
     * Starts 100 command-1 trials with an equal, shuffled split between wristbands.
     */
    private func startLeftRightTrials() {
        guard trialTask == nil, bluetooth.left.isReady, bluetooth.right.isReady else { return }
        trialSequence = (Array(repeating: BluetoothService.Wrist.left, count: 50)
            + Array(repeating: BluetoothService.Wrist.right, count: 50)).shuffled()
        trialNumber = 0
        currentTrialWrist = nil
        trialStatus = "Running. Record the wrist that actually vibrates."
        let sequence = trialSequence
        let runID = UUID()
        trialRunID = runID
        trialTask = Task { @MainActor in
            for (index, wrist) in sequence.enumerated() {
                guard !Task.isCancelled else { break }
                guard bluetooth.left.isReady, bluetooth.right.isReady else {
                    trialStatus = "Stopped because a wristband disconnected."
                    break
                }
                trialNumber = index + 1
                currentTrialWrist = wrist
                bluetooth.send(1, to: wrist)
                if index < sequence.count - 1 {
                    do {
                        try await Task.sleep(for: .seconds(Int.random(in: 3...6)))
                    } catch {
                        break
                    }
                }
            }
            guard trialRunID == runID else { return }
            if !Task.isCancelled, trialNumber == sequence.count {
                trialStatus = "Complete: 50 left and 50 right commands sent."
            }
            currentTrialWrist = nil
            trialTask = nil
            trialRunID = nil
        }
    }

    /**
     * Stops the randomized motor check and sends stop commands to both wristbands.
     */
    private func stopLeftRightTrials() {
        guard let task = trialTask else { return }
        task.cancel()
        trialTask = nil
        trialRunID = nil
        currentTrialWrist = nil
        trialStatus = "Stopped after trial \(trialNumber) of 100."
        bluetooth.stopAll()
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
        .disabled(!recipientsReady || trialTask != nil)
        .accessibilityElement(children: .combine)
    }
}
