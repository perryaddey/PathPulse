# Wristband firmware

PlatformIO firmware for the PathPulse wristband PCB:

- Seeed Studio XIAO ESP32-C3 (`seeed_xiao_esp32c3`)
- DRV2605L haptic driver at I2C address `0x5A`
- Precision Microdrives C10-100(R7), 10 mm linear resonant actuator, 4 mm type

Wiring: driver VIN to 3V3, GND to GND, SDA to D5/GPIO7, SCL to D4/GPIO6;
connect the motor to the driver's motor outputs.
All entry points use the explicit PCB pin mapping in `include/wristband_hardware.h`.

## Build

Run commands from this directory:

```sh
pio run
```

The default `wristband-left` environment configures fixed-frequency open-loop
LRA drive and services the pattern player.
It advertises as `PathPulse-Left` and accepts binary BLE commands. It does not
accept serial pattern commands. The `wristband-right` environment uses the same
firmware and protocol but advertises as `PathPulse-Right`.

Build and upload each board separately (select the appropriate USB port if both
boards are attached):

```sh
# Left wristband (also the default build)
pio run -e wristband-left -t upload
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

## Motor drive configuration

The pattern player and `motor-diagnostic` use open-loop LRA drive without auto-calibration. Both use the same stronger motor settings:

| Environments | Period register `0x20` | Frequency | Clamp register `0x17` | Nominal peak clamp |
|---|---|---|---|---|
| `motor-diagnostic` | `58` | 175.11 Hz | `94` | 1.99468 V |
| `wristband-left`, `wristband-right`, `vibration-test` | `58` | 175.11 Hz | `94` | 1.99468 V |

The diagnostic settings are in `src/motor_diagnostic.cpp`; the pattern player
settings are in `src/vibrations.cpp`. Both open-loop implementations use signed RTP amplitude `0x7F` during
pulses. Full configured amplitude refers to the selected clamp, not the motor's
maximum rated output. These are configured values, not measured motor voltage;
peak clamp voltage is not RMS voltage.

Frequency and clamp settings follow the [TI DRV2605L datasheet](https://www.ti.com/lit/ds/symlink/drv2605l.pdf),
sections 8.5.2.2, 8.5.4.2, and 8.6.26.

## Manual vibration test

```sh
pio run -e vibration-test -t upload
pio device monitor -b 115200
```

Send one digit `0–8` to test a pattern. Command `0` stops immediately. Newlines
are ignored. This is an interactive hardware test, not an automated `pio test` suite.
The test entry point lives in `src/vibration_test.cpp`; the default build excludes it.
The test build excludes `src/main.cpp`. Both use `src/vibrations.cpp`.

## Isolated motor diagnostic

The `motor-diagnostic` environment is a serial-only open-loop test of the PCB
and C10-100 motor. It excludes the normal pattern player and
BLE. Build/upload with `pio run -e motor-diagnostic -t upload`, then open Serial
Monitor at 115200 baud. It does not vibrate automatically.

Send `1` once for a 300 ms pulse at approximately 175.11 Hz, with a nominal
1.99468 V peak clamp (register 0x17 = 94). Send `0` to stop/disarm. One pulse is
allowed per board reset; additional commands cannot extend it. Configuration
readback and temperature/current checks must pass. A communication fault attempts
to stop output; if the stop write fails, disconnect USB power as the log requests.

Open Serial Monitor, press the XIAO reset button, wait for successful configuration
checks and `READY`, then send `1`. Reset and wait for `READY` before repeating.
Close Serial Monitor before uploading firmware so the serial port is available.
Upload the appropriate wristband environment to use BLE.

A perceptible pulse at these diagnostic settings has been confirmed on the PCB.
Motor voltage and maximum output have not been measured or validated.

## Isolated closed-loop calibration test

`motor-closed-loop` builds only `src/motor_closed_loop.cpp`, with no BLE.
It uses the same PCB pins and requires manual calibration before playback.

```sh
pio run -e motor-closed-loop
pio run -e motor-closed-loop -t upload
pio device monitor -b 115200
```

Close Serial Monitor before uploading. After opening it, reset the XIAO:

1. Wait for configuration checks and `READY FOR CALIBRATION`.
2. Send `c`. **Calibration vibrates the motor**, normally for 1000–1200 ms,
   with a 1500 ms timeout. Capture the `CAL RESULT` register values.
3. Only after `CAL PASSED`, send `1` for one 300 ms pulse. Reported resonance
   is sampled during playback; readings alone do not prove resonance lock.
4. Output returns to zero for 100 ms of automatic braking, then standby.
   Send `0` at any stage to stop/disarm. Reset before another calibration/pulse.

The initial rated-voltage register is `58` (approximately 1.39 V RMS target at
175 Hz with 300 us sampling), and peak clamp is `94` (nominal 1.99468 V).
The RMS target follows the motor manufacturer's typical 30% auto-resonance
voltage reduction. Drive time starts at 2.8 ms, then the driver tracks resonance.
RTP uses unsigned unidirectional input: `255` for full configured output, `0` for
braking. Calibration results remain volatile; OTP programming is never enabled.
I2C errors, calibration failure/timeouts, and temperature/current faults disable
playback until reset. These settings require hardware validation and are not
measured output values. See [calibration notes](../../../notes/motor-closed-loop-calibration.md).

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
turn-around detection is implemented. Serial testing plays the pattern on the
connected board only; BLE tests use the app's selected recipient.

Command `0` interrupts any pattern. Command `8` interrupts other patterns and
ignores further commands except stop until it finishes. Other new commands replace
the active pattern; no patterns are queued. A straight cue indicates route direction,
not that the path or crossing is clear.

See [the command protocol](../../../docs/haptic-command-protocol.md) for timings,
priority rules, and the distinction between serial ASCII digits and binary BLE bytes.

## Validation

All five build environments must compile (`wristband-left`, `wristband-right`,
`vibration-test`, `motor-diagnostic`, and `motor-closed-loop`). With hardware attached, check every pattern,
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
