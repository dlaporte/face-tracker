import SwiftUI
import Combine

class CameraViewModel: ObservableObject, Identifiable {

    let id: String        // AVCaptureDevice.uniqueID
    let displayName: String
    private let settings: AppSettings

    @Published var gazeState: GazeState = .noFace
    @Published var isActive: Bool = false
    @Published var isErrored: Bool = false

    init(deviceID: String, displayName: String, settings: AppSettings) {
        self.id = deviceID
        self.displayName = displayName
        self.settings = settings
    }

    var overlayColor: Color? {
        guard !isErrored else { return nil }
        switch gazeState {
        case .lookingAtCamera: return settings.lookingColor.opacity(settings.overlayOpacity)
        case .lookingAway:     return settings.awayColor.opacity(settings.overlayOpacity)
        case .noFace:          return nil
        }
    }

    var badgeName: String {
        if isErrored { return "ERROR" }
        switch gazeState {
        case .lookingAtCamera: return "LOOKING"
        case .lookingAway:     return "AWAY"
        case .noFace:          return "NO FACE"
        }
    }
}
