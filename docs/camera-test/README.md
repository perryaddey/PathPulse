# Glasses camera test

PathPulse's Camera Test screen previews the Ray-Ban Meta Gen 2 camera on an iPhone. It requests high resolution at 30 fps and reports delivered frame count, receipt fps, frame dimensions, and time since the last frame. These are receipt measurements, not capture-to-display latency guarantees.

## Setup

1. Open `ios-app/PathPulse/PathPulse.xcodeproj` in Xcode. Resolve package dependencies. Meta's `MWDATCore` and `MWDATCamera` products are pinned to **1.0.1**.
2. Select your paid Apple development team under Signing & Capabilities. Confirm automatic signing provisions **Hotspot Configuration** and **Access Wi-Fi Information**. The bundle identifier remains `com.perryaddey.PathPulse`.
3. Pair the glasses with Meta AI on the test iPhone, update their firmware, and enable glasses Developer Mode in Meta AI. In Meta AI, open **Settings → App Info**, tap **App version** five times, then enable **Developer Mode** and confirm.
4. Build and run on the physical iPhone. Simulator build success cannot validate glasses streaming.
5. Open **Camera Test → Connect**. Complete registration in Meta AI and return to PathPulse. Developer Mode does not require a Meta application ID or client token. The `pathpulse://` callback is registered in Info.plist; production distribution would require a separate production registration configuration.
6. Wait for **Device readiness: Ready**, then tap **Start Feed**. Grant camera access through Meta AI, allow Local Network access, and accept the glasses' Wi-Fi connection when prompted. If permission completes while PathPulse is inactive, return and tap Start Feed again.
7. Confirm the preview changes as you move the glasses, frame count increases, and received fps/dimensions are shown. Tap **Stop Feed** to end the session.

No microphone, recording, photo saving, Vision, depth integration, or obstacle haptics are enabled. Navigation and wristband BLE remain separate. The camera stops when the test screen is dismissed or the app backgrounds; restart explicitly. Device/stream pause ends this test session rather than automatically resuming it. A two-second frame gap clears the preview and displays a stalled-feed message. Start creates a fresh session and resets diagnostics.

## Troubleshooting

- **Registration fails:** confirm Developer Mode, pairing, and firmware in Meta AI. Inspect the displayed SDK error.
- **No eligible device / readiness stays Waiting:** registration and permissions do not guarantee a selected device. Put on the powered-on glasses, confirm their connection in Meta AI, and return to PathPulse. The app retains the SDK selector and waits for an active device before enabling Start Feed. Report the Discovered glasses count and Selected glasses label if it stays Waiting.
- **No frames:** check iOS Settings → PathPulse → Local Network, accept the glasses' Wi-Fi join prompt, and verify signed entitlements. Registration over Bluetooth alone does not prove camera streaming works.
- **Camera denied:** tap Start Feed again and grant camera permission in Meta AI.
- **Disconnected/paused:** restore glasses availability and tap Start Feed. Stop Feed remains available during startup.
- **No image but frame count increases:** report the dimensions and SDK version; raw-frame conversion needs investigation on the device.

## Development verification

- Complete app Swift type-check passed against the cached Google SDKs and Meta 1.0.1 for arm64 iOS, using the project's Swift 5 language mode and MainActor default isolation.
- Project, Info.plist, and entitlements plist validation passed; `git diff --check` passed.
- Physical-device registration, camera permission, and live preview were confirmed by the developer on November 8, 2026, after retaining and observing the SDK device selector.
- Command-line Xcode build verification was unavailable in the agent environment (`xcodebuild` aborted before compilation). The cleanup changes have been type-checked; repeat the on-device smoke test after rebuilding.

## Hardware acceptance checklist

Only the checks explicitly confirmed on hardware are marked passed. Performance and recovery checks remain pending.

| Check | Result / observations |
| --- | --- |
| Registration and permission grant | Passed — developer confirmed, November 8, 2026 |
| Live glasses camera preview | Passed — developer confirmed, November 8, 2026 |
| Correct orientation in portrait and landscape | Pending |
| Five-minute continuous preview; actual fps, dimensions, visible lag, interruptions | Pending |
| Five start/stop cycles; no duplicate frames/listeners or frozen UI | Pending |
| Leave/reopen screen; no live feed until Start Feed | Pending |
| Background/foreground; no automatic restart | Pending |
| Camera permission denial and retry | Pending |
| Local Network denial / Wi-Fi join rejection and recovery | Pending |
| Glasses pause/disconnect/reconnect; stale preview cleared | Pending |
| Stream with both wristbands connected | Pending |
| Outdoor stream without a nearby Wi-Fi router | Pending |
| Existing navigation and wristband controls | Pending |

Record iPhone/iOS version, glasses firmware, SDK version, and test duration with results. The five-minute test should remain responsive without an ever-growing frame backlog. Falling below requested 30 fps is a measurement to investigate, not evidence that 30 fps was delivered.

## References

- [Meta iOS integration](https://wearables.developer.meta.com/docs/develop/dat/build-integration-ios/)
- [Camera streaming](https://wearables.developer.meta.com/docs/develop/dat/streaming/)
- [Official CameraAccess sample](https://github.com/meta/meta-wearables-dat-ios/tree/main/samples/CameraAccess)
