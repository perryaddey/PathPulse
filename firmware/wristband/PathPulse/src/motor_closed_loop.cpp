#include <Arduino.h>
#include <Wire.h>
#include "wristband_hardware.h"

namespace {
constexpr uint8_t kAddress = 0x5A;
// TI equation 5: 0.02058 * 58 / sqrt(1 - (4 * 0.0003 + 0.0003) * 175)
// = approximately 1.39 V RMS. C10-100 auto-resonance starting target: 30% below 2 V RMS.
constexpr uint8_t kRatedVoltage = 58;
constexpr uint8_t kClamp = 94; // TI equation 9: 1.99468 V nominal peak, not measured.
constexpr uint32_t kCalibrationTimeoutMs = 1500;
constexpr uint32_t kPulseMs = 300;
constexpr uint32_t kBrakeMs = 100;
enum class State { Disabled, AwaitCalibration, Calibrating, Ready, Playing, Braking };
State state = State::Disabled;
uint32_t phaseStart = 0;
uint32_t lastPoll = 0;
uint32_t lastResonance = 0;

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
 * Attempts all stop writes and disables further activity until board reset.
 * @param reason Completion or error message to print after stopping output.
 */
void stopTest(const char *reason) {
  state = State::Disabled;
  const bool zeroOK = writeRegister(0x02, 0);
  const bool goOK = writeRegister(0x0C, 0);
  const bool standbyOK = writeRegister(0x01, 0x40);
  Serial.println(reason);
  if (!zeroOK || !goOK || !standbyOK) {
    Serial.println("ERROR: Stop write failed. Disconnect driver power.");
  }
  Serial.println("Test disabled. Reset required for another calibration/pulse.");
}

/**
 * Checks driver identity and temperature/current flags; stops on read failure or fault.
 * @return Whether the driver responded with the expected identity and no hardware fault.
 */
bool checkFaults() {
  uint8_t status = 0;
  if (!readRegister(0x00, status) || (status & 0xE0) != 0xE0 || (status & 0x03)) {
    stopTest("ERROR: Driver identity, I2C, or temperature/current fault.");
    Serial.printf("Status: 0x%02X\n", status);
    return false;
  }
  return true;
}

/** Starts one manually requested calibration, which energizes the motor for up to 1500 ms. */
void startCalibration() {
  if (state != State::AwaitCalibration) {
    Serial.println("Calibration unavailable in this state; reset to start again.");
    return;
  }
  if (!checkFaults()) { return; }
  Serial.println("CAL START: motor will vibrate; target ~1.39 V RMS, clamp ~1.99 V peak.");
  phaseStart = lastPoll = millis();
  state = State::Calibrating;
  if (!writeRegister(0x01, 0x07) || !writeRegister(0x0C, 1)) {
    stopTest("ERROR: Could not start calibration.");
  }
}

/** Validates completed calibration, logs volatile results, and arms one manual pulse. */
void finishCalibration() {
  uint8_t status = 0, compensation = 0, bemf = 0, feedback = 0;
  if (!readRegister(0x00, status) || !readRegister(0x18, compensation)
      || !readRegister(0x19, bemf) || !readRegister(0x1A, feedback)) {
    stopTest("ERROR: Calibration result read failed.");
    return;
  }
  Serial.printf("CAL RESULT: status=0x%02X COMP=0x%02X BEMF=0x%02X FEEDBACK=0x%02X elapsed=%lu ms\n",
                status, compensation, bemf, feedback, static_cast<unsigned long>(millis() - phaseStart));
  if ((status & 0xE0) != 0xE0 || (status & 0x0B)) {
    stopTest("CAL FAILED: diagnostic or hardware fault; no playback permitted.");
    return;
  }
  if (!configureRegister(0x01, 0x40, 0xC7)) {
    stopTest("ERROR: Could not enter standby after calibration.");
    return;
  }
  state = State::Ready;
  Serial.println("CAL PASSED. READY: send 1 for one 300 ms pulse; 0 stops/disarms.");
}

/** Starts one 300 ms unsigned, unidirectional closed-loop RTP pulse after calibration. */
void startPulse() {
  if (state != State::Ready) {
    Serial.println("Pulse unavailable: successful calibration required; one pulse per reset.");
    return;
  }
  if (!checkFaults()) { return; }
  Serial.println("PULSE START: closed-loop, ~1.39 V RMS target, ~1.99 V peak clamp, 300 ms (not measured).");
  phaseStart = lastPoll = lastResonance = millis();
  state = State::Playing;
  if (!writeRegister(0x02, 0xFF) || !writeRegister(0x01, 0x05)) {
    stopTest("ERROR: Could not start pulse.");
  }
}

/** Services calibration, bounded playback/braking, and fault polling without blocking serial stop. */
void updateTest() {
  const uint32_t now = millis();
  if (state == State::Calibrating && now - phaseStart >= kCalibrationTimeoutMs) {
    stopTest("CAL TIMEOUT.");
    return;
  }
  if (state == State::Playing && now - phaseStart >= kPulseMs) {
    if (!writeRegister(0x02, 0)) {
      stopTest("ERROR: Could not start braking.");
      return;
    }
    state = State::Braking;
    phaseStart = millis();
    Serial.println("PULSE END: zero RTP; allowing 100 ms for automatic braking.");
    return;
  }
  if (state == State::Braking && now - phaseStart >= kBrakeMs) {
    stopTest("BRAKING END: standby.");
    return;
  }
  if (state != State::Calibrating && state != State::Playing && state != State::Braking) { return; }
  if (now - lastPoll >= 20) {
    lastPoll = now;
    if (!checkFaults()) { return; }
    if (state == State::Calibrating) {
      uint8_t go = 0;
      if (!readRegister(0x0C, go)) { stopTest("ERROR: Calibration GO read failed."); return; }
      if (!(go & 1)) { finishCalibration(); return; }
    }
  }
  if (state == State::Playing && now - lastResonance >= 100) {
    lastResonance = now;
    uint8_t period = 0;
    if (!readRegister(0x22, period)) { stopTest("ERROR: Resonance read failed."); return; }
    if (period == 0) {
      Serial.println("Resonance period unavailable (0); not proof of resonance lock.");
    } else {
      Serial.printf("Reported resonance: raw=%u, %.2f Hz (not independent lock verification).\n",
                    period, 1000000.0 / (period * 98.46));
    }
  }
}
}

