import AppKit
import ApplicationServices
import SwiftUI

protocol AppleScriptRunning {
    func run(_ source: String) throws
}

struct NSAppleScriptRunner: AppleScriptRunning {
    func run(_ source: String) throws {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw ZoomIntegrationError.invalidScript
        }

        script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String
                ?? "Zoom didn't accept the camera switch request."
            throw ZoomIntegrationError.scriptExecutionFailed(message)
        }
    }
}

enum ZoomIntegrationError: LocalizedError {
    case invalidScript
    case scriptExecutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidScript:
            return "FaceTracker couldn't build the Zoom automation script."
        case .scriptExecutionFailed(let message):
            return message
        }
    }
}

@MainActor
final class ZoomIntegrationController: ObservableObject {

    @Published private(set) var isZoomInstalled = false
    @Published private(set) var isZoomRunning = false
    @Published private(set) var hasAccessibilityAccess = false
    @Published private(set) var statusMessage = "Zoom sync is off."
    @Published private(set) var lastSyncedCameraName: String?

    private let settings: AppSettings
    private let scriptRunner: AppleScriptRunning
    private let workspace: NSWorkspace

    private let bundleIdentifier = "us.zoom.xos"
    private let processName = "zoom.us"
    private var lastAttemptedCameraID: String?

    init(
        settings: AppSettings,
        scriptRunner: AppleScriptRunning = NSAppleScriptRunner(),
        workspace: NSWorkspace = .shared
    ) {
        self.settings = settings
        self.scriptRunner = scriptRunner
        self.workspace = workspace
        refreshEnvironmentStatus()
    }

    func refreshEnvironmentStatus() {
        isZoomInstalled = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
        isZoomRunning = workspace.runningApplications.contains(where: { $0.bundleIdentifier == bundleIdentifier })
        hasAccessibilityAccess = AXIsProcessTrusted()

        guard settings.zoomIntegrationEnabled else {
            statusMessage = "Zoom sync is off."
            return
        }

        if !isZoomInstalled {
            statusMessage = "Install Zoom Workplace to enable camera sync."
        } else if !isZoomRunning {
            statusMessage = "Open Zoom and join a meeting to sync the active camera."
        } else if !hasAccessibilityAccess {
            statusMessage = "Allow Accessibility access so FaceTracker can control Zoom."
        } else if let lastSyncedCameraName {
            statusMessage = "Zoom is synced to \(lastSyncedCameraName)."
        } else {
            statusMessage = "Zoom is ready for camera sync."
        }
    }

    func syncIfNeeded(activeCameraID: String?, cameras: [CameraViewModel], force: Bool = false) {
        refreshEnvironmentStatus()

        guard settings.zoomIntegrationEnabled else { return }
        guard isZoomInstalled, isZoomRunning, hasAccessibilityAccess else { return }
        guard let activeCameraID,
              let camera = cameras.first(where: { $0.id == activeCameraID }) else {
            statusMessage = "Waiting for an active camera before syncing Zoom."
            return
        }

        if !force, lastAttemptedCameraID == activeCameraID {
            return
        }

        lastAttemptedCameraID = activeCameraID

        do {
            try scriptRunner.run(ZoomAppleScriptBuilder.cameraSelectionScript(
                bundleIdentifier: bundleIdentifier,
                processName: processName,
                cameraName: camera.displayName
            ))
            lastSyncedCameraName = camera.displayName
            statusMessage = "Zoom is synced to \(camera.displayName)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func openZoom() {
        if let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        workspace.open(url)
    }
}

enum ZoomAppleScriptBuilder {
    static func cameraSelectionScript(bundleIdentifier: String, processName: String, cameraName: String) -> String {
        let escapedBundleID = escape(bundleIdentifier)
        let escapedProcessName = escape(processName)
        let escapedCameraName = escape(cameraName)

        return """
        on clickCameraMenu(zoomProcess, rootMenuName, cameraName)
            if not (exists menu bar item rootMenuName of menu bar 1 of zoomProcess) then
                return false
            end if

            click menu bar item rootMenuName of menu bar 1 of zoomProcess
            delay 0.15

            try
                set videoMenu to menu 1 of menu bar item rootMenuName of menu bar 1 of zoomProcess
                if my clickCameraItem(videoMenu, cameraName) then
                    key code 53
                    return true
                end if
            end try

            key code 53
            return false
        end clickCameraMenu

        on clickCameraItem(videoMenu, cameraName)
            if exists menu item cameraName of videoMenu then
                click menu item cameraName of videoMenu
                return true
            end if

            repeat with submenuName in {"Select a Camera", "Camera"}
                if exists menu item submenuName of videoMenu then
                    set cameraSubmenu to menu 1 of menu item submenuName of videoMenu
                    if exists menu item cameraName of cameraSubmenu then
                        click menu item cameraName of cameraSubmenu
                        return true
                    end if
                end if
            end repeat

            return false
        end clickCameraItem

        tell application id "\(escapedBundleID)" to activate
        delay 0.15

        tell application "System Events"
            if UI elements enabled is false then
                error "FaceTracker needs Accessibility access before it can control Zoom."
            end if

            set zoomProcess to first application process whose name is "\(escapedProcessName)"
            set frontmost of zoomProcess to true

            if my clickCameraMenu(zoomProcess, "Video", "\(escapedCameraName)") then
                return
            end if

            if my clickCameraMenu(zoomProcess, "Camera", "\(escapedCameraName)") then
                return
            end if

            error "Zoom couldn't find the camera named \(escapedCameraName). Join a meeting first, then make sure the camera appears in Zoom's Video menu."
        end tell
        """
    }

    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
