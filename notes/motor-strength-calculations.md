# Motor strength calculations

These notes explain the current NFP-ELV959535 LRA settings in
[`vibrations.cpp`](../firmware/wristband/PathPulse/src/vibrations.cpp).

## What “full strength” means

We request the highest positive playback amplitude while using conservative
voltage settings based on the motor's rating. This is not a measurement of the
motor's maximum vibration, actual output voltage, or power consumption.

## Motor specifications

- Rated voltage: **0.9 Vrms AC**.
- Resonant frequency: **170 Hz**, nominal (manufacturer tolerance: ±10 Hz).
- Driver: **DRV2605L**, configured for closed-loop LRA operation.

Manufacturer reference:
[NFP-ELV959535 specifications](https://nfpmotor.com/newest-rectangular-linear-resonance-actuators-haptic-vibration-motor-model-nfp-elv959535).

## 1. Convert rated voltage to a driver register value

The driver expects an encoded value in its rated-voltage register, rather than
a voltage directly. Using the DRV2605L closed-loop LRA equation, with a sampling
time of 300 µs and a nominal frequency of 170 Hz:

```text
register = Vrms × sqrt(1 − (4 × sample_time_seconds + 0.0003) × frequency_hz)
           / 0.02058

         = 0.9 × sqrt(1 − 0.0015 × 170) / 0.02058
         ≈ 37.75
```

Round down to **37**, stored as `kRatedVoltage`. This sets a target slightly below
0.9 Vrms under the equation's assumptions; actual output has not been measured.

## 2. Set a conservative peak-voltage clamp

For a sine wave, peak voltage is RMS voltage multiplied by the square root of two:

```text
peak voltage = 0.9 × sqrt(2) ≈ 1.273 V
clamp register = peak voltage / 0.02122 ≈ 59.98
```

Round down to **59**, stored as `kVoltageClamp`. This corresponds to a nominal
clamp of about **1.252 V peak**. We intentionally allow no additional overdrive
above the rated sine-wave peak. This is a conservative choice, not a manufacturer
specification for the motor's absolute maximum transient voltage.

## 3. Request full playback amplitude

Signed real-time playback uses **127 (`0x7F`)** as its highest positive command.
This is `kFullStrength`. It requests full scale relative to the configured driver
settings; it does not request the full 3.3 V supply across the motor.

## 4. Initialize resonance tracking

The nominal half-period at 170 Hz is approximately 2.94 ms. The driver's initial
drive-time setting uses:

```text
drive time (ms) = 0.5 + register × 0.1
register ≈ (2.94 − 0.5) / 0.1 ≈ 24.4
```

We use **24** (`kDriveTime`), giving 2.9 ms as the initial estimate. Closed-loop
operation then tracks resonance, and startup auto-calibration adjusts the driver's
actuator feedback settings.

Driver equations and register descriptions:
[TI DRV2605L datasheet](https://www.ti.com/lit/ds/symlink/drv2605l.pdf),
sections 8.5.2–8.5.3 and the Control1 register description.

## What remains to be measured

The longer 500 ms test pulse felt stronger than a brief click without increasing
the configured voltage or amplitude. Pulse length and wristband mounting affect
perceived strength, so the final patterns still need testing on mounted wristbands.

Lab measurements are needed to verify actual motor voltage and electrical power.
Voltage alone does not establish power: real motor power is the average of
instantaneous voltage multiplied by instantaneous current. Driver input power is
a separate useful measurement for battery-life estimates and includes driver losses.

The motor output is differential. A grounded oscilloscope clip must not be attached
directly to either motor terminal; use an appropriate differential measurement setup
with lab assistance.
