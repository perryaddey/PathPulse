#pragma once

namespace WristbandBLE {
/**
 * Starts the command service and advertises as PathPulse-Left.
 * May run even if motor initialization failed; the motor player rejects commands then.
 * @return True if the command handoff buffer was allocated and BLE started.
 */
bool begin();

/** Dispatches received commands and handles disconnects from the motor's main loop. */
void update();
}
