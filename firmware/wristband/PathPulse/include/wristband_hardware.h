#pragma once

namespace WristbandHardware {
// PCB routing uses explicit GPIO numbers rather than the board's default I2C pins.
constexpr int kSdaPin = 7; // XIAO ESP32-C3 D5.
constexpr int kSclPin = 6; // XIAO ESP32-C3 D4.
}
