# Wristband firmware

PlatformIO project for an ESP32-C3-DevKitM-1, DRV2605L, and NFP-ELV959535 LRA.

Wiring: driver VIN to 3V3, GND to GND, SDA to GPIO 4, SCL to GPIO 5;
connect the motor to the driver's motor outputs.

## Build

Run commands from this directory:

```sh
pio run
```

The default `esp32-c3-devkitm-1` environment initializes and calibrates the driver
and services the pattern player. Calibration may briefly vibrate the motor.
BLE is not implemented yet; this environment does not accept serial pattern commands.

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
turn-around detection is implemented. BLE and app-driven wrist selection are not
implemented yet; serial testing plays the pattern on the connected board only.

Command `0` interrupts any pattern. Command `8` interrupts other patterns and
ignores further commands except stop until it finishes. Other new commands replace
the active pattern; no patterns are queued. A straight cue indicates route direction,
not that the path or crossing is clear.

See [the command protocol](../../../docs/haptic-command-protocol.md) for timings,
priority rules, and the distinction between serial ASCII digits and future BLE bytes.
All pulses use full configured amplitude with conservative motor voltage limits.

## Validation

Both build environments must compile. With hardware attached, check every pattern,
stop during a pulse, and obstacle interruption before changing the pulse table.
Generated `.pio/` build outputs and local `.vscode/` settings are ignored by Git.
