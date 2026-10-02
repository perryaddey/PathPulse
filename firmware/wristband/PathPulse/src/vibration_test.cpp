#include <Arduino.h>
#include "vibrations.h"

namespace {
constexpr int kSdaPin = 4;
constexpr int kSclPin = 5;
}

/** Starts serial pattern testing and calibrates the haptic driver on GPIO 4/5. */
void setup() {
  Serial.begin(115200);
  delay(1000);
  if (!Vibrations::begin(kSdaPin, kSclPin)) {
    Serial.println("Haptic startup failed. Check wiring and reset.");
    return;
  }
  Serial.println("Ready: type 0-8 in Serial Monitor (115200 baud).");
  Serial.println("0 stop, 1 turn, 2 bear, 3 straight, 4 arrived, 5 sharp,");
  Serial.println("6 turn-around (bench only), 7 guidance unavailable, 8 obstacle.");
}

/**
 * Services non-blocking playback and accepts one ASCII digit per serial command.
 * Serial is a bench adapter only; the future BLE interface will use binary IDs.
 */
void loop() {
  Vibrations::update();
  if (Serial.available() > 0) {
    const int input = Serial.read();
    if (input >= '0' && input <= '8') {
      const uint8_t command = static_cast<uint8_t>(input - '0');
      const bool accepted = Vibrations::play(command);
      Serial.print("Command ");
      Serial.print(command);
      Serial.println(accepted ? " accepted" : " ignored (priority or driver unavailable)");
    } else if (input != '\r' && input != '\n' && input != ' ' && input != '\t') {
      Serial.println("Unknown command. Type one digit from 0 to 8.");
    }
  }
}
