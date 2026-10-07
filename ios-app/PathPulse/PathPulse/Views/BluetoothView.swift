import SwiftUI

struct BluetoothView: View {
    let bluetooth: BluetoothService
    @State private var showsTestingSuite = false

    var body: some View {
        List {
            Section("Left wristband") {
                Text(bluetooth.status)
                if bluetooth.hasConnection {
                    Button("Disconnect", role: .destructive) { bluetooth.disconnect() }
                } else if bluetooth.isScanning {
                    Button("Stop scanning") { bluetooth.stopScan() }
                } else {
                    Button("Scan for wristband") { bluetooth.scan() }
                }
            }
            if !bluetooth.hasConnection && !bluetooth.devices.isEmpty {
                Section("Available wristbands") {
                    ForEach(bluetooth.devices) { device in
                        Button {
                            bluetooth.connect(to: device.id)
                        } label: {
                            Label("Connect \(device.name)", systemImage: "link")
                        }
                    }
                }
            }
            Section {
                Button("Test vibration") { bluetooth.send(1) }
                    .disabled(!bluetooth.isReady)
                Button("Stop vibration") { bluetooth.send(0) }
                    .disabled(!bluetooth.isReady)
                if let message = bluetooth.commandStatus { Text(message) }
            } header: {
                Text("Vibration controls")
            } footer: {
                Text("Test plays two short pulses on the left wristband.")
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
