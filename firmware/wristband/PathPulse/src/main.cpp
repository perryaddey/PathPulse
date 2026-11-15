#include <Arduino.h>
#include "vibrations.h"
#include "wristband_ble.h"
#include "wristband_hardware.h"

/** Configures haptics on PCB SDA GPIO7/SCL GPIO6, then starts BLE even if haptics fail. */
void setup() {
  Serial.begin(115200);
  delay(1000);
  if (!Vibrations::begin(WristbandHardware::kSdaPin, WristbandHardware::kSclPin)) {
    Serial.println("Haptic startup failed. Vibration disabled; starting BLE for connection testing.");
  }
  if (!WristbandBLE::begin()) {
    Serial.println("BLE startup failed. Reset the board.");
  }
}

/** Dispatches BLE commands and services non-blocking motor playback on the same task. */
void loop() {
  WristbandBLE::update();
  Vibrations::update();
  delay(1); // Yield to the BLE and system tasks.
}
