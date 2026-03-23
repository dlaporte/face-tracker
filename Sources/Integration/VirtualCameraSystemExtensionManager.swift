import Foundation
import SystemExtensions

@MainActor
final class VirtualCameraSystemExtensionManager: NSObject, ObservableObject {

    @Published private(set) var statusMessage = "Virtual camera not installed."
    @Published private(set) var extensionState = "Unknown"
    @Published private(set) var needsUserApproval = false
    @Published private(set) var isBusy = false

    let extensionBundleIdentifier = "com.facetracker.app.virtualcamera"

    func refreshStatus() {
        guard isRunningFromApplicationsFolder else {
            extensionState = "Unavailable"
            statusMessage = "Move FaceTracker.app into /Applications and launch it from there before installing the virtual camera."
            return
        }

        guard #available(macOS 12.0, *) else {
            extensionState = "Unsupported"
            statusMessage = "Virtual cameras require macOS 12.3 or later."
            return
        }

        let request = OSSystemExtensionRequest.propertiesRequest(
            forExtensionWithIdentifier: extensionBundleIdentifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func installExtension() {
        guard isRunningFromApplicationsFolder else {
            extensionState = "Unavailable"
            statusMessage = "Virtual camera install is disabled while FaceTracker is running from a build folder. Copy FaceTracker.app into /Applications, open that copy, then try again."
            return
        }
        submitActivationRequest()
    }

    func uninstallExtension() {
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: extensionBundleIdentifier,
            queue: .main
        )
        request.delegate = self
        isBusy = true
        statusMessage = "Requesting virtual camera removal..."
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    private func submitActivationRequest() {
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionBundleIdentifier,
            queue: .main
        )
        request.delegate = self
        isBusy = true
        needsUserApproval = false
        statusMessage = "Requesting virtual camera installation..."
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    private var isRunningFromApplicationsFolder: Bool {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let path = bundleURL.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    private func updateState(from properties: OSSystemExtensionProperties?) {
        guard let properties else {
            extensionState = "Not installed"
            statusMessage = "Build the app, move it into /Applications, then install the virtual camera."
            return
        }

        if properties.isAwaitingUserApproval {
            extensionState = "Awaiting approval"
            needsUserApproval = true
            statusMessage = "Approve the system extension in Privacy & Security to finish installing the virtual camera."
        } else if properties.isEnabled {
            extensionState = "Enabled"
            needsUserApproval = false
            statusMessage = "Virtual camera is installed. In this first pass it publishes a test pattern device named FaceTracker Virtual Camera."
        } else if properties.isUninstalling {
            extensionState = "Uninstalling"
            statusMessage = "Virtual camera uninstall is pending."
        } else {
            extensionState = "Installed"
            statusMessage = "Virtual camera is present but not active yet."
        }
    }
}

@MainActor
extension VirtualCameraSystemExtensionManager: OSSystemExtensionRequestDelegate {

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        needsUserApproval = true
        isBusy = false
        extensionState = "Awaiting approval"
        statusMessage = "Approve the FaceTracker virtual camera in System Settings > Privacy & Security."
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        isBusy = false
        needsUserApproval = false

        switch result {
        case .completed:
            statusMessage = "System extension request completed."
        case .willCompleteAfterReboot:
            statusMessage = "System extension request will complete after reboot."
        @unknown default:
            statusMessage = "System extension request finished with an unknown result."
        }

        refreshStatus()
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        isBusy = false
        statusMessage = friendlyMessage(for: error)
    }

    func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        updateState(from: properties.first)
    }

    private func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == OSSystemExtensionErrorDomain else {
            return nsError.localizedDescription
        }

        switch nsError.code {
        case OSSystemExtensionError.unknown.rawValue:
            return "The virtual camera request failed. Most often this means FaceTracker is not running from /Applications or the system extension is not accepted by macOS yet."
        case OSSystemExtensionError.missingEntitlement.rawValue:
            return "FaceTracker is missing a required system-extension entitlement."
        case OSSystemExtensionError.unsupportedParentBundleLocation.rawValue:
            return "Move FaceTracker.app into /Applications and launch it from there before installing the virtual camera."
        case OSSystemExtensionError.extensionNotFound.rawValue:
            return "The embedded virtual camera extension could not be found in the app bundle."
        case OSSystemExtensionError.extensionMissingIdentifier.rawValue:
            return "The virtual camera extension is missing its bundle identifier."
        case OSSystemExtensionError.duplicateExtensionIdentifer.rawValue:
            return "macOS found multiple virtual camera extensions with the same identifier."
        case OSSystemExtensionError.unknownExtensionCategory.rawValue:
            return "macOS did not recognize the FaceTracker system extension type."
        case OSSystemExtensionError.codeSignatureInvalid.rawValue:
            return "The virtual camera extension signature is invalid for installation."
        case OSSystemExtensionError.validationFailed.rawValue:
            return "macOS rejected the virtual camera extension during validation."
        case OSSystemExtensionError.forbiddenBySystemPolicy.rawValue:
            return "macOS blocked the virtual camera by system policy. Check Privacy & Security for an approval prompt."
        case OSSystemExtensionError.requestCanceled.rawValue:
            return "The virtual camera install request was canceled."
        case OSSystemExtensionError.requestSuperseded.rawValue:
            return "A newer virtual camera install request replaced the previous one."
        case OSSystemExtensionError.authorizationRequired.rawValue:
            return "Admin authorization is required to install the virtual camera."
        default:
            return nsError.localizedDescription
        }
    }
}
