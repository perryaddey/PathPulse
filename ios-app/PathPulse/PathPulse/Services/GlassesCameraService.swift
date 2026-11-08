import Foundation
import MWDATCamera
import MWDATCore
import Observation
import UIKit

/**
 * Shares one pending preview between SDK callbacks and the main actor.
 * The lock protects every mutable field, providing the unchecked Sendable guarantee.
 */
private nonisolated final class CameraFrameMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var image: UIImage?
    private var count = 0
    private var receivedAt: TimeInterval?

    /**
     * Converts a frame on the callback thread and replaces the pending image.
     * Counts every callback, including frames whose image conversion fails; no frame queue is retained.
     * @param frame The SDK frame received from the glasses.
     */
    func receive(_ frame: VideoFrame) {
        let preview = frame.makeUIImage()
        lock.lock()
        defer { lock.unlock() }
        count += 1
        receivedAt = ProcessInfo.processInfo.systemUptime
        image = preview
    }

    /**
     * Takes and clears the pending image while retaining cumulative diagnostics.
     * @return Image, total received frames, and last receipt time in uptime seconds.
     */
    func take() -> (image: UIImage?, count: Int, receivedAt: TimeInterval?) {
        lock.lock()
        defer { lock.unlock() }
        let result = (image, count, receivedAt)
        image = nil
        return result
    }
}

/** Owns Meta registration, device selection, and the foreground camera test session. */
@Observable
@MainActor
final class GlassesCameraService {
    static let requestedFrameRate: UInt = 30
    static let staleFrameInterval: TimeInterval = 2
    private static let previewPollInterval: Duration = .milliseconds(33)
    private static let frameRateSampleInterval: TimeInterval = 1

    private(set) var configured = false
    private(set) var registered = false
    private(set) var registrationStatus = "Not connected"
    private(set) var deviceCount = 0
    private(set) var deviceReady = false
    private(set) var selectedDeviceName = "Waiting for glasses"
    private(set) var status = "Connect your glasses to begin."
    private(set) var errorMessage: String?
    private(set) var busy = false
    private(set) var running = false
    private(set) var preview: UIImage?
    private(set) var frameCount = 0
    private(set) var fps = 0.0
    private(set) var dimensions = "—"
    private(set) var frameAge: TimeInterval?
    var foreground = true

    @ObservationIgnored private var deviceSelector: AutoDeviceSelector?
    @ObservationIgnored private var selectionTask: Task<Void, Never>?
    @ObservationIgnored private var session: DeviceSession?
    @ObservationIgnored private var camera: Camera?
    @ObservationIgnored private var tokens: [AnyListenerToken] = []
    @ObservationIgnored private var registrationToken: AnyListenerToken?
    @ObservationIgnored private var devicesTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    // Invalidated on stop so callbacks from an older session cannot update a new one.
    @ObservationIgnored private var generation = UUID()

