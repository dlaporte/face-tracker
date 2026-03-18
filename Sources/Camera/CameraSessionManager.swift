import AVFoundation
import Combine

class CameraSessionManager: ObservableObject {

    @Published var cameraViewModels: [CameraViewModel] = []
    var sessions: [String: CameraSession] = [:]

    private let settings: AppSettings
    private let controller: ActiveCameraController
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    init(settings: AppSettings, controller: ActiveCameraController) {
        self.settings = settings
        self.controller = controller
        observeHotPlug()
        enumerateAndSync()
    }

    deinit {
        [connectObserver, disconnectObserver].compactMap { $0 }
            .forEach { NotificationCenter.default.removeObserver($0) }
    }

    func enumerateAndSync() {
        let discovered = discoverDevices()
        let enabled = settings.enabledCameraIDs

        // If enabledCameraIDs is empty (first launch), enable all discovered cameras
        if enabled.isEmpty && !discovered.isEmpty {
            settings.enabledCameraIDs = discovered.map { $0.uniqueID }
        }

        let currentEnabled = settings.enabledCameraIDs

        // Remove stale sessions
        for (id, session) in sessions where !discovered.contains(where: { $0.uniqueID == id }) {
            session.stop()
            sessions.removeValue(forKey: id)
        }

        // Build or keep sessions for enabled discovered cameras
        var newViewModels: [CameraViewModel] = []
        for device in discovered {
            let id = device.uniqueID
            let vm = sessions[id]?.viewModel
                ?? CameraViewModel(deviceID: id, displayName: device.localizedName, settings: settings)

            if currentEnabled.contains(id) {
                if sessions[id] == nil {
                    let session = CameraSession(device: device, viewModel: vm, settings: settings)
                    sessions[id] = session
                    session.start()
                }
                newViewModels.append(vm)
            } else {
                if let session = sessions.removeValue(forKey: id) {
                    session.stop()
                }
            }
        }

        // Default camera: if unset or disconnected, use first available
        if settings.defaultCameraID.isEmpty || !newViewModels.contains(where: { $0.id == settings.defaultCameraID }) {
            settings.defaultCameraID = newViewModels.first?.id ?? ""
        }

        DispatchQueue.main.async {
            self.cameraViewModels = newViewModels
            self.controller.update(cameras: newViewModels)
        }
    }

    func setEnabled(_ enabled: Bool, for deviceID: String) {
        if enabled {
            var ids = settings.enabledCameraIDs
            if !ids.contains(deviceID) { ids.append(deviceID) }
            settings.enabledCameraIDs = ids
        } else {
            settings.enabledCameraIDs = settings.enabledCameraIDs.filter { $0 != deviceID }
        }
        enumerateAndSync()
    }

    private func discoverDevices() -> [AVCaptureDevice] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14, *) {
            types.append(.external)
        }
        let discovered = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        ).devices

        if #unavailable(macOS 14) {
            let all = AVCaptureDevice.devices(for: .video)
            let extra = all.filter { d in !discovered.contains(where: { $0.uniqueID == d.uniqueID }) }
            return discovered + extra
        }
        return discovered
    }

    private func observeHotPlug() {
        connectObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.enumerateAndSync() }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.enumerateAndSync() }
    }
}
