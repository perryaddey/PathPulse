# Wristband haptic command protocol

Agreed command mapping, September 30, 2026. Patterns are implemented in
`firmware/wristband/PathPulse/src/vibrations.cpp`; the BLE receiver is not implemented yet.

The iOS app selects the recipient wristband. Both wristbands use identical
firmware and the same command numbers; neither needs a left/right role in firmware.
For bilateral cues, the app sends a separate command to each wristband. These
writes do not guarantee precisely synchronized playback.

All pulses use full configured strength within the NFP-ELV959535 motor's voltage
rating. Use 200 ms pauses between pulses. Timings are initial proposals to validate
on mounted wristbands. Navigation is haptics-only; patterns must not rely on speech.

| Number | Meaning | Send to | Initial pattern |
|---|---|---|---|
| `0` | Stop immediately | Either or both | Cancel current vibration |
| `1` | Turn | Left or right | Two 400 ms pulses |
| `2` | Bear / slight turn / fork | Left or right | One 400 ms pulse |
| `3` | Continue straight | Both | One 800 ms pulse |
| `4` | Arrived | Both | 200 ms, 200 ms, then 800 ms |
| `5` | Sharp turn | Left or right | Three 400 ms pulses |
| `6` | Turn around | Both | Two 800 ms pulses |
| `7` | Guidance unavailable | Both | 800 ms, then two 200 ms pulses |
| `8` | Obstacle warning | Either or both, selected by obstacle logic | Five 200 ms pulses |

## Protocol rules

- Send one binary byte: command `1` is `0x01`, not ASCII `"1"` (`0x31`).
- Each command plays once and stops automatically.
- Command `0` stops any pattern.
- Command `8` interrupts navigation patterns.
- Reserve `9–255` for future commands; ignore unknown values.
- Keep command `6` reserved until reliable walking turn-around detection is implemented.
- A straight cue describes route direction, not whether the path or crossing is clear.

Examples: a left turn sends `0x01` only to the left wristband. Arrival sends
`0x04` separately to both wristbands.

## Playback policy

- No queue: a new non-obstacle command replaces the active non-obstacle pattern.
- Repeating a non-obstacle command restarts that pattern.
- An obstacle warning interrupts any non-obstacle pattern. While it plays, all
  commands except stop are ignored, including repeated obstacle commands.
- Interrupted patterns are not resumed. The app must send a fresh cue if needed.
- Driver temperature/current faults stop playback and require a board reset.
- Playback uses non-blocking timing; startup calibration is bounded but blocking.

## Bench testing before BLE

Build and upload the `vibration-test` PlatformIO environment, then open Serial
Monitor at 115200 baud and type one digit `0` through `8`. The interactive entry
point is `src/vibration_test.cpp`; the default firmware excludes it.
This serial-only adapter converts ASCII digits to binary command IDs; the future
BLE protocol still uses one binary byte. Newlines are ignored. No pattern plays
automatically after calibration. Command `6` is available for bench testing but
remains reserved for app use until walking turn-around detection is implemented.

Test `0` during a long pulse to stop it. Start `3` then send `8` to interrupt with
an obstacle warning. Commands `1–8` during that warning are ignored until it ends.
