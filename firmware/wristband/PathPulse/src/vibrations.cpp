#include "vibrations.h"
#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_DRV2605.h>

namespace {
constexpr uint8_t kFullStrength = 0x7F;
constexpr uint32_t kGapMs = 200;
constexpr uint32_t kFaultCheckMs = 50;
// NFP-ELV959535: 0.9 Vrms, 170 Hz. TI DRV2605L datasheet sections 8.5.2–8.5.3.
// At SAMPLE_TIME=300 us: floor(0.9 * sqrt(1 - 0.0015 * 170) / 0.02058).
constexpr uint8_t kRatedVoltage = 37;
// Conservative peak clamp: floor(0.9 * sqrt(2) / 0.02122), no extra overdrive.
constexpr uint8_t kVoltageClamp = 59;
// Half-period is 2.94 ms; DRIVE_TIME uses 0.5 ms + value * 0.1 ms.
constexpr uint8_t kDriveTime = 24;
Adafruit_DRV2605 hapticDriver;
bool driverReady = false;


struct Pattern {
  uint8_t count;
  uint16_t pulsesMs[5];
};
constexpr Pattern kPatterns[] = {
    {0, {0}},
    {2, {400, 400}},
    {1, {400}},
    {1, {800}},
    {3, {200, 200, 800}},
    {3, {400, 400, 400}},
    {2, {800, 800}}, // Bench only until the app supports walking turn-around detection.
    {3, {800, 200, 200}},
    {5, {200, 200, 200, 200, 200}},
};
uint8_t activeCommand = 0;
uint8_t pulseIndex = 0;
bool pulseOn = false;
uint32_t phaseStartMs = 0;
uint32_t lastFaultCheckMs = 0;

/** Stops motor output and clears the current pattern without queueing another cue. */
void stopPlayback() {
  hapticDriver.setRealtimeValue(0);
  activeCommand = 0;
  pulseOn = false;
  pulseIndex = 0;
}
}

namespace Vibrations {
/**
 * Initializes the driver and performs bounded startup calibration for the LRA.
 * Logs the post-calibration status and fault bits; failures leave playback disabled.
 * @param sdaPin GPIO used for I2C data.
 * @param sclPin GPIO used for I2C clock.
 * @return True after successful calibration; false on initialization or driver failure.
 */
bool begin(int sdaPin, int sclPin) {
  driverReady = false;
  activeCommand = 0;
  if (!Wire.begin(sdaPin, sclPin)) {
    Serial.println("ERROR: Could not initialize I2C.");
    return false;
  }

  if (!hapticDriver.begin(&Wire)) {
    Serial.println("ERROR: DRV2605L not found at 0x5A. Check power, GND, SDA and SCL.");
    return false;
  }

  hapticDriver.useLRA();
  hapticDriver.stop();
  hapticDriver.writeRegister8(DRV2605_REG_RATEDV, kRatedVoltage);
  hapticDriver.writeRegister8(DRV2605_REG_CLAMPV, kVoltageClamp);
  hapticDriver.writeRegister8(DRV2605_REG_CONTROL1,
      (hapticDriver.readRegister8(DRV2605_REG_CONTROL1) & 0xE0) | kDriveTime);
  hapticDriver.writeRegister8(DRV2605_REG_CONTROL2, 0xF5); // 300 us sampling.
  hapticDriver.writeRegister8(DRV2605_REG_CONTROL3,
      hapticDriver.readRegister8(DRV2605_REG_CONTROL3) & ~0x29); // Closed loop, signed RTP.
  hapticDriver.writeRegister8(DRV2605_REG_CONTROL4,
      (hapticDriver.readRegister8(DRV2605_REG_CONTROL4) & 0xCF) | 0x30);
  hapticDriver.setMode(DRV2605_MODE_AUTOCAL);
  Serial.println("Calibrating NFP-ELV959535...");
  hapticDriver.go();
  const uint32_t calibrationStart = millis();
  while (hapticDriver.readRegister8(DRV2605_REG_GO) & 0x01) {
    if (millis() - calibrationStart >= 2000) {
      hapticDriver.stop();
      Serial.println("ERROR: Calibration timed out. Check driver and motor wiring.");
      return false;
    }
    delay(10);
  }
  // DIAG_RESULT, overtemperature, or overcurrent must prevent playback.
  const uint8_t status = hapticDriver.readRegister8(DRV2605_REG_STATUS);
  Serial.printf("DRV2605L status: 0x%02X; diagnostic failure=%u, overtemperature=%u, overcurrent=%u\n",
                status, (status >> 3) & 1, (status >> 1) & 1, status & 1);
  if (status & 0x0B) {
    Serial.println("ERROR: Calibration failed or driver fault. Check motor connections.");
    return false;
  }
  hapticDriver.setRealtimeValue(0);
  hapticDriver.setMode(DRV2605_MODE_REALTIME);
  driverReady = true;
  return true;
}

/**
 * Accepts a pattern or stop command; an active obstacle warning blocks other cues.
 * @param command Binary command ID from 0 to 8.
 * @return True if accepted, false for unknown commands, unavailable hardware, or priority rejection.
 */
bool play(uint8_t command) {
  if (!driverReady || command >= sizeof(kPatterns) / sizeof(kPatterns[0])) {
    return false;
  }
  if (command == 0) {
    stopPlayback();
    return true;
  }
  if (activeCommand == 8) {
    return false; // Includes repeated obstacle commands: never extend a warning indefinitely.
  }
  stopPlayback();
  activeCommand = command;
  phaseStartMs = millis();
  lastFaultCheckMs = phaseStartMs - kFaultCheckMs;
  pulseOn = true;
  hapticDriver.setRealtimeValue(kFullStrength);
  return true;
}

/**
 * Advances a single pulse/gap phase using rollover-safe elapsed milliseconds.
 * Checks faults every 50 ms during playback and disables output on a fault.
 * Late calls preserve a full off gap instead of rushing overdue pulses together.
 */
void update() {
  if (!driverReady || activeCommand == 0) {
    return;
  }
  const uint32_t now = millis();
  if (now - lastFaultCheckMs >= kFaultCheckMs) {
    lastFaultCheckMs = now;
    if (hapticDriver.readRegister8(DRV2605_REG_STATUS) & 0x03) {
      stopPlayback();
      hapticDriver.setMode(DRV2605_MODE_INTTRIG);
      driverReady = false;
      Serial.println("ERROR: Driver temperature/current fault. Reset required.");
      return;
    }
  }
  const Pattern &pattern = kPatterns[activeCommand];
  const uint32_t duration = pulseOn ? pattern.pulsesMs[pulseIndex] : kGapMs;
  if (now - phaseStartMs < duration) {
    return;
  }
  phaseStartMs = now;
  if (pulseOn) {
    hapticDriver.setRealtimeValue(0);
    pulseOn = false;
    if (++pulseIndex >= pattern.count) {
      stopPlayback();
    }
  } else {
    pulseOn = true;
    hapticDriver.setRealtimeValue(kFullStrength);
  }
}
}