/** Initializes the isolated closed-loop test in standby; calibration requires a manual c command. */
void setup() {
  Serial.begin(115200);
  delay(1000);
  if (!Wire.begin(WristbandHardware::kSdaPin, WristbandHardware::kSclPin)) {
    Serial.println("ERROR: I2C initialization failed.");
    return;
  }
  Wire.setTimeOut(20);
  if (!writeRegister(0x01, 0x80)) { stopTest("ERROR: Reset write failed."); return; }
  const uint32_t resetStart = millis();
  uint8_t mode = 0x80;
  do {
    delay(1);
    if (!readRegister(0x01, mode) || millis() - resetStart >= 500) {
      stopTest("ERROR: Reset failed or timed out."); return;
    }
  } while (mode & 0x80);
  if (!checkFaults()) { return; }
  // TI sections 8.5.2 and 8.5.6. Configure while idle; only c sets calibration GO.
  if (!configureRegister(0x01, 0x40, 0xC7)
      || !configureRegister(0x02, 0)
      || !configureRegister(0x16, kRatedVoltage)
      || !configureRegister(0x17, kClamp)
      || !configureRegister(0x1A, 0xAA) // LRA, brake factor 2, loop gain 2, initial BEMF gain 2.
      || !configureRegister(0x1B, 0x97, 0xBF) // Boost; DRIVE_TIME=23: 2.8 ms initial half-period.
      || !configureRegister(0x1C, 0x75) // Unidirectional, brake stabilizer, 300 us sampling, 25 us blank/idiss.
      || !configureRegister(0x1D, 0x88) // Unsigned RTP, supply compensation, LRA closed loop.
      || !configureRegister(0x1E, 0x30, 0xF1) // 1000-1200 ms auto-cal; OTP_PROGRAM remains zero.
      || !configureRegister(0x1F, 0x80)) { // Auto-open-loop option disabled; blank/idiss upper bits zero.
    stopTest("ERROR: Configuration verification failed."); return;
  }
  state = State::AwaitCalibration;
  Serial.println("READY FOR CALIBRATION: c calibrates (motor vibrates); 1 requires CAL PASSED; 0 stops/disarms.");
}

/** Dispatches manual commands and services calibration/playback; stop disables the test until reset. */
void loop() {
  if (Serial.available() > 0) {
    const int command = Serial.read();
    if (command == '0') { stopTest("Manual stop."); }
    else if (command == 'c') { startCalibration(); }
    else if (command == '1') { startPulse(); }
  }
  updateTest();
  delay(1);
}
