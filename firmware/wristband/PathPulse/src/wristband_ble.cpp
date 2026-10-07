#include "wristband_ble.h"
#include "vibrations.h"
#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <atomic>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>

namespace {
constexpr char kDeviceName[] = "PathPulse-Left";
constexpr char kServiceUUID[] = "7ca10001-8e6b-4b2d-a9f0-6c3d52e18470";
constexpr char kCommandUUID[] = "7ca10002-8e6b-4b2d-a9f0-6c3d52e18470";
// Transport handoff only: commands never wait for a vibration pattern to finish.
constexpr UBaseType_t kBufferSize = 16;
QueueHandle_t commands = nullptr;
std::atomic<bool> restartAdvertising{false};

class ConnectionCallbacks : public BLEServerCallbacks {
  /**
   * Logs the connection; advertising remains stopped while connected.
   * @param server The server reporting the connection.
   */
  void onConnect(BLEServer* server) override {
    Serial.println("BLE connected.");
  }

  /**
   * Clears stale commands and requests a motor stop before advertising again.
   * @param server The server reporting the disconnection.
   */
  void onDisconnect(BLEServer* server) override {
    xQueueReset(commands);
    const uint8_t stop = 0;
    xQueueSend(commands, &stop, 0);
    restartAdvertising.store(true);
    Serial.println("BLE disconnected.");
  }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
  /**
   * Validates a binary command and hands it to the main loop without accessing I2C.
   * Stop clears pending commands. Buffer overflow discards pending work and stops.
   * @param characteristic The characteristic containing the client's write.
   */
  void onWrite(BLECharacteristic* characteristic) override {
    const std::string value = characteristic->getValue();
    if (value.size() != 1 || static_cast<uint8_t>(value[0]) > 8) {
      Serial.println("BLE ignored: expected one binary byte 0-8.");
      return;
    }
    const uint8_t command = static_cast<uint8_t>(value[0]);
    if (command == 0) {
      xQueueReset(commands);
    }
    if (xQueueSend(commands, &command, 0) != pdTRUE) {
      xQueueReset(commands);
      const uint8_t stop = 0;
      xQueueSend(commands, &stop, 0);
      Serial.println("BLE buffer full: pending commands discarded, stopping.");
    }
  }
};

ConnectionCallbacks connectionCallbacks;
CommandCallbacks commandCallbacks;
}

namespace WristbandBLE {
/**
 * Allocates the command buffer and advertises the writable haptic service.
 * The full device name uses the scan response so the 128-bit service UUID fits.
 * @return Whether the command buffer was allocated and BLE initialization completed.
 */
bool begin() {
  commands = xQueueCreate(kBufferSize, sizeof(uint8_t));
  if (commands == nullptr) {
    return false;
  }
  BLEDevice::init(kDeviceName);
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(&connectionCallbacks);
  BLEService* service = server->createService(kServiceUUID);
  BLECharacteristic* command = service->createCharacteristic(
      kCommandUUID, BLECharacteristic::PROPERTY_WRITE);
  command->setCallbacks(&commandCallbacks);
  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  BLEAdvertisementData advertisement;
  advertisement.setFlags(0x06); // General discoverable, Bluetooth Classic unsupported.
  advertisement.setCompleteServices(BLEUUID(kServiceUUID));
  advertising->setAdvertisementData(advertisement);
  BLEAdvertisementData scanResponse;
  scanResponse.setName(kDeviceName);
  advertising->setScanResponseData(scanResponse);
  advertising->setScanResponse(true);
  advertising->start();
  Serial.println("BLE advertising as PathPulse-Left.");
  return true;
}

/**
 * Dispatches at most one buffer's worth of commands without waiting for playback.
 * Stops before restarting advertising after a disconnect; call only from loop().
 */
void update() {
  if (commands == nullptr) {
    return;
  }
  if (restartAdvertising.exchange(false)) {
    Vibrations::play(0);
    BLEDevice::startAdvertising();
  }
  uint8_t command;
  for (UBaseType_t count = 0;
       count < kBufferSize && xQueueReceive(commands, &command, 0) == pdTRUE;
       ++count) {
    const bool accepted = Vibrations::play(command);
    Serial.printf("BLE command %u %s\n", command,
                  accepted ? "accepted" : "ignored (priority or driver unavailable)");
  }
}
}
