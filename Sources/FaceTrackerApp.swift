import SwiftUI
import AVFoundation

@main
struct FaceTrackerApp: App {

    @StateObject private var settings = AppSettings.shared
    @StateObject private var controller: ActiveCameraController
    @StateObject private var cameraManager: CameraSessionManager
    @StateObject private var zoomIntegration: ZoomIntegrationController
    @StateObject private var virtualCameraManager: VirtualCameraSystemExtensionManager
    @State private var cameraAuthorized: Bool? = nil

    init() {
        let s = AppSettings.shared
        let c = ActiveCameraController(settings: s)
        let m = CameraSessionManager(settings: s, controller: c)
        let z = ZoomIntegrationController(settings: s)
        let v = VirtualCameraSystemExtensionManager()
        _controller = StateObject(wrappedValue: c)
        _cameraManager = StateObject(wrappedValue: m)
        _zoomIntegration = StateObject(wrappedValue: z)
        _virtualCameraManager = StateObject(wrappedValue: v)
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
                        settings: settings,
                        zoomIntegration: zoomIntegration,
                        virtualCameraManager: virtualCameraManager
                    )
                }
            }
            .onAppear { requestCameraAccess() }
        }
        .defaultSize(width: 960, height: 540)
    }

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorized = true
        case .denied, .restricted:
            cameraAuthorized = false
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraAuthorized = granted
                }
            }
        @unknown default:
            cameraAuthorized = false
        }
    }
}
