# C10-100 closed-loop calibration log

## Configuration — 2026-11-11

Hardware: XIAO ESP32-C3, SDA D5/GPIO7, SCL D4/GPIO6, DRV2605L at 0x5A,
C10-100(R7) LRA. Environment: `motor-closed-loop`.

| Register | Value | Purpose |
|---|---|---|
| 0x16 | 58 / 0x3A | Approximately 1.39 V RMS rated-drive target |
| 0x17 | 94 / 0x5E | 1.99468 V nominal peak clamp |
| 0x1A | 0xAA initially | LRA, brake factor 2, loop gain 2; calibration updates BEMF gain |
| 0x1B | 0x97 | Startup boost, 2.8 ms initial drive time |
| 0x1C | 0x75 | Unidirectional; brake stabilization; 300 us sample; 25 us blanking/dissipation |
| 0x1D | 0x88 | Unsigned RTP, closed-loop LRA, supply compensation |
| 0x1E | 0x30 | 1000–1200 ms calibration, OTP programming disabled |
| 0x1F | 0x80 | Auto-open-loop option disabled; upper timing bits zero |

TI equation 5: V_RMS = 0.02058 × 58 / sqrt(1 − (4 × 0.0003 + 0.0003) × 175)
≈ 1.39 V. Register selection rounds down from the 1.4 V target.
TI equation 9: peak clamp = 0.02122 × 94 = 1.99468 V.
These are configured targets, not measured output voltages.
The C10-100 datasheet recommends a typical 30% reduction from its 2 V RMS rating
for auto-resonance, with application-specific validation.

Sources: [TI DRV2605L, sections 8.5.2 and 8.5.6](https://www.ti.com/lit/ds/symlink/drv2605l.pdf)
and [C10-100 R006 datasheet](https://www.precisionmicrodrives.com/datasheets/C10-100%20-%20datasheet-006.pdf).
The supplier listing identifies C10-100; the R7 suffix is not resolved by that sheet.

## Procedure

Reset and capture configuration readbacks. Send `c` to energize the motor for
calibration; wait for `CAL RESULT` and `CAL PASSED`. Send `1` separately for a
300 ms pulse followed by 100 ms braking. `0` stops/disarms even during calibration.
Calibration has a 1500 ms timeout. Reset to repeat; no OTP results are stored.

## Hardware results

**Calibration and one closed-loop pulse completed successfully, per user-provided serial output.**

Upload verified on 2026-11-11 to `/dev/cu.usbmodem3101`, ESP32-C3
MAC `1c:db:d4:eb:c9:f0`. Flash hashes verified. No calibration or pulse
command was sent during upload.

Record the following after the physical test:

- Board identity and motor mounting condition.
- Configuration readbacks, raw status, COMP (0x18), BEMF (0x19), FEEDBACK (0x1A), elapsed calibration time.
- Reported resonance values during playback (not independent proof of lock).
- Perceived strength, braking behavior, any errors, and measured voltage/current if available.

The open-loop diagnostic at 175.11 Hz and nominal 1.99468 V peak clamp produced
a perceptible pulse that the user reported as stronger. This is a comparison
observation, not a closed-loop calibration result.

## Software validation

All five PlatformIO environments compiled successfully. A temporary host harness
with simulated I2C and time passed checks for startup playback gating, calibration
success/failure/timeout, manual stop during calibration, single-pulse enforcement,
300 ms playback plus 100 ms braking, I2C/current-fault shutdown, and timer rollover.
These checks validate control flow only; they do not validate the physical driver,
calibration quality, resonance lock, or motor voltage.

## First closed-loop result — 2026-11-11

User-provided serial output:

```text
CAL RESULT: status=0xE0 COMP=0x06 BEMF=0x23 FEEDBACK=0xAB elapsed=1002 ms
Config 0x01: expected 0x40, read 0x40: OK
CAL PASSED. READY: send 1 for one 300 ms pulse; 0 stops/disarms.
PULSE START: closed-loop, ~1.39 V RMS target, ~1.99 V peak clamp, 300 ms (not measured).
Reported resonance: raw=58, 175.11 Hz (not independent lock verification).
Reported resonance: raw=58, 175.11 Hz (not independent lock verification).
PULSE END: zero RTP; allowing 100 ms for automatic braking.
BRAKING END: standby.
Test disabled. Reset required for another calibration/pulse.
Pulse unavailable: successful calibration required; one pulse per reset.
```

Calibration completed without the diagnostic/current/temperature fault bits set.
The driver reported the same resonance period twice. Playback and braking ended,
and a second pulse was correctly rejected. Perceived closed-loop strength and
physical stopping behavior have not yet been reported; voltage/current were not
measured. These calibration results belong to this tested actuator and are not
validated for the other prototype. Normal wristband firmware still uses open-loop
period 60 / clamp 30; closed-loop integration remains pending approval.
