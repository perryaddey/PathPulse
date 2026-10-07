#include <Arduino.h>
#include "vibrations.h"
#include "wristband_ble.h"

/** Attempts motor calibration, then starts BLE even if motor output is unavailable. */
void setup() {
  Serial.begin(115200);
  delay(1000);
  if (!Vibrations::begin(4, 5)) {
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
