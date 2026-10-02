#include <Arduino.h>
#include "vibrations.h"

/** Initializes the wristband motor driver; BLE command handling is not implemented yet. */
void setup() {
  Serial.begin(115200);
  delay(1000);
  if (!Vibrations::begin(4, 5)) {
    Serial.println("Haptic startup failed. Check wiring and reset.");
    return;
  }
  Serial.println("Wristband ready; BLE command handling is not implemented yet.");
}

/** Services the pattern player without starting any automatic vibration pattern. */
void loop() {
  Vibrations::update();
}
