import SwiftUI

struct SettingsView: View {

    @ObservedObject var settings: AppSettings
    @ObservedObject var cameraManager: CameraSessionManager

    var body: some View {
        TabView {
            CamerasTab(settings: settings, cameraManager: cameraManager)
                .tabItem { Label("Cameras", systemImage: "camera") }

            AppearanceTab(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            DetectionTab(settings: settings)
                .tabItem { Label("Detection", systemImage: "eye") }
        }
        .frame(minWidth: 500, minHeight: 350)
    }
}
