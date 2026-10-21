#include <Arduino.h>
#include <Wire.h>

namespace {
constexpr uint8_t kAddress = 0x5A;
constexpr uint8_t kClamp = 30; // 30 * 0.02122 = 0.6366 V nominal peak clamp.
constexpr uint8_t kPeriod = 60; // 60 * 98.46 us = 5907.6 us, approximately 169.27 Hz.
constexpr uint32_t kPulseMs = 300;
constexpr uint32_t kFaultPollMs = 20;
bool armed = false;
bool active = false;
uint32_t pulseStart = 0;
uint32_t lastFaultPoll = 0;

/**
 * Writes one driver register, checking the I2C acknowledgement.
 * @param address The DRV2605L register address.
 * @param value The register value to write.
 * @return Whether the driver acknowledged the write.
 */
bool writeRegister(uint8_t address, uint8_t value) {
  Wire.beginTransmission(kAddress);
  Wire.write(address);
  Wire.write(value);
  return Wire.endTransmission() == 0;
}

/**
 * Reads one driver register with explicit transfer checks.
 * @param address The DRV2605L register address.
 * @param value Destination for the result; unchanged on failure.
 * @return Whether both the register selection and data read succeeded.
 */
bool readRegister(uint8_t address, uint8_t &value) {
  Wire.beginTransmission(kAddress);
  Wire.write(address);
  if (Wire.endTransmission(false) != 0 || Wire.requestFrom(kAddress, uint8_t(1)) != 1) {
    return false;
  }
  value = Wire.read();
  return true;
}

/**
 * Writes and verifies a configuration register before motor playback is allowed.
 * @param address The register to configure.
 * @param value The expected register value.
 * @param mask Bits to verify, excluding reserved bits.
 * @return Whether the write, read, and comparison succeeded.
 */
bool configureRegister(uint8_t address, uint8_t value, uint8_t mask = 0xFF) {
  uint8_t actual = 0;
  const bool ok = writeRegister(address, value) && readRegister(address, actual)
      && (actual & mask) == (value & mask);
  Serial.printf("Config 0x%02X: expected 0x%02X, read 0x%02X: %s\n",
                address, value, actual, ok ? "OK" : "FAILED");
  return ok;
}

/**
 * Clears RTP output, requests standby, and disables further pulses until reset.
 * Both stop writes are attempted even if the first fails. An I2C failure cannot
 * guarantee physical shutdown, so the log requests removal of USB power.
 * @param reason The completion or failure reason to print after stopping.
 */
void stopTest(const char *reason) {
  active = false;
  armed = false;
  const bool zeroOK = writeRegister(0x02, 0x00);
  const bool standbyOK = writeRegister(0x01, 0x40);
  Serial.println(reason);
  if (!zeroOK || !standbyOK) {
    Serial.println("ERROR: Stop write failed. Disconnect USB power.");
  } else {
    Serial.println("Output zeroed; driver in standby. Reset required for another test.");
  }
}

/**
 * Checks temperature/current status without treating calibration as a prerequisite.
 * @return Whether the status read succeeded and no temperature/current fault is set.
 */
bool checkFaults() {
  uint8_t status = 0;
  if (!readRegister(0x00, status)) {
    stopTest("ERROR: Status read failed.");
    return false;
  }
  if (status & 0x03) {
    stopTest("ERROR: Temperature/current fault; test disabled.");
    Serial.printf("Fault status: 0x%02X\n", status);
    return false;
  }
  return true;
}

/** Starts the sole permitted 300 ms pulse after a manual command and fault check. */
void startTest() {
  if (!armed || active) {
    Serial.println("Test unavailable: only one pulse is permitted per reset.");
    return;
  }
  if (!checkFaults()) { return; }
  armed = false;
  Serial.println("PULSE START: approximately 169 Hz, 0.64 V peak clamp, 300 ms.");
  // Signed RTP 0x7F selects full scale of the deliberately reduced clamp.
  // Load the amplitude while in standby, then enter RTP to begin output.
  pulseStart = millis();
  lastFaultPoll = pulseStart;
  if (!writeRegister(0x02, 0x7F) || !writeRegister(0x01, 0x05)) {
    stopTest("ERROR: Could not start pulse.");
    return;
  }
  active = true;
}
}

/**
 * Initializes an isolated open-loop LRA test on GPIO 4/5, without calibration or BLE.
 * Verifies frequency and reduced clamp before accepting a manual serial command.
 * TI DRV2605L datasheet sections 8.5.2.2, 8.5.4.2, and 8.6.26 define these settings.
 */
void setup() {
  Serial.begin(115200);
  delay(1000);
  if (!Wire.begin(4, 5)) {
    Serial.println("ERROR: I2C initialization failed.");
    return;
  }
  Wire.setTimeOut(20); // Bound a stalled transaction so the pulse loop can stop.
  if (!writeRegister(0x01, 0x80)) {
    stopTest("ERROR: Driver reset write failed.");
    return;
  }
  const uint32_t resetStart = millis();
  uint8_t mode = 0x80;
  do {
    delay(1);
    if (!readRegister(0x01, mode) || millis() - resetStart >= 500) {
      stopTest("ERROR: Driver reset failed or timed out.");
      return;
    }
  } while (mode & 0x80);
  uint8_t status = 0;
  if (!readRegister(0x00, status) || (status & 0xE0) != 0xE0 || (status & 0x03)) {
    stopTest("ERROR: Expected DRV2605L identity and fault-free startup.");
    return;
  }
  // Remain in standby throughout configuration. Never write OTP registers.
  if (!configureRegister(0x01, 0x40, 0xC7)
      || !configureRegister(0x02, 0x00)
      || !configureRegister(0x17, kClamp)
      || !configureRegister(0x1A, 0xB6) // LRA mode; default feedback settings unused here.
      || !configureRegister(0x1C, 0xF5) // Bidirectional input required for open loop.
      || !configureRegister(0x1D, 0x81) // LRA open loop, signed RTP, supply compensation on.
      || !configureRegister(0x20, kPeriod, 0x7F)) {
    stopTest("ERROR: Configuration verification failed.");
    return;
  }
  armed = true;
  Serial.println("READY: send 1 for one 300 ms pulse; 0 stops/disarms. No automatic playback.");
}

/**
 * Services manual commands, automatic pulse termination, and 20 ms fault checks.
 * Repeated commands cannot extend the pulse or start another without a board reset.
 */
void loop() {
  if (active) {
    const uint32_t now = millis();
    if (now - pulseStart >= kPulseMs) {
      stopTest("PULSE END: duration elapsed.");
    } else if (now - lastFaultPoll >= kFaultPollMs) {
      lastFaultPoll = now;
      checkFaults();
    }
  }
  if (Serial.available() > 0) {
    const int command = Serial.read();
    if (command == '0') {
      stopTest("Manual stop.");
    } else if (command == '1') {
      startTest();
    }
  }
  delay(1);
}
