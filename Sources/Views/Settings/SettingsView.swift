import SwiftUI

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings: AppSettings
    @ObservedObject var cameraManager: CameraSessionManager
    @ObservedObject var controller: ActiveCameraController
    @ObservedObject var zoomIntegration: ZoomIntegrationController
    @ObservedObject var virtualCameraManager: VirtualCameraSystemExtensionManager

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                CamerasTab(settings: settings, cameraManager: cameraManager)
                    .tabItem { Label("Cameras", systemImage: "camera") }

                AppearanceTab(settings: settings)
                    .tabItem { Label("Appearance", systemImage: "paintbrush") }

                DetectionTab(settings: settings)
                    .tabItem { Label("Detection", systemImage: "eye") }

                ZoomTab(
                    settings: settings,
                    cameraManager: cameraManager,
                    controller: controller,
                    zoomIntegration: zoomIntegration
                )
                .tabItem { Label("Zoom", systemImage: "video.badge.checkmark") }

                VirtualCameraTab(manager: virtualCameraManager)
                    .tabItem { Label("Virtual Cam", systemImage: "camera.aperture") }
            }

            Divider()

            HStack {
                Button("Close") {
                    dismiss()
                }
                Spacer()
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
                .padding(12)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
