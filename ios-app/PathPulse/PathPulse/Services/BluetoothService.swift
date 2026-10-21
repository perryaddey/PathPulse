import CoreBluetooth
import Observation

@MainActor
@Observable
final class BluetoothService: NSObject, @preconcurrency CBCentralManagerDelegate,
    @preconcurrency CBPeripheralDelegate {
    enum Wrist: String, CaseIterable, Identifiable {
        case left = "Left", right = "Right"
        var id: String { rawValue }
        var deviceName: String { "PathPulse-\(rawValue)" }
    }

    struct Device: Identifiable {
        let id: UUID
        let wrist: Wrist
        var name: String { wrist.deviceName }
    }

    @Observable
    final class Connection {
        var status = "Scan to find this wristband."
        var commandStatus: String?
        var isReady = false
        var hasConnection: Bool { peripheral != nil }
        fileprivate var peripheral: CBPeripheral?
        fileprivate var characteristic: CBCharacteristic?
        fileprivate var timeout: Task<Void, Never>?
    }

    let left = Connection()
    let right = Connection()
    private(set) var devices: [Device] = []
    private(set) var status = "Tap Scan to find your wristbands."
    private(set) var isScanning = false

    private let serviceID = CBUUID(string: "7ca10001-8e6b-4b2d-a9f0-6c3d52e18470")
    private let commandID = CBUUID(string: "7ca10002-8e6b-4b2d-a9f0-6c3d52e18470")
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var scanRequested = false
    private var scanTimeout: Task<Void, Never>?

    /**
     * Returns the independent state for a wrist.
     * @param wrist The wrist whose connection is requested.
     * @return Observable connection and command state.
     */
    func connection(for wrist: Wrist) -> Connection {
        wrist == .left ? left : right
    }

    /**
     * Finds the wrist owning a callback, ignoring peripherals no longer selected.
     * @param peripheral The peripheral delivering a callback.
     * @return Its assigned wrist, or nil for an obsolete callback.
     */
    private func wrist(for peripheral: CBPeripheral) -> Wrist? {
        Wrist.allCases.first { connection(for: $0).peripheral === peripheral }
    }

    /** Starts a bounded scan, requesting Bluetooth access on first use. */
    func scan() {
        guard !left.hasConnection || !right.hasConnection else { return }
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
        isScanning = true
        status = "Searching for PathPulse wristbands…"
        central.scanForPeripherals(withServices: [serviceID])
        scanTimeout?.cancel()
        scanTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            self?.stopScan()
        }
    }

    /** Stops shared discovery without affecting either connection. */
    func stopScan() {
        scanRequested = false
        guard isScanning else { return }
        central?.stopScan()
        isScanning = false
        scanTimeout?.cancel()
        status = devices.isEmpty ? "No wristbands found. Check their power and scan again."
            : "Select a wristband to connect."
    }

    /**
     * Connects one wrist and allows 15 seconds for connection and service discovery.
     * @param id The discovered peripheral identifier.
     * @param wrist The wrist matching the advertised device name.
     */
    func connect(to id: UUID, wrist: Wrist) {
        let connection = connection(for: wrist)
        guard !connection.hasConnection, central?.state == .poweredOn,
              devices.contains(where: { $0.id == id && $0.wrist == wrist }),
              let peripheral = peripherals[id], peripheral.state == .disconnected,
              self.wrist(for: peripheral) == nil else { return }
        connection.peripheral = peripheral
        peripheral.delegate = self
        connection.commandStatus = nil
        connection.status = "Connecting to \(wrist.deviceName)…"
        central?.connect(peripheral)
        connection.timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            self?.disconnect(wrist, message: "Connection timed out. Scan and try again.")
        }
        if left.hasConnection && right.hasConnection { stopScan() }
    }

    /**
     * Cancels only the selected wrist's connection; firmware stops on disconnect.
     * @param wrist The wrist to disconnect.
     * @param message The status to display for that wrist.
     */
    func disconnect(_ wrist: Wrist, message: String = "Disconnected.") {
        let connection = connection(for: wrist)
        if let peripheral = connection.peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        clear(wrist, message: message)
    }

    /**
     * Clears one wrist's local state without changing the other connection or scan.
     * @param wrist The wrist whose state is cleared.
     * @param message The status to display.
     */
    private func clear(_ wrist: Wrist, message: String) {
        let connection = connection(for: wrist)
        connection.timeout?.cancel()
        connection.timeout = nil
        connection.peripheral?.delegate = nil
        connection.peripheral = nil
        connection.characteristic = nil
        connection.isReady = false
        connection.commandStatus = nil
        connection.status = message
    }

    /**
     * Sends one binary manual-test command to one wrist, without replay or retries.
     * A GATT response confirms receipt, not motor playback. Command 6 is manual only.
     * @param command The protocol command from 0 through 8.
     * @param wrist The recipient wrist.
     */
    func send(_ command: UInt8, to wrist: Wrist) {
        let connection = connection(for: wrist)
        guard command <= 8, connection.isReady,
              let peripheral = connection.peripheral, peripheral.state == .connected,
              let characteristic = connection.characteristic else { return }
        connection.commandStatus = command == 0 ? "Sending stop…" : "Sending test vibration…"
        peripheral.writeValue(Data([command]), for: characteristic, type: .withResponse)
    }

    /** Stops every ready wristband, including when only one wrist is connected. */
    func stopAll() {
        for wrist in Wrist.allCases { send(0, to: wrist) }
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
        scanTimeout?.cancel()
        isScanning = false
        devices = []
        peripherals = [:]
        switch central.state {
        case .poweredOff: status = "Turn on Bluetooth to connect your wristbands."
        case .unauthorized:
            scanRequested = false
            status = "Allow Bluetooth access for PathPulse in Settings."
        case .unsupported:
            scanRequested = false
            status = "Bluetooth is unavailable on this device. Use a physical iPhone."
        case .resetting: status = "Bluetooth is restarting…"
        default: status = "Waiting for Bluetooth…"
        }
        for wrist in Wrist.allCases { clear(wrist, message: status) }
    }

    /**
     * Lists exact left/right advertised names once per identifier.
     * @param central The scanning manager.
     * @param peripheral The discovered wristband.
     * @param advertisementData Advertised service and local-name data.
     * @param RSSI Received signal strength in dBm.
     */
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard isScanning else { return }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        guard let wrist = Wrist.allCases.first(where: { $0.deviceName == name }),
              peripherals[peripheral.identifier] == nil else { return }
        peripherals[peripheral.identifier] = peripheral
        devices.append(Device(id: peripheral.identifier, wrist: wrist))
    }

    /**
     * Discovers the haptic service after connecting.
     * @param central The connected manager.
     * @param peripheral The connected wristband.
     */
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let wrist = wrist(for: peripheral) else { return }
        connection(for: wrist).status = "Checking wristband service…"
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
        guard let wrist = wrist(for: peripheral) else { return }
        disconnect(wrist, message: error?.localizedDescription ?? "Connection failed. Try again.")
    }

    /**
     * Clears command access when the wristband disconnects.
     * @param central The manager reporting disconnection.
     * @param peripheral The disconnected wristband.
     * @param error The disconnection error, if supplied.
     */
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        guard let wrist = wrist(for: peripheral) else { return }
        disconnect(wrist, message: error?.localizedDescription ?? "Wristband disconnected. Scan to reconnect.")
    }

    /**
     * Finds the command characteristic in the haptic service.
     * @param peripheral The wristband supplying services.
     * @param error The service discovery error, if supplied.
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let wrist = wrist(for: peripheral) else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceID }) else {
            disconnect(wrist, message: "Could not find the wristband service. Try reconnecting.")
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
        guard let wrist = wrist(for: peripheral) else { return }
        guard error == nil, let characteristic = service.characteristics?.first(where: {
            $0.uuid == commandID && $0.properties.contains(.write)
        }) else {
            disconnect(wrist, message: "Wristband command service is unavailable. Try reconnecting.")
            return
        }
        let connection = connection(for: wrist)
        connection.timeout?.cancel()
        connection.timeout = nil
        connection.characteristic = characteristic
        connection.isReady = true
        connection.status = "Connected to \(wrist.deviceName)."
    }

    /**
     * Reports transport acknowledgement without claiming the motor played a pattern.
     * @param peripheral The wristband acknowledging the write.
     * @param characteristic The written command characteristic.
     * @param error The write error, if supplied.
     */
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let wrist = wrist(for: peripheral), characteristic === connection(for: wrist).characteristic else { return }
        connection(for: wrist).commandStatus = error.map { "Command failed: \($0.localizedDescription)" }
            ?? "Command delivered."
    }
}
