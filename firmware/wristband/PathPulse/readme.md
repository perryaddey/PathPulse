# Wristband firmware

PlatformIO project for an ESP32-C3-DevKitM-1, DRV2605L, and NFP-ELV959535 LRA.

Wiring: driver VIN to 3V3, GND to GND, SDA to GPIO 4, SCL to GPIO 5;
connect the motor to the driver's motor outputs.

## Build

Run commands from this directory:

```sh
pio run
```

The default `esp32-c3-devkitm-1` environment configures fixed-frequency open-loop
LRA drive and services the pattern player. This avoids the calibration failure
seen with these motors and uses the same reduced drive that produced a confirmed
diagnostic pulse: approximately 169 Hz and a 0.64 V peak clamp.
It advertises as `PathPulse-Left` and accepts binary BLE commands. It does not
accept serial pattern commands. The `wristband-right` environment uses the same
firmware and protocol but advertises as `PathPulse-Right`.

Build and upload each board separately (select the appropriate USB port if both
boards are attached):

```sh
# Left wristband (also the default build)
pio run -e esp32-c3-devkitm-1 -t upload
# Right wristband
pio run -e wristband-right -t upload
```

In the app, open Bluetooth and scan. Connect each device in its Left or Right
section; either may connect first. Each section has independent test and stop
controls. The vibration testing suite offers Left, Right, and Both recipients.
Both requires two ready connections and sends separate writes, without precise
playback synchronization. Stop all remains available when only one band is ready.
Connections are manual; disconnected bands do not automatically reconnect or
replay commands. These controls do not yet drive navigation.

## Manual vibration test

```sh
pio run -e vibration-test -t upload
pio device monitor -b 115200
```

Send one digit `0–8` to test a pattern. Command `0` stops immediately. Newlines
are ignored. This is an interactive hardware test, not an automated `pio test` suite.
The test entry point lives in `src/vibration_test.cpp`; the default build excludes it.
The test build excludes `src/main.cpp`. Both use `src/vibrations.cpp`.

## Current motor patterns

### Isolated motor diagnostic

The `motor-diagnostic` environment is a separate serial-only open-loop test for
troubleshooting calibration failures. It excludes the normal pattern player and
BLE. Build/upload with `pio run -e motor-diagnostic -t upload`, then open Serial
Monitor at 115200 baud. It does not vibrate automatically.

Send `1` once for a 300 ms pulse at approximately 169.27 Hz, with a nominal
0.6366 V peak clamp (register 0x17 = 30). Send `0` to stop/disarm. One pulse is
allowed per board reset; additional commands cannot extend it. Configuration
readback and temperature/current checks must pass. A communication fault attempts
to stop output; if the stop write fails, disconnect USB power as the log requests.

These are configured values, not measured motor voltage. Feeling no vibration at
this reduced output does not alone establish that the motor is damaged. Upload
the appropriate normal wristband environment afterward to restore BLE.

Frequency and clamp settings follow the [TI DRV2605L datasheet](https://www.ti.com/lit/ds/symlink/drv2605l.pdf),
sections 8.5.4.2 and 8.6.26. Normal firmware now uses the verified open-loop
configuration instead of requiring closed-loop auto-calibration.

All pulses use full configured strength, with a 200 ms pause between pulses.
Each pattern plays once and stops automatically. The app selects which wristband
receives the command; both wristbands use the same pattern numbers.

| Command | Meaning | Wristband | Pulse durations |
|---|---|---|---|
| `0` | Stop immediately | Either or both | Cancel the active pattern |
| `1` | Turn left or right | Corresponding wrist | 400 ms, 400 ms |
| `2` | Bear / slight turn / fork | Corresponding wrist | 400 ms |
| `3` | Continue straight | Both | 800 ms |
| `4` | Arrived | Both | 200 ms, 200 ms, 800 ms |
| `5` | Sharp left or right turn | Corresponding wrist | 400 ms, 400 ms, 400 ms |
| `6` | Turn around | Both | 800 ms, 800 ms |
| `7` | Guidance unavailable | Both | 800 ms, 200 ms, 200 ms |
| `8` | Obstacle warning | Either or both, selected by obstacle logic | Five 200 ms pulses |

Command `6` is available for bench testing but reserved for app use until walking
turn-around detection is implemented. Serial testing plays the pattern on the
connected board only; BLE tests use the app's selected recipient.

Command `0` interrupts any pattern. Command `8` interrupts other patterns and
ignores further commands except stop until it finishes. Other new commands replace
the active pattern; no patterns are queued. A straight cue indicates route direction,
not that the path or crossing is clear.

See [the command protocol](../../../docs/haptic-command-protocol.md) for timings,
priority rules, and the distinction between serial ASCII digits and binary BLE bytes.
All pulses use full configured amplitude with conservative motor voltage limits.

## Validation

All three build environments must compile (`esp32-c3-devkitm-1`, `wristband-right`,
and `vibration-test`). With hardware attached, check every pattern,
stop during a pulse, and obstacle interruption before changing the pulse table.
Generated `.pio/` build outputs and local `.vscode/` settings are ignored by Git.

## Two-wristband integration checks

Physical checks are pending until both wristbands are available:

- Connect left first, then right; repeat with right first.
- Test each command on Left and Right separately, then on Both.
- Disconnect or power off either band and verify the other remains usable.
- Verify Both tests disable with a missing band, while Stop all still works.
- Turn iPhone Bluetooth off and verify both connections clear; reconnect manually
  and verify no previous command plays again.
- Check a connection/service timeout affects only its wrist.
