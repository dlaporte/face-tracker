import SwiftUI

struct CamerasTab: View {

    @ObservedObject var settings: AppSettings
    @ObservedObject var cameraManager: CameraSessionManager

    var body: some View {
        Form {
            Section("Connected Cameras") {
                if cameraManager.allDiscoveredDevices.isEmpty {
                    Text("No cameras detected").foregroundColor(.secondary)
                } else {
                    ForEach(cameraManager.allDiscoveredDevices, id: \.id) { device in
                        HStack {
                            Toggle(isOn: enabledBinding(for: device.id)) {
                                Text(device.name)
                            }
                            Spacer()
                            if device.id == settings.defaultCameraID {
                                Text("★ Default")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else {
                                Button("Set Default") {
                                    settings.defaultCameraID = device.id
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                        }
                    }
                }
            }

            Section("Fallback Behavior") {
                HStack {
                    Text("Delay before returning to default")
                    Slider(value: $settings.fallbackDelay, in: 0...10, step: 0.5)
                    Text(String(format: "%.1fs", settings.fallbackDelay))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func enabledBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { settings.enabledCameraIDs.contains(id) },
            set: { enabled in cameraManager.setEnabled(enabled, for: id) }
        )
    }
}
