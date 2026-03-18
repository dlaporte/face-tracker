import SwiftUI
import AVFoundation

@main
struct FaceTrackerApp: App {

    @StateObject private var settings = AppSettings.shared
    @StateObject private var controller: ActiveCameraController
    @StateObject private var cameraManager: CameraSessionManager
    @State private var cameraAuthorized: Bool? = nil

    init() {
        let s = AppSettings.shared
        let c = ActiveCameraController(settings: s)
        let m = CameraSessionManager(settings: s, controller: c)
        _controller = StateObject(wrappedValue: c)
        _cameraManager = StateObject(wrappedValue: m)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch cameraAuthorized {
                case .none:
                    ProgressView("Requesting camera access\u{2026}")
                        .frame(width: 300, height: 200)
                case .some(false):
                    PermissionDeniedView()
                case .some(true):
                    ContentView(
                        cameraManager: cameraManager,
                        controller: controller,
                        settings: settings
                    )
                }
            }
            .onAppear { requestCameraAccess() }
        }
        .defaultSize(width: 960, height: 540)

        Settings {
            SettingsView(settings: settings, cameraManager: cameraManager)
        }
    }

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorized = true
            cameraManager.enumerateAndSync()
        case .denied, .restricted:
            cameraAuthorized = false
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraAuthorized = granted
                    if granted { cameraManager.enumerateAndSync() }
                }
            }
        @unknown default:
            cameraAuthorized = false
        }
    }
}
