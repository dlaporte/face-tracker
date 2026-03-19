import SwiftUI

struct VirtualCameraTab: View {

    @ObservedObject var manager: VirtualCameraSystemExtensionManager

    var body: some View {
        Form {
            Section("Virtual Camera") {
                Text("FaceTracker can install a CoreMediaIO camera extension so Zoom and other apps can use one stable virtual camera device.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                statusRow(label: "State", value: manager.extensionState)
                statusRow(label: "Bundle ID", value: manager.extensionBundleIdentifier)

                if manager.needsUserApproval {
                    Text("Approval is required in System Settings > Privacy & Security before macOS will enable the virtual camera.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(manager.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Actions") {
                Button("Install Virtual Camera") {
                    manager.installExtension()
                }
                .disabled(manager.isBusy)

                Button("Refresh Status") {
                    manager.refreshStatus()
                }
                .disabled(manager.isBusy)

                Button("Uninstall Virtual Camera") {
                    manager.uninstallExtension()
                }
                .disabled(manager.isBusy)
            }

            Section("Notes") {
                Text("This first pass publishes a test-pattern camera named FaceTracker Virtual Camera. The next step will be feeding the selected physical camera into the extension.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("For development, the app should be run from /Applications before installing the system extension.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}
