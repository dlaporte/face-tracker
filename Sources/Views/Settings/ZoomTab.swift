import SwiftUI

struct ZoomTab: View {

    @ObservedObject var settings: AppSettings
    @ObservedObject var cameraManager: CameraSessionManager
    @ObservedObject var controller: ActiveCameraController
    @ObservedObject var zoomIntegration: ZoomIntegrationController

    var body: some View {
        Form {
            Section("Zoom Camera Sync") {
                Toggle("Enable manual Zoom camera sync", isOn: $settings.zoomIntegrationEnabled)

                Text("This sheet keeps Zoom integration manual-only for stability. Use Refresh Status and Sync Zoom Now when you want to interact with Zoom.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Status") {
                statusRow(label: "Zoom installed", value: zoomIntegration.isZoomInstalled ? "Yes" : "No")
                statusRow(label: "Zoom running", value: zoomIntegration.isZoomRunning ? "Yes" : "No")
                statusRow(label: "Accessibility access", value: zoomIntegration.hasAccessibilityAccess ? "Granted" : "Needed")
                statusRow(label: "Active camera", value: activeCameraName)
                statusRow(label: "Last synced", value: zoomIntegration.lastSyncedCameraName ?? "Not yet synced")

                Text(zoomIntegration.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Actions") {
                Button("Refresh Zoom Status") {
                    zoomIntegration.refreshEnvironmentStatus()
                }

                Button("Sync Zoom Now") {
                    zoomIntegration.syncIfNeeded(
                        activeCameraID: controller.activeCameraID,
                        cameras: cameraManager.cameraViewModels,
                        force: true
                    )
                }
                .disabled(controller.activeCameraID == nil || !settings.zoomIntegrationEnabled)

                Button("Open Zoom") {
                    zoomIntegration.openZoom()
                }
                .disabled(!zoomIntegration.isZoomInstalled)

                Button("Open Accessibility Settings") {
                    zoomIntegration.openAccessibilitySettings()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var activeCameraName: String {
        guard let activeCameraID = controller.activeCameraID,
              let camera = cameraManager.cameraViewModels.first(where: { $0.id == activeCameraID }) else {
            return "None"
        }
        return camera.displayName
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
