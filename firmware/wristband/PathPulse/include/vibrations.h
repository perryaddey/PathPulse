#pragma once
#include <stdint.h>

namespace Vibrations {
/**
 * Initializes I2C and calibrates the NFP-ELV959535 motor; may vibrate during startup.
 * @param sdaPin GPIO connected to the driver's SDA pin.
 * @param sclPin GPIO connected to the driver's SCL pin.
 * @return Whether the driver is ready for pattern playback.
 */
bool begin(int sdaPin, int sclPin);

/**
 * Starts a finite pattern, replacing a non-obstacle pattern, or stops on command 0.
 * Commands during an obstacle warning are ignored except stop. No cues are queued.
 * Call from the main loop, not concurrently from a BLE callback.
 * @param command Binary command ID, 0 through 8; unknown values are ignored.
 * @return Whether the command was accepted. ID 6 is available for bench testing only.
 */
bool play(uint8_t command);

/**
 * Advances playback without delays and checks driver faults while a pattern is active.
 * Call frequently from the main loop. A driver fault disables playback until reset.
 */
void update();
}