    /** Configures Meta once for this app-owned service and observes registration and availability. */
    init() {
        do {
            try Wearables.configure()
            configured = true
            // Selection is asynchronous: retain and observe it before creating a session.
            let selector = AutoDeviceSelector(wearables: Wearables.shared)
            deviceSelector = selector
            selectionTask = Task { [weak self] in
                for await deviceID in selector.activeDeviceStream() {
                    guard !Task.isCancelled else { return }
                    self?.deviceReady = deviceID != nil
                    self?.selectedDeviceName = deviceID.flatMap {
                        Wearables.shared.deviceForIdentifier($0)?.nameOrId()
                    } ?? "Waiting for glasses"
                }
            }
            registrationToken = Wearables.shared.addRegistrationStateListener { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    registered = state == .registered
                    registrationStatus = String(describing: state)
                    if !registered, running { stop() }
                }
            }
            devicesTask = Task { [weak self] in
                for await devices in Wearables.shared.devicesStream() {
                    guard !Task.isCancelled else { return }
                    self?.deviceCount = devices.count
                }
            }
        } catch {
            errorMessage = "Meta SDK setup failed: \(error.localizedDescription)"
        }
    }

    /** Opens Meta AI to register PathPulse in Developer Mode; completion arrives through handleURL. */
    func connect() {
        guard configured, !busy, !running else { return }
        busy = true
        errorMessage = nil
        let id = generation
        operationTask = Task { [weak self] in
            do {
                try await Wearables.shared.startRegistration()
            } catch {
                guard self?.generation == id else { return }
                self?.errorMessage = "Connection failed: \(error.localizedDescription). Check Developer Mode in Meta AI."
            }
            guard self?.generation == id else { return }
            self?.busy = false
        }
    }

    /**
     * Completes registration and permission callbacks delivered by Meta AI.
     * @param url The unchanged callback URL supplied by iOS.
     */
    func handleURL(_ url: URL) async {
        guard configured else { return }
        do {
            _ = try await Wearables.shared.handleUrl(url)
        } catch {
            errorMessage = "Meta callback failed: \(error.localizedDescription)"
        }
    }

    /**
     * Requests camera permission through Meta AI and starts a session when a device is selected.
     * Returning while inactive requires another explicit start; denied access is shown in the UI.
     */
    func start() {
        guard configured, registered, !busy, !running, foreground else { return }
        guard deviceSelector?.activeDevice != nil else {
            status = "Waiting for eligible glasses. Put them on, confirm they are connected in Meta AI, then return here."
            return
        }
        errorMessage = nil
        busy = true
        generation = UUID()
        let id = generation
        status = "Checking camera permission…"
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                var permission = try await Wearables.shared.checkPermissionStatus(.camera)
                if permission != .granted {
                    status = "Allow camera access in Meta AI, then return here."
                    permission = try await Wearables.shared.requestPermission(.camera)
                }
                guard generation == id, !Task.isCancelled else { return }
                busy = false
                guard permission == .granted else {
                    errorMessage = "Camera access was denied. Tap Start Feed to request it again in Meta AI."
                    status = "Camera permission required"
                    return
                }
                guard foreground else {
                    status = "Permission granted. Tap Start Feed when you return."
                    return
                }
                try beginSession(id: id)
            } catch {
                guard generation == id else { return }
                if let sessionError = error as? DeviceSessionError, sessionError == .noEligibleDevice {
                    fail("Glasses are no longer ready. Put them on, confirm the connection in Meta AI, then wait for Device readiness before retrying.")
                } else {
                    fail("Could not start camera: \(error.localizedDescription)")
                }
            }
        }
    }

    /**
     * Reuses the observed selector and registers lifecycle listeners before session start.
     * @param id Generation identifier used to discard callbacks from previous sessions.
     * @throws SDK session creation or startup errors.
     */
    private func beginSession(id: UUID) throws {
        guard let deviceSelector, deviceSelector.activeDevice != nil else {
            throw DeviceSessionError.noEligibleDevice
        }
        let newSession = try Wearables.shared.createSession(deviceSelector: deviceSelector)
        session = newSession
        running = true
        frameCount = 0
        fps = 0
        dimensions = "—"
        frameAge = nil
        status = "Connecting to glasses…"
        tokens.append(newSession.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, generation == id else { return }
                switch state {
                case .started:
                    if camera == nil { beginCamera(id: id) }
                case .paused:
                    stop()
                    status = "Glasses paused. Tap Start Feed to restart."
                case .stopped:
                    stop()
                    status = "Glasses disconnected or session ended. Tap Start Feed to reconnect."
                default: break
                }
            }
        })
        tokens.append(newSession.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, generation == id else { return }
                fail("Glasses session failed: \(error). Check the connection and firmware in Meta AI, then retry.")
            }
        })
        try newSession.start()
    }

    /**
     * Attaches a video-only stream after the device reports it has started.
     * @param id The active session generation.
     */
    private func beginCamera(id: UUID) {
        guard let session else { return }
        do {
            guard let newCamera = try session.addCamera(config: StreamConfiguration(
                videoCodec: .raw, resolution: .high, frameRate: Self.requestedFrameRate)) else {
                fail("Camera is unavailable. Stop and retry after checking the glasses in Meta AI.")
                return
            }
            camera = newCamera
            let stream = newCamera.stream
            let mailbox = CameraFrameMailbox()
            tokens.append(stream.videoFramePublisher.listen { frame in mailbox.receive(frame) })
            tokens.append(stream.statePublisher.listen { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self, generation == id else { return }
                    status = "Camera: \(state)"
                    if state == .paused || state == .stopped {
                        stop()
                        status = "Camera \(state). Tap Start Feed to restart."
                    } else if state != .streaming {
                        preview = nil
                    }
                }
            })
            tokens.append(stream.errorPublisher.listen { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self, generation == id else { return }
                    fail("Camera failed: \(error). Check Local Network permission and accept the glasses’ Wi-Fi connection, then retry.")
                }
            })
            startPreviewPolling(mailbox: mailbox, id: id)
            stream.start()
        } catch {
            fail("Could not attach camera: \(error.localizedDescription)")
        }
    }

    /**
     * Polls one bounded mailbox and calculates receipt rate using monotonic time.
     * @param mailbox The latest-frame buffer for this stream.
     * @param id The active session generation.
     */
    private func startPreviewPolling(mailbox: CameraFrameMailbox, id: UUID) {
        previewTask = Task { [weak self] in
            var previousTime = ProcessInfo.processInfo.systemUptime
            var previousCount = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: Self.previewPollInterval) } catch { return }
                guard let self, generation == id else { return }
                let (image, count, lastTime) = mailbox.take()
                let now = ProcessInfo.processInfo.systemUptime
                if count != frameCount {
                    // A failed conversion must not leave an old image looking live.
                    preview = image
                    if let cg = image?.cgImage { dimensions = "\(cg.width) × \(cg.height)" }
                }
                frameCount = count
                frameAge = lastTime.map { now - $0 }
                if let age = frameAge, age > Self.staleFrameInterval { preview = nil }
                let elapsed = now - previousTime
                if elapsed >= Self.frameRateSampleInterval {
                    fps = Double(count - previousCount) / elapsed
                    previousTime = now
                    previousCount = count
                }
            }
        }
    }

    /**
     * Cancels pending startup and preview work, releases session listeners, and clears the image.
     * Keeps registration and device discovery active so the user can start another session.
     * Retains the last frame count, dimensions, and error for inspection.
     */
    func stop() {
        generation = UUID()
        operationTask?.cancel()
        operationTask = nil
        previewTask?.cancel()
        previewTask = nil
        tokens.removeAll()
        camera?.stop()
        camera = nil
        session?.stop()
        session = nil
        running = false
        busy = false
        preview = nil
        frameAge = nil
        fps = 0
        status = "Stopped. Tap Start Feed to begin."
    }

    /**
     * Ends the current session while preserving an actionable failure message.
     * @param message The error and suggested recovery action.
     */
    private func fail(_ message: String) {
        stop()
        errorMessage = message
        status = "Camera unavailable"
    }
}
