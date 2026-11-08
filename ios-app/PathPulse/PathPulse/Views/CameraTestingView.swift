import SwiftUI

struct CameraTestingView: View {
    let glasses: GlassesCameraService
    @Environment(\.scenePhase) private var scenePhase

    private var isLive: Bool {
        glasses.running && glasses.preview != nil
            && (glasses.frameAge ?? .infinity) <= GlassesCameraService.staleFrameInterval
    }

    private var feedLabel: String {
        if isLive { return "Live" }
        if glasses.running { return "Waiting for frames" }
        if glasses.busy { return "Connecting" }
        return "Preview off"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "eyeglasses")
                        .font(.title2)
                        .foregroundStyle(PathPulseBrand.accent)
                        .frame(width: 48, height: 48)
                        .background(PathPulseBrand.card, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Glasses camera").font(.title3.weight(.semibold))
                        Text(glasses.deviceReady ? glasses.selectedDeviceName : "Waiting for your glasses")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                previewCard

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 12)], spacing: 12) {
                    metric("Frame rate", value: String(format: "%.1f fps", glasses.fps), icon: "speedometer")
                    metric("Resolution", value: glasses.dimensions, icon: "viewfinder")
                }

                if let error = glasses.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                } else if glasses.registered && !glasses.deviceReady && !glasses.running {
                    Label("Put on your glasses and check their connection in Meta AI. Start Feed will be available when they’re ready.",
                          systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup {
                    VStack(spacing: 14) {
                        LabeledContent("Registration", value: glasses.registrationStatus)
                        LabeledContent("Discovered glasses", value: "\(glasses.deviceCount)")
                        LabeledContent("Device readiness", value: glasses.deviceReady ? "Ready" : "Waiting")
                        LabeledContent("Requested", value: "High · \(GlassesCameraService.requestedFrameRate) fps")
                        LabeledContent("Received frames", value: "\(glasses.frameCount)")
                        LabeledContent("Last frame", value: glasses.frameAge.map {
                            String(format: "%.1f seconds ago", $0)
                        } ?? "—")
                    }
                    .font(.subheadline)
                    .monospacedDigit()
                    .padding(.top, 16)
                } label: {
                    Label("Stream details", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(16)
                .background(PathPulseBrand.card, in: RoundedRectangle(cornerRadius: 16))

                Label("Preview only · Nothing is recorded", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 560)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(PathPulseBrand.background)
        .safeAreaInset(edge: .bottom) { controls }
        .tint(PathPulseBrand.accent)
        .navigationTitle("Camera Test")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { glasses.foreground = scenePhase == .active }
        .onDisappear { glasses.stop() }
        .onChange(of: scenePhase) { _, phase in
            glasses.foreground = phase == .active
            // Permission redirects happen before a session exists; let those finish.
            if phase == .background, glasses.running { glasses.stop() }
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color.black
                if let image = glasses.preview {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Live glasses camera preview")
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "video")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(PathPulseBrand.accent)
                        Text(glasses.running ? "Waiting for your feed" : "Your view starts here")
                            .font(.headline)
                        Text(glasses.running ? "Keep your glasses connected." : "Connect your glasses, then start the preview.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                }
            }
            .frame(height: 340)
            .overlay(alignment: .topLeading) {
                Label(feedLabel, systemImage: isLive ? "dot.radiowaves.left.and.right" : "video.slash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isLive ? Color.green : Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.75), in: Capsule())
                    .padding(14)
            }

            Text(glasses.status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let age = glasses.frameAge, age > GlassesCameraService.staleFrameInterval {
                Label("Feed stalled. Stop and retry if frames do not resume.", systemImage: "wifi.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding([.horizontal, .bottom], 16)
            }
        }
        .background(PathPulseBrand.card)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(PathPulseBrand.accent.opacity(0.18), lineWidth: 1)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if glasses.running || glasses.busy {
                Button { glasses.stop() } label: {
                    Label(glasses.running ? "Stop Feed" : "Cancel", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else if !glasses.registered {
                Button { glasses.connect() } label: {
                    Label("Connect Glasses", systemImage: "eyeglasses")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!glasses.configured)
            } else {
                Button { glasses.start() } label: {
                    Label("Start Feed", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!glasses.deviceReady)
            }
            Text("Streaming stops when you leave this screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    /**
     * Displays a prominent stream measurement in a branded card.
     * @param title The measurement label.
     * @param value The formatted measurement, including its units.
     * @param icon The SF Symbol representing the measurement.
     * @return An accessible card that groups the label and value.
     */
    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(PathPulseBrand.card, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
