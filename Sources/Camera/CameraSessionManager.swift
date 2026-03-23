import AVFoundation
import Combine

class CameraSessionManager: ObservableObject {

    @Published var cameraViewModels: [CameraViewModel] = []
    @Published var allDiscoveredDevices: [(id: String, name: String)] = []
    @Published var isDiscovering = false
    @Published var hasCompletedDiscovery = false
    var sessions: [String: CameraSession] = [:]

    private let settings: AppSettings
    private let controller: ActiveCameraController
    private let discoveryQueue = DispatchQueue(label: "facetracker.discovery", qos: .userInitiated)
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    init(settings: AppSettings, controller: ActiveCameraController) {
        self.settings = settings
        self.controller = controller
        observeHotPlug()
    }

    deinit {
        [connectObserver, disconnectObserver].compactMap { $0 }
            .forEach { NotificationCenter.default.removeObserver($0) }
    }

    func enumerateAndSync() {
        DispatchQueue.main.async { [weak self] in
            self?.isDiscovering = true
        }
        discoveryQueue.async { [weak self] in
            guard let self = self else { return }
            let discovered = self.discoverDevices()
            DispatchQueue.main.async { [weak self] in
                self?.applyDiscoveredDevices(discovered)
            }
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

    func setEnabledForAllDiscoveredCameras() {
        settings.enabledCameraIDs = allDiscoveredDevices.map(\.id)
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

    private func applyDiscoveredDevices(_ discovered: [AVCaptureDevice]) {
        isDiscovering = false
        hasCompletedDiscovery = true
        allDiscoveredDevices = discovered.map { (id: $0.uniqueID, name: $0.localizedName) }
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
            } else if let session = sessions.removeValue(forKey: id) {
                session.stop()
            }
        }

        // Default camera: if unset or disconnected, use first available
        if settings.defaultCameraID.isEmpty || !newViewModels.contains(where: { $0.id == settings.defaultCameraID }) {
            settings.defaultCameraID = newViewModels.first?.id ?? ""
        }

        cameraViewModels = newViewModels
        controller.update(cameras: newViewModels)
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
