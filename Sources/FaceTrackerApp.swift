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
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About FaceTracker") {
                    showAboutPanel()
                }
            }
        }

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

    private func showAboutPanel() {
        let cameraCount = discoverCameraCount()
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        let creditsString = """
        Monitors multiple camera feeds and detects which camera you're looking at \
        using face orientation analysis via the Vision framework.

        Detection: Vision (face orientation)
        Frameworks: AVFoundation, Vision, SwiftUI
        Cameras detected: \(cameraCount)
        macOS: \(osString)

        Built as a proof of concept for automatic camera switching.
        """

        let credits = NSAttributedString(
            string: creditsString,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "FaceTracker",
            .credits: credits,
        ])
    }

    private func discoverCameraCount() -> Int {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14, *) { types.append(.external) }
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified
        ).devices.count
    }
}
