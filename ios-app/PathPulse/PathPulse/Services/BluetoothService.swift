import CoreBluetooth
import Observation

@MainActor
@Observable
final class BluetoothService: NSObject, @preconcurrency CBCentralManagerDelegate,
    @preconcurrency CBPeripheralDelegate {
    struct Device: Identifiable {
        let id: UUID
        let name: String
    }

    private(set) var devices: [Device] = []
    private(set) var status = "Tap Scan to find your left wristband."
    private(set) var isScanning = false
    private(set) var isReady = false
    private(set) var hasConnection = false
    private(set) var commandStatus: String?

    private let serviceID = CBUUID(string: "7ca10001-8e6b-4b2d-a9f0-6c3d52e18470")
    private let commandID = CBUUID(string: "7ca10002-8e6b-4b2d-a9f0-6c3d52e18470")
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var selected: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var scanRequested = false
    private var timeout: Task<Void, Never>?

    /** Starts a bounded scan, requesting Bluetooth access on first use. */
    func scan() {
        guard !hasConnection else { return }
        scanRequested = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
            return
        }
        guard let central, central.state == .poweredOn else {
            if let central { centralManagerDidUpdateState(central) }
            return
        }
        scanRequested = false
        devices = []
        peripherals = [:]
        commandStatus = nil
        isScanning = true
        status = "Searching for PathPulse-Left…"
        central.scanForPeripherals(withServices: [serviceID])
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            self?.stopScan()
        }
    }

    /** Stops discovery and reports whether a left wristband was found. */
    func stopScan() {
        scanRequested = false
        guard isScanning else { return }
        central?.stopScan()
        isScanning = false
        timeout?.cancel()
        status = devices.isEmpty ? "No left wristband found. Check its power and scan again."
            : "Select your left wristband to connect."
    }

    /**
     * Connects to a discovered wristband and allows 15 seconds for service discovery.
     * @param id The identifier of the selected wristband.
     */
    func connect(to id: UUID) {
        guard !hasConnection, central?.state == .poweredOn,
              let peripheral = peripherals[id] else { return }
        stopScan()
        selected = peripheral
        peripheral.delegate = self
        hasConnection = true
        commandStatus = nil
        status = "Connecting to PathPulse-Left…"
        central?.connect(peripheral)
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            self?.disconnect(message: "Connection timed out. Scan and try again.")
        }
    }

    /**
     * Cancels a connection and clears command access; firmware stops on disconnect.
     * @param message The connection status to display.
     */
    func disconnect(message: String = "Disconnected.") {
        timeout?.cancel()
        if let selected { central?.cancelPeripheralConnection(selected) }
        selected?.delegate = nil
        selected = nil
        commandCharacteristic = nil
        isReady = false
        hasConnection = false
        commandStatus = nil
        status = message
    }

    /**
     * Writes a single binary manual-test or stop command with a GATT response.
     * A response confirms the write, not motor playback. No commands are replayed.
     * Command 6 is for manual testing only, not automatic navigation guidance.
     * @param command A protocol command from 0 (stop) through 8 (obstacle warning).
     */
    func send(_ command: UInt8) {
        guard command <= 8, isReady,
              let selected, selected.state == .connected,
              let commandCharacteristic else { return }
        commandStatus = command == 0 ? "Sending stop…" : "Sending test vibration…"
        selected.writeValue(Data([command]), for: commandCharacteristic, type: .withResponse)
    }

    /**
     * Reports Bluetooth availability and resumes an explicitly requested scan.
     * @param central The manager delivering state changes on the main queue.
     */
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if scanRequested { scan() } else { status = "Bluetooth ready. Tap Scan." }
            return
        }
        timeout?.cancel()
        isScanning = false
        devices = []
        peripherals = [:]
        selected?.delegate = nil
        selected = nil
        commandCharacteristic = nil
        isReady = false
        hasConnection = false
        commandStatus = nil
        switch central.state {
        case .poweredOff: status = "Turn on Bluetooth to connect your wristband."
        case .unauthorized:
            scanRequested = false
            status = "Allow Bluetooth access for PathPulse in Settings."
        case .unsupported:
            scanRequested = false
            status = "Bluetooth is unavailable on this device. Use a physical iPhone."
        case .resetting: status = "Bluetooth is restarting…"
        default: status = "Waiting for Bluetooth…"
        }
    }

    /**
     * Lists matching left wristbands once per identifier.
     * @param central The scanning manager.
     * @param peripheral The discovered wristband.
     * @param advertisementData Advertised service and local-name data.
     * @param RSSI Received signal strength in dBm.
     */
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard isScanning else { return }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        guard name == "PathPulse-Left", peripherals[peripheral.identifier] == nil else { return }
        peripherals[peripheral.identifier] = peripheral
        devices.append(Device(id: peripheral.identifier, name: "PathPulse-Left"))
    }

    /**
     * Discovers the haptic service after connecting.
     * @param central The connected manager.
     * @param peripheral The connected wristband.
     */
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === selected else { return }
        status = "Checking wristband service…"
        peripheral.discoverServices([serviceID])
    }

    /**
     * Clears a failed connection and reports the error.
     * @param central The manager reporting failure.
     * @param peripheral The wristband that failed to connect.
     * @param error The connection error, if supplied.
     */
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        guard peripheral === selected else { return }
        disconnect(message: error?.localizedDescription ?? "Connection failed. Try again.")
    }

    /**
     * Clears command access when the wristband disconnects.
     * @param central The manager reporting disconnection.
     * @param peripheral The disconnected wristband.
     * @param error The disconnection error, if supplied.
     */
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        guard peripheral === selected else { return }
        disconnect(message: error?.localizedDescription ?? "Wristband disconnected. Scan to reconnect.")
    }

    /**
     * Finds the command characteristic in the haptic service.
     * @param peripheral The wristband supplying services.
     * @param error The service discovery error, if supplied.
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === selected else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceID }) else {
            disconnect(message: "Could not find the wristband service. Try reconnecting.")
            return
        }
        peripheral.discoverCharacteristics([commandID], for: service)
    }

    /**
     * Enables controls only after finding a characteristic supporting write responses.
     * @param peripheral The wristband supplying characteristics.
     * @param service The discovered haptic service.
     * @param error The characteristic discovery error, if supplied.
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard peripheral === selected else { return }
        guard error == nil, let characteristic = service.characteristics?.first(where: {
            $0.uuid == commandID && $0.properties.contains(.write)
        }) else {
            disconnect(message: "Wristband command service is unavailable. Try reconnecting.")
            return
        }
        timeout?.cancel()
        commandCharacteristic = characteristic
        isReady = true
        status = "Connected to PathPulse-Left."
    }

    /**
     * Reports transport acknowledgement without claiming the motor played a pattern.
     * @param peripheral The wristband acknowledging the write.
     * @param characteristic The written command characteristic.
     * @param error The write error, if supplied.
     */
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard peripheral === selected, characteristic.uuid == commandID else { return }
        commandStatus = error.map { "Command failed: \($0.localizedDescription)" }
            ?? "Command delivered."
    }
}
