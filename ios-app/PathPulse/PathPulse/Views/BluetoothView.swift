import SwiftUI

struct BluetoothView: View {
    let bluetooth: BluetoothService
    @State private var showsTestingSuite = false

    var body: some View {
        List {
            Section("Discovery") {
                Text(bluetooth.status)
                if bluetooth.isScanning {
                    Button("Stop scanning") { bluetooth.stopScan() }
                } else {
                    Button("Scan for wristbands") { bluetooth.scan() }
                        .disabled(bluetooth.left.hasConnection && bluetooth.right.hasConnection)
                }
            }
            ForEach(BluetoothService.Wrist.allCases) { wrist in
                let connection = bluetooth.connection(for: wrist)
                Section("\(wrist.rawValue) wristband") {
                    Text(connection.status)
                    if connection.hasConnection {
                        Button("Disconnect", role: .destructive) { bluetooth.disconnect(wrist) }
                    } else {
                        ForEach(bluetooth.devices.filter { $0.wrist == wrist }) { device in
                            Button("Connect \(device.name)") {
                                bluetooth.connect(to: device.id, wrist: wrist)
                            }
                        }
                    }
                    Button("Test \(wrist.rawValue.lowercased()) vibration") { bluetooth.send(1, to: wrist) }
                        .disabled(!connection.isReady)
                    Button("Stop \(wrist.rawValue.lowercased()) vibration") { bluetooth.send(0, to: wrist) }
                        .disabled(!connection.isReady)
                    if let message = connection.commandStatus { Text(message) }
                }
            }

        }
        .scrollContentBackground(.hidden)
        .background(PathPulseBrand.background)
        .tint(PathPulseBrand.accent)
        .navigationTitle("Bluetooth")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, alignment: .leading) {
            Button {
                showsTestingSuite = true
            } label: {
                Image(systemName: "testtube.2")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(PathPulseBrand.accent, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            }
            .accessibilityLabel("Open vibration testing suite")
            .padding(.leading, 20)
            .padding(.vertical, 12)
        }
        .sheet(isPresented: $showsTestingSuite) {
            VibrationTestingView(bluetooth: bluetooth)
        }
        .onDisappear { bluetooth.stopScan() }
    }
}
