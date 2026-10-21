#include "vibrations.h"
#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_DRV2605.h>

namespace {
constexpr uint8_t kFullStrength = 0x7F;
constexpr uint32_t kGapMs = 200;
constexpr uint32_t kFaultCheckMs = 50;
// Match the verified diagnostic setup: 0.64 V nominal peak at approximately 169 Hz.
constexpr uint8_t kVoltageClamp = 30;
constexpr uint8_t kOpenLoopPeriod = 60;
constexpr uint8_t kStandbyMode = 0x40;
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

/**
 * Reads a driver register with explicit I2C error detection.
 * @param address Register address on the DRV2605L at I2C address 0x5A.
 * @param value Destination for the byte read; unchanged on failure.
 * @return Whether the register address and byte were transferred successfully.
 */
bool readChecked(uint8_t address, uint8_t &value) {
  Wire.beginTransmission(0x5A);
  Wire.write(address);
  if (Wire.endTransmission(false) != 0 || Wire.requestFrom(uint8_t(0x5A), uint8_t(1)) != 1) {
    Serial.printf("ERROR: I2C read failed at register 0x%02X.\n", address);
    return false;
  }
  value = Wire.read();
  return true;
}

/**
 * Logs a configuration register and compares its relevant bits with expectations.
 * @param address Register address to read.
 * @param expected Expected configured value before calibration.
 * @param mask Bits to compare, excluding reserved bits.
 * @return Whether the read succeeded and all selected bits matched.
 */
bool verifyRegister(uint8_t address, uint8_t expected, uint8_t mask) {
  uint8_t actual = 0;
  if (!readChecked(address, actual)) { return false; }
  const bool matches = (actual & mask) == (expected & mask);
  Serial.printf("Config 0x%02X = 0x%02X; expected 0x%02X mask 0x%02X: %s\n",
                address, actual, expected, mask, matches ? "OK" : "MISMATCH");
  return matches;
}
}

namespace Vibrations {
/**
 * Initializes the LRA in fixed-frequency open-loop RTP mode without calibration.
 * This matches the low-voltage configuration that produced a confirmed motor pulse.
 * @param sdaPin GPIO used for I2C data.
 * @param sclPin GPIO used for I2C clock.
 * @return True when configuration and driver checks pass; false on initialization or driver failure.
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

  // An ESP32 reset does not necessarily power-cycle the separately powered driver.
  // DEV_RESET restores volatile registers; it does not program OTP memory.
  hapticDriver.writeRegister8(DRV2605_REG_MODE, 0x80);
  const uint32_t resetStart = millis();
  uint8_t mode = 0x80;
  do {
    delay(1);
    if (!readChecked(DRV2605_REG_MODE, mode)) { return false; }
    if (millis() - resetStart >= 500) {
      Serial.println("ERROR: Driver reset timed out.");
      return false;
    }
  } while (mode & 0x80);
  Serial.println("DRV2605L reset complete.");
  if (!hapticDriver.begin(&Wire)) {
    Serial.println("ERROR: Driver unavailable after reset.");
    return false;
  }

  hapticDriver.stop();
  hapticDriver.setMode(kStandbyMode);
  hapticDriver.writeRegister8(DRV2605_REG_CLAMPV, kVoltageClamp);
  hapticDriver.writeRegister8(DRV2605_REG_FEEDBACK, 0xB6); // LRA mode.
  hapticDriver.writeRegister8(0x1C, 0xF5); // Bidirectional input for signed RTP.
  hapticDriver.writeRegister8(DRV2605_REG_CONTROL3, 0x81); // Open-loop LRA, RTP, supply compensation.
  hapticDriver.writeRegister8(0x20, kOpenLoopPeriod);
  bool configurationOK = true;
  configurationOK &= verifyRegister(DRV2605_REG_CLAMPV, kVoltageClamp, 0xFF);
  configurationOK &= verifyRegister(DRV2605_REG_FEEDBACK, 0xB6, 0xFF);
  configurationOK &= verifyRegister(0x1C, 0xF5, 0xFF);
  configurationOK &= verifyRegister(DRV2605_REG_CONTROL3, 0x81, 0xFF);
  configurationOK &= verifyRegister(0x20, kOpenLoopPeriod, 0x7F);
  configurationOK &= verifyRegister(DRV2605_REG_MODE, kStandbyMode, 0xC7);
  if (!configurationOK) {
    hapticDriver.stop();
    hapticDriver.writeRegister8(DRV2605_REG_MODE, 0x40); // STANDBY, no playback.
    Serial.println("ERROR: Open-loop configuration verification failed.");
    return false;
  }
  uint8_t status = 0;
  if (!readChecked(DRV2605_REG_STATUS, status)) { return false; }
  if ((status & 0xE0) != 0xE0 || (status & 0x03)) {
    Serial.printf("ERROR: DRV2605L identity or fault check failed (status 0x%02X).\n", status);
    return false;
  }
  hapticDriver.setRealtimeValue(0);
  hapticDriver.setMode(DRV2605_MODE_REALTIME);
  driverReady = true;
  Serial.printf("Open-loop haptics ready: approximately %.1f Hz, 0.64 V peak clamp.\n",
                1000000.0 / (kOpenLoopPeriod * 98.46));
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
  lastFaultCheckMs = phaseStartMs;
  pulseOn = true;
  hapticDriver.setRealtimeValue(kFullStrength);
  return true;
}

/**
 * Advances a single pulse/gap phase using rollover-safe elapsed milliseconds.
 * Checks faults every 50 ms during playback, beginning 50 ms after the first pulse starts.
 * Late calls preserve a full off gap instead of rushing overdue pulses together.
 */
void update() {
  if (!driverReady || activeCommand == 0) {
    return;
  }
  const uint32_t now = millis();
  if (now - lastFaultCheckMs >= kFaultCheckMs) {
    lastFaultCheckMs = now;
    const uint8_t status = hapticDriver.readRegister8(DRV2605_REG_STATUS);
    if (status & 0x03) {
      stopPlayback();
      hapticDriver.setMode(kStandbyMode);
      driverReady = false;
      Serial.printf("ERROR: Driver temperature/current fault (status 0x%02X). Reset required.\n", status);
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
