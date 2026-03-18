# FaceTracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS app that shows multiple camera feeds in a tiled window, tints each tile green/red based on whether the user is looking at that camera, and tracks which camera is "active" with a configurable fallback timer.

**Architecture:** SwiftUI `WindowGroup` + `Settings` scene for the top-level app; `NSViewRepresentable` bridges `AVCaptureVideoPreviewLayer` into SwiftUI tiles; Vision's `VNDetectFaceRectanglesRequest` runs on a per-camera background queue and publishes `GazeState` to main via Combine; `ActiveCameraController` manages selection logic on main.

**Tech Stack:** Swift 5.9, SwiftUI, AVFoundation, Vision, Combine, XCTest, xcodegen (project generation), macOS 12+.

---

## File Map

| File | Responsibility |
|------|---------------|
| `project.yml` | xcodegen config — targets, entitlements, deployment target |
| `Sources/Info.plist` | `NSCameraUsageDescription` and bundle metadata |
| `Sources/FaceTracker.entitlements` | `com.apple.security.device.camera` |
| `Sources/FaceTrackerApp.swift` | `@main` App — permission check, WindowGroup, Settings scene |
| `Sources/Camera/GazeState.swift` | `GazeState` enum (lookingAtCamera / lookingAway / noFace) |
| `Sources/Camera/FaceAnalyzer.swift` | Stateless Vision wrapper; pure `gazeState(yaw:pitch:...)` function |
| `Sources/Camera/CameraSession.swift` | One `AVCaptureSession` per camera + Vision on its own serial queue |
| `Sources/Camera/CameraSessionManager.swift` | Device enumeration, hot-plug, session lifecycle |
| `Sources/Models/AppSettings.swift` | `@AppStorage` settings + `Color` ↔ hex extension |
| `Sources/Models/CameraViewModel.swift` | Per-camera `ObservableObject` — gazeState, isActive, isErrored, overlayColor |
| `Sources/Models/ActiveCameraController.swift` | Selection logic: instant switch, tie-break, debounced fallback timer |
| `Sources/Views/CameraTileView.swift` | `NSViewRepresentable` + `ZStack` overlay + badges |
| `Sources/Views/ContentView.swift` | `LazyVGrid` of tiles + toolbar + status bar |
| `Sources/Views/PermissionDeniedView.swift` | Full-window auth-denied placeholder |
| `Sources/Views/Settings/SettingsView.swift` | `TabView` container for 3 settings tabs |
| `Sources/Views/Settings/CamerasTab.swift` | Camera toggles, default selection, fallback delay slider |
| `Sources/Views/Settings/AppearanceTab.swift` | ColorPicker × 2 + opacity slider |
| `Sources/Views/Settings/DetectionTab.swift` | Yaw + pitch threshold sliders |
| `Tests/GazeStateTests.swift` | Unit tests for `FaceAnalyzer.gazeState(yaw:pitch:...)` |
| `Tests/AppSettingsTests.swift` | Unit tests for Color ↔ hex round-trip + enabledCameraIDs JSON encoding |
| `Tests/CameraViewModelTests.swift` | Unit tests for `overlayColor` priority logic |
| `Tests/ActiveCameraControllerTests.swift` | Unit tests for instant switch, tie-break, fallback target state |

---

## Task 1: Project Scaffold

**Files:**
- Create: `project.yml`
- Create: `Sources/Info.plist`
- Create: `Sources/FaceTracker.entitlements`

- [ ] **Step 1: Check for xcodegen**

```bash
which xcodegen || brew install xcodegen
```

- [ ] **Step 2: Create `project.yml`**

```yaml
name: FaceTracker
options:
  deploymentTarget:
    macOS: "12.0"
  bundleIdPrefix: com.facetracker
targets:
  FaceTracker:
    type: application
    platform: macOS
    sources:
      - path: Sources
    settings:
      base:
        INFOPLIST_FILE: Sources/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.facetracker.app
        SWIFT_VERSION: 5.9
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: ""
        CODE_SIGN_IDENTITY: "-"
        OTHER_LDFLAGS: ""
    entitlements:
      path: Sources/FaceTracker.entitlements
  FaceTrackerTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests
    dependencies:
      - target: FaceTracker
    settings:
      base:
        SWIFT_VERSION: 5.9
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/FaceTracker.app/Contents/MacOS/FaceTracker"
        BUNDLE_LOADER: "$(TEST_HOST)"
```

- [ ] **Step 3: Create `Sources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>FaceTracker</string>
    <key>CFBundleIdentifier</key>
    <string>com.facetracker.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>NSCameraUsageDescription</key>
    <string>FaceTracker needs camera access to detect which camera you are looking at.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSMainStoryboardFile</key>
    <string></string>
</dict>
</plist>
```

- [ ] **Step 4: Create `Sources/FaceTracker.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.camera</key>
    <true/>
    <key>com.apple.security.app-sandbox</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 5: Create source directories**

```bash
mkdir -p Sources/Camera Sources/Models Sources/Views/Settings Tests
```

- [ ] **Step 6: Generate Xcode project**

```bash
xcodegen generate
```

Expected: `FaceTracker.xcodeproj` created with no errors.

- [ ] **Step 7: Commit**

```bash
git add project.yml Sources/Info.plist Sources/FaceTracker.entitlements
git commit -m "chore: scaffold Xcode project with xcodegen"
```

---

## Task 2: GazeState Enum

**Files:**
- Create: `Sources/Camera/GazeState.swift`
- Create: `Tests/GazeStateTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/GazeStateTests.swift
import XCTest
@testable import FaceTracker

final class GazeStateTests: XCTestCase {

    // MARK: - FaceAnalyzer.gazeState pure logic

    func test_lookingAtCamera_whenBothWithinThreshold() {
        let state = FaceAnalyzer.gazeState(yaw: 10, pitch: 8, yawThreshold: 20, pitchThreshold: 15)
        XCTAssertEqual(state, .lookingAtCamera)
    }

    func test_lookingAtCamera_whenExactlyAtThreshold() {
        let state = FaceAnalyzer.gazeState(yaw: 20, pitch: 15, yawThreshold: 20, pitchThreshold: 15)
        XCTAssertEqual(state, .lookingAtCamera)
    }

    func test_lookingAway_whenYawExceedsThreshold() {
        let state = FaceAnalyzer.gazeState(yaw: 25, pitch: 8, yawThreshold: 20, pitchThreshold: 15)
        XCTAssertEqual(state, .lookingAway)
    }

    func test_lookingAway_whenPitchExceedsThreshold() {
        let state = FaceAnalyzer.gazeState(yaw: 5, pitch: 20, yawThreshold: 20, pitchThreshold: 15)
        XCTAssertEqual(state, .lookingAway)
    }

    func test_lookingAway_whenYawNil() {
        let state = FaceAnalyzer.gazeState(yaw: nil, pitch: 8, yawThreshold: 20, pitchThreshold: 15)
        XCTAssertEqual(state, .lookingAway)
    }

    func test_lookingAway_whenPitchNil() {
        let state = FaceAnalyzer.gazeState(yaw: 5, pitch: nil, yawThreshold: 20, pitchThreshold: 15)
        XCTAssertEqual(state, .lookingAway)
    }

    func test_lookingAtCamera_withNegativeAnglesWithinThreshold() {
        let state = FaceAnalyzer.gazeState(yaw: -18, pitch: -12, yawThreshold: 20, pitchThreshold: 15)
        XCTAssertEqual(state, .lookingAtCamera)
    }
}
```

- [ ] **Step 2: Create `Sources/Camera/GazeState.swift`**

```swift
import Foundation

enum GazeState: Equatable {
    case lookingAtCamera
    case lookingAway
    case noFace
}
```

- [ ] **Step 3: Create `Sources/Camera/FaceAnalyzer.swift`** with the pure function only (Vision integration comes later)

```swift
import AVFoundation
import Vision

struct FaceAnalyzer {

    // Pure, testable logic — no AVFoundation dependency
    static func gazeState(
        yaw: Double?,
        pitch: Double?,
        yawThreshold: Double,
        pitchThreshold: Double
    ) -> GazeState {
        guard let yaw = yaw, let pitch = pitch else { return .lookingAway }
        return abs(yaw) <= yawThreshold && abs(pitch) <= pitchThreshold
            ? .lookingAtCamera
            : .lookingAway
    }

    // AVFoundation + Vision integration (called from CameraSession background queue)
    func analyze(_ buffer: CMSampleBuffer, yawThreshold: Double, pitchThreshold: Double) -> GazeState {
        let request = VNDetectFaceRectanglesRequest()
        guard let handler = try? VNImageRequestHandler(cmSampleBuffer: buffer, orientation: .up, options: [:]),
              let _ = try? handler.perform([request]),
              let observations = request.results, !observations.isEmpty
        else {
            return .noFace
        }

        // Use largest face
        let largest = observations.max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        })!

        return FaceAnalyzer.gazeState(
            yaw: largest.yaw.map { Double(truncating: $0) },
            pitch: largest.pitch.map { Double(truncating: $0) },
            yawThreshold: yawThreshold,
            pitchThreshold: pitchThreshold
        )
    }
}
```

- [ ] **Step 4: Run tests in Xcode**

Open `FaceTracker.xcodeproj`, select the `FaceTrackerTests` target, press `Cmd+U`.
Expected: All `GazeStateTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Camera/GazeState.swift Sources/Camera/FaceAnalyzer.swift Tests/GazeStateTests.swift
git commit -m "feat: add GazeState enum and FaceAnalyzer with pure logic + tests"
```

---

## Task 3: AppSettings

**Files:**
- Create: `Sources/Models/AppSettings.swift`
- Create: `Tests/AppSettingsTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/AppSettingsTests.swift
import XCTest
import SwiftUI
@testable import FaceTracker

final class AppSettingsTests: XCTestCase {

    // MARK: - Color hex round-trip

    func test_colorHexRoundTrip_red() {
        let original = Color(hex: "#FF0000")
        let hex = original.hexString
        XCTAssertEqual(hex.uppercased(), "#FF0000")
    }

    func test_colorHexRoundTrip_green() {
        let original = Color(hex: "#00FF7F")
        XCTAssertEqual(original.hexString.uppercased(), "#00FF7F")
    }

    func test_colorHex_lowercaseInput() {
        let color = Color(hex: "#ff3b30")
        XCTAssertEqual(color.hexString.uppercased(), "#FF3B30")
    }

    func test_colorHex_withoutHash() {
        let color = Color(hex: "00FF7F")
        XCTAssertEqual(color.hexString.uppercased(), "#00FF7F")
    }

    // MARK: - enabledCameraIDs JSON encoding

    func test_enabledCameraIDs_encodeDecodeRoundTrip() {
        let ids = ["cam-1", "cam-2", "cam-3"]
        let encoded = AppSettings.encodeIDs(ids)
        let decoded = AppSettings.decodeIDs(encoded)
        XCTAssertEqual(decoded, ids)
    }

    func test_enabledCameraIDs_emptyArray() {
        let encoded = AppSettings.encodeIDs([])
        let decoded = AppSettings.decodeIDs(encoded)
        XCTAssertEqual(decoded, [])
    }

    func test_enabledCameraIDs_preservesOrder() {
        let ids = ["z-cam", "a-cam", "m-cam"]
        let decoded = AppSettings.decodeIDs(AppSettings.encodeIDs(ids))
        XCTAssertEqual(decoded, ids)
    }
}
```

- [ ] **Step 2: Create `Sources/Models/AppSettings.swift`**

```swift
import SwiftUI
import AppKit

// MARK: - Color hex extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int & 0xFF0000) >> 16) / 255
        let g = Double((int & 0x00FF00) >> 8) / 255
        let b = Double(int & 0x0000FF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .green
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - AppSettings

class AppSettings: ObservableObject {

    static let shared = AppSettings()

    // Primitive @AppStorage fields
    @AppStorage("overlayOpacity")   var overlayOpacity: Double = 0.30
    @AppStorage("yawThreshold")     var yawThreshold: Double  = 20.0
    @AppStorage("pitchThreshold")   var pitchThreshold: Double = 15.0
    @AppStorage("fallbackDelay")    var fallbackDelay: Double  = 3.0
    @AppStorage("defaultCameraID")  var defaultCameraID: String = ""

    // Color fields — stored as hex strings
    @AppStorage("lookingColorHex") private var lookingColorHex: String = "#00FF7F"
    @AppStorage("awayColorHex")    private var awayColorHex: String   = "#FF3B30"

    var lookingColor: Color {
        get { Color(hex: lookingColorHex) }
        set { lookingColorHex = newValue.hexString }
    }

    var awayColor: Color {
        get { Color(hex: awayColorHex) }
        set { awayColorHex = newValue.hexString }
    }

    // Bindings for ColorPicker
    var lookingColorBinding: Binding<Color> {
        Binding(get: { self.lookingColor }, set: { self.lookingColor = $0 })
    }
    var awayColorBinding: Binding<Color> {
        Binding(get: { self.awayColor }, set: { self.awayColor = $0 })
    }

    // enabledCameraIDs — ordered [String] stored as JSON
    @AppStorage("enabledCameraIDsJSON") private var enabledCameraIDsJSON: String = "[]"

    var enabledCameraIDs: [String] {
        get { AppSettings.decodeIDs(enabledCameraIDsJSON) }
        set { enabledCameraIDsJSON = AppSettings.encodeIDs(newValue) }
    }

    // MARK: - JSON helpers (static so tests can call them)

    static func encodeIDs(_ ids: [String]) -> String {
        (try? String(data: JSONEncoder().encode(ids), encoding: .utf8)) ?? "[]"
    }

    static func decodeIDs(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return ids
    }
}
```

- [ ] **Step 3: Run tests**

`Cmd+U` in Xcode. Expected: All `AppSettingsTests` pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/Models/AppSettings.swift Tests/AppSettingsTests.swift
git commit -m "feat: add AppSettings with Color hex extension and JSON camera ID storage"
```

---

## Task 4: CameraViewModel

**Files:**
- Create: `Sources/Models/CameraViewModel.swift`
- Create: `Tests/CameraViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/CameraViewModelTests.swift
import XCTest
import SwiftUI
@testable import FaceTracker

final class CameraViewModelTests: XCTestCase {

    var settings: AppSettings!
    var vm: CameraViewModel!

    override func setUp() {
        super.setUp()
        settings = AppSettings()
        settings.overlayOpacity = 0.4
        vm = CameraViewModel(deviceID: "test-cam", displayName: "Test Camera", settings: settings)
    }

    func test_overlayColor_lookingAtCamera_returnsLookingColor() {
        vm.gazeState = .lookingAtCamera
        XCTAssertNotNil(vm.overlayColor)
    }

    func test_overlayColor_lookingAway_returnsAwayColor() {
        vm.gazeState = .lookingAway
        XCTAssertNotNil(vm.overlayColor)
    }

    func test_overlayColor_noFace_returnsNil() {
        vm.gazeState = .noFace
        XCTAssertNil(vm.overlayColor)
    }

    func test_overlayColor_errored_returnsNil_regardlessOfGazeState() {
        vm.gazeState = .lookingAtCamera
        vm.isErrored = true
        XCTAssertNil(vm.overlayColor)
    }

    func test_badgeName_lookingAtCamera() {
        vm.gazeState = .lookingAtCamera
        vm.isErrored = false
        XCTAssertEqual(vm.badgeName, "LOOKING")
    }

    func test_badgeName_lookingAway() {
        vm.gazeState = .lookingAway
        XCTAssertEqual(vm.badgeName, "AWAY")
    }

    func test_badgeName_noFace() {
        vm.gazeState = .noFace
        XCTAssertEqual(vm.badgeName, "NO FACE")
    }

    func test_badgeName_errored_takesOverGazeState() {
        vm.gazeState = .lookingAtCamera
        vm.isErrored = true
        XCTAssertEqual(vm.badgeName, "ERROR")
    }
}
```

- [ ] **Step 2: Create `Sources/Models/CameraViewModel.swift`**

```swift
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

    // MARK: - Computed display properties

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
```

- [ ] **Step 3: Run tests**

`Cmd+U`. Expected: All `CameraViewModelTests` pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/Models/CameraViewModel.swift Tests/CameraViewModelTests.swift
git commit -m "feat: add CameraViewModel with overlay color and badge logic + tests"
```

---

## Task 5: ActiveCameraController

**Files:**
- Create: `Sources/Models/ActiveCameraController.swift`
- Create: `Tests/ActiveCameraControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/ActiveCameraControllerTests.swift
import XCTest
import Combine
@testable import FaceTracker

final class ActiveCameraControllerTests: XCTestCase {

    var settings: AppSettings!
    var controller: ActiveCameraController!
    var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        settings = AppSettings()
        settings.fallbackDelay = 60 // large so timer doesn't fire during tests
        controller = ActiveCameraController(settings: settings)
    }

    override func tearDown() {
        cancellables.removeAll()
        controller = nil
        super.tearDown()
    }

    // MARK: - Immediate switch

    func test_immediateSwitchOnLookingAtCamera() {
        let camA = CameraViewModel(deviceID: "cam-a", displayName: "A", settings: settings)
        let camB = CameraViewModel(deviceID: "cam-b", displayName: "B", settings: settings)
        settings.enabledCameraIDs = ["cam-a", "cam-b"]
        controller.update(cameras: [camA, camB])

        camA.gazeState = .lookingAtCamera
        controller.evaluateGazeStates()

        XCTAssertEqual(controller.activeCameraID, "cam-a")
    }

    func test_immediateSwitch_updatesIsActiveFlag() {
        let camA = CameraViewModel(deviceID: "cam-a", displayName: "A", settings: settings)
        let camB = CameraViewModel(deviceID: "cam-b", displayName: "B", settings: settings)
        settings.enabledCameraIDs = ["cam-a", "cam-b"]
        controller.update(cameras: [camA, camB])

        camA.gazeState = .lookingAtCamera
        controller.evaluateGazeStates()

        XCTAssertTrue(camA.isActive)
        XCTAssertFalse(camB.isActive)
    }

    // MARK: - Tie-breaking

    func test_tieBraking_prefersDefaultCamera() {
        let camA = CameraViewModel(deviceID: "cam-a", displayName: "A", settings: settings)
        let camB = CameraViewModel(deviceID: "cam-b", displayName: "B", settings: settings)
        settings.enabledCameraIDs = ["cam-a", "cam-b"]
        settings.defaultCameraID = "cam-b"
        controller.update(cameras: [camA, camB])

        camA.gazeState = .lookingAtCamera
        camB.gazeState = .lookingAtCamera
        controller.evaluateGazeStates()

        XCTAssertEqual(controller.activeCameraID, "cam-b")
    }

    func test_tieBreaking_prefersLowestIndexWhenDefaultNotLooking() {
        let camA = CameraViewModel(deviceID: "cam-a", displayName: "A", settings: settings)
        let camB = CameraViewModel(deviceID: "cam-b", displayName: "B", settings: settings)
        let camC = CameraViewModel(deviceID: "cam-c", displayName: "C", settings: settings)
        settings.enabledCameraIDs = ["cam-a", "cam-b", "cam-c"]
        settings.defaultCameraID = "cam-c" // cam-c is NOT looking
        controller.update(cameras: [camA, camB, camC])

        camA.gazeState = .lookingAtCamera
        camB.gazeState = .lookingAtCamera
        controller.evaluateGazeStates()

        XCTAssertEqual(controller.activeCameraID, "cam-a") // lowest index looking
    }

    // MARK: - Fallback target state

    func test_fallback_setsActiveToDDefault() {
        let camA = CameraViewModel(deviceID: "cam-a", displayName: "A", settings: settings)
        let camB = CameraViewModel(deviceID: "cam-b", displayName: "B", settings: settings)
        settings.enabledCameraIDs = ["cam-a", "cam-b"]
        settings.defaultCameraID = "cam-b"
        controller.update(cameras: [camA, camB])

        controller.triggerFallback() // simulate timer firing

        XCTAssertEqual(controller.activeCameraID, "cam-b")
    }

    func test_fallback_usesFirstEnabledWhenDefaultNotEnabled() {
        let camA = CameraViewModel(deviceID: "cam-a", displayName: "A", settings: settings)
        settings.enabledCameraIDs = ["cam-a"]
        settings.defaultCameraID = "cam-missing"
        controller.update(cameras: [camA])

        controller.triggerFallback()

        XCTAssertEqual(controller.activeCameraID, "cam-a")
    }

    func test_fallback_setsNilWhenNoCamerasEnabled() {
        settings.enabledCameraIDs = []
        controller.update(cameras: [])

        controller.triggerFallback()

        XCTAssertNil(controller.activeCameraID)
    }
}
```

- [ ] **Step 2: Create `Sources/Models/ActiveCameraController.swift`**

```swift
import Foundation
import Combine
import SwiftUI

class ActiveCameraController: ObservableObject {

    @Published var activeCameraID: String?
    @Published var fallbackCountdown: Double?

    private let settings: AppSettings
    private var cameras: [CameraViewModel] = []
    private var fallbackTimer: Timer?
    private var countdownTimer: Timer?
    private var fallbackDeadline: Date?
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings
    }

    // Called by CameraSessionManager whenever the camera list changes
    func update(cameras: [CameraViewModel]) {
        self.cameras = cameras
        // Subscribe to each camera's gazeState
        cancellables.removeAll()
        for cam in cameras {
            cam.$gazeState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.evaluateGazeStates() }
                .store(in: &cancellables)
        }
        // Reset active to default
        activeCameraID = resolvedDefaultID()
        updateIsActiveFlags()
    }

    // Evaluate which camera is looking and update activeCameraID
    func evaluateGazeStates() {
        let looking = cameras.filter { $0.gazeState == .lookingAtCamera }

        if looking.isEmpty {
            // Start fallback timer if not already running
            if fallbackTimer == nil {
                startFallbackTimer()
            }
        } else {
            // Cancel timer, switch immediately
            cancelTimers()
            let winner = pickWinner(from: looking)
            activeCameraID = winner.id
            updateIsActiveFlags()
        }
    }

    // Simulate timer firing (also used directly in tests)
    func triggerFallback() {
        cancelTimers()
        activeCameraID = resolvedDefaultID()
        updateIsActiveFlags()
    }

    // MARK: - Private

    private func pickWinner(from looking: [CameraViewModel]) -> CameraViewModel {
        // Prefer default camera
        if let def = looking.first(where: { $0.id == settings.defaultCameraID }) {
            return def
        }
        // Otherwise prefer lowest index in enabledCameraIDs
        let order = settings.enabledCameraIDs
        return looking.min(by: {
            (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max)
        }) ?? looking[0]
    }

    private func resolvedDefaultID() -> String? {
        let enabled = settings.enabledCameraIDs
        if enabled.contains(settings.defaultCameraID) { return settings.defaultCameraID }
        return enabled.first
    }

    private func updateIsActiveFlags() {
        for cam in cameras {
            cam.isActive = cam.id == activeCameraID
        }
    }

    private func startFallbackTimer() {
        let delay = settings.fallbackDelay
        fallbackDeadline = Date().addingTimeInterval(delay)

        fallbackTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.triggerFallback()
        }

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let deadline = self.fallbackDeadline else { return }
            let remaining = deadline.timeIntervalSinceNow
            if remaining > 0 {
                self.fallbackCountdown = remaining
            } else {
                self.fallbackCountdown = nil
            }
        }
    }

    private func cancelTimers() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        fallbackDeadline = nil
        fallbackCountdown = nil
    }
}
```

- [ ] **Step 3: Run tests**

`Cmd+U`. Expected: All `ActiveCameraControllerTests` pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/Models/ActiveCameraController.swift Tests/ActiveCameraControllerTests.swift
git commit -m "feat: add ActiveCameraController with selection logic, tie-breaking, fallback + tests"
```

---

## Task 6: CameraSession

**Files:**
- Create: `Sources/Camera/CameraSession.swift`

*No unit tests — AVFoundation requires real hardware. Verified by running the app.*

- [ ] **Step 1: Create `Sources/Camera/CameraSession.swift`**

```swift
import AVFoundation
import Vision
import Combine

class CameraSession: NSObject {

    let device: AVCaptureDevice
    let viewModel: CameraViewModel

    private let session = AVCaptureSession()
    private let sessionQueue: DispatchQueue
    private let analyzer = FaceAnalyzer()
    private weak var settings: AppSettings?
    private var restartAttempted = false
    private var runtimeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var interruptionEndObserver: NSObjectProtocol?

    // AVCaptureVideoPreviewLayer for the tile view
    var previewLayer: AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    init(device: AVCaptureDevice, viewModel: CameraViewModel, settings: AppSettings) {
        self.device = device
        self.viewModel = viewModel
        self.settings = settings
        self.sessionQueue = DispatchQueue(label: "facetracker.camera.\(device.uniqueID)", qos: .userInteractive)
        super.init()
        configure()
        observeErrors()
    }

    func start() {
        sessionQueue.async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
        removeObservers()
    }

    // MARK: - Private

    private func configure() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .medium

            guard let input = try? AVCaptureDeviceInput(device: self.device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: self.sessionQueue)
            output.alwaysDiscardsLateVideoFrames = true
            if self.session.canAddOutput(output) {
                self.session.addOutput(output)
            }

            self.session.commitConfiguration()
        }
    }

    private func observeErrors() {
        let nc = NotificationCenter.default

        runtimeObserver = nc.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: session,
            queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            if !self.restartAttempted {
                self.restartAttempted = true
                self.sessionQueue.async {
                    self.session.startRunning()
                    if !self.session.isRunning {
                        DispatchQueue.main.async { self.viewModel.isErrored = true }
                    }
                }
            } else {
                DispatchQueue.main.async { self.viewModel.isErrored = true }
            }
        }

        interruptionObserver = nc.addObserver(
            forName: .AVCaptureSessionWasInterrupted,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.viewModel.gazeState = .noFace
        }

        interruptionEndObserver = nc.addObserver(
            forName: .AVCaptureSessionInterruptionEnded,
            object: session,
            queue: nil
        ) { [weak self] _ in
            self?.sessionQueue.async { self?.session.startRunning() }
        }
    }

    private func removeObservers() {
        [runtimeObserver, interruptionObserver, interruptionEndObserver]
            .compactMap { $0 }
            .forEach { NotificationCenter.default.removeObserver($0) }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let settings = settings else { return }
        let state = analyzer.analyze(
            sampleBuffer,
            yawThreshold: settings.yawThreshold,
            pitchThreshold: settings.pitchThreshold
        )
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.gazeState = state
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

In Xcode: `Cmd+B`. Expected: builds clean, no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Camera/CameraSession.swift
git commit -m "feat: add CameraSession with AVFoundation capture and Vision integration"
```

---

## Task 7: CameraSessionManager

**Files:**
- Create: `Sources/Camera/CameraSessionManager.swift`

- [ ] **Step 1: Create `Sources/Camera/CameraSessionManager.swift`**

```swift
import AVFoundation
import Combine

class CameraSessionManager: ObservableObject {

    @Published var cameraViewModels: [CameraViewModel] = []

    private var sessions: [String: CameraSession] = [:]
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

    // MARK: - Public

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

    // MARK: - Private

    private func enumerateAndSync() {
        let discovered = discoverDevices()
        let enabled = settings.enabledCameraIDs

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

            if enabled.contains(id) {
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

        // On macOS 12-13 also include external USB cameras not caught above
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
```

- [ ] **Step 2: Build (`Cmd+B`)** — expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Camera/CameraSessionManager.swift
git commit -m "feat: add CameraSessionManager with device enumeration, hot-plug, and session lifecycle"
```

---

## Task 8: CameraTileView

**Files:**
- Create: `Sources/Views/CameraTileView.swift`

- [ ] **Step 1: Create `Sources/Views/CameraTileView.swift`**

```swift
import SwiftUI
import AVFoundation
import AppKit

// MARK: - NSViewRepresentable wrapper for AVCaptureVideoPreviewLayer

struct VideoPreviewView: NSViewRepresentable {

    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.session = session
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.session = session
    }
}

class PreviewNSView: NSView {

    var session: AVCaptureSession? {
        didSet { previewLayer.session = session }
    }

    private let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

// MARK: - CameraTileView

struct CameraTileView: View {

    @ObservedObject var viewModel: CameraViewModel
    let session: AVCaptureSession
    let lookingColor: Color

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Video preview
            VideoPreviewView(session: session)

            // Color overlay
            if let color = viewModel.overlayColor {
                color
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Top-right badge: gaze state
            Text(viewModel.badgeName)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(badgeBackground)
                .cornerRadius(4)
                .padding(6)

            // Top-left badge: default camera star
            if viewModel.isActive {
                // active border handled by parent
            }
        }
        .overlay(
            // Default camera star (top-left)
            VStack {
                HStack {
                    if isDefault {
                        Text("★")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.yellow)
                            .padding(6)
                    }
                    Spacer()
                }
                Spacer()
            }
        )
        .overlay(
            // Active camera border
            RoundedRectangle(cornerRadius: 6)
                .stroke(viewModel.isActive ? lookingColor : .clear, lineWidth: 3)
        )
        .cornerRadius(6)
        .clipped()
    }

    // Injected by parent so star renders correctly
    var isDefault: Bool = false

    private var badgeBackground: Color {
        switch viewModel.badgeName {
        case "LOOKING": return .green.opacity(0.8)
        case "AWAY":    return .red.opacity(0.8)
        case "ERROR":   return .orange.opacity(0.8)
        default:        return .black.opacity(0.5)
        }
    }
}
```

- [ ] **Step 2: Build (`Cmd+B`)** — expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Views/CameraTileView.swift
git commit -m "feat: add CameraTileView with preview layer, color overlay, and status badges"
```

---

## Task 9: Settings Views

**Files:**
- Create: `Sources/Views/Settings/SettingsView.swift`
- Create: `Sources/Views/Settings/CamerasTab.swift`
- Create: `Sources/Views/Settings/AppearanceTab.swift`
- Create: `Sources/Views/Settings/DetectionTab.swift`

- [ ] **Step 1: Create `Sources/Views/Settings/CamerasTab.swift`**

```swift
import SwiftUI

struct CamerasTab: View {

    @ObservedObject var settings: AppSettings
    @ObservedObject var cameraManager: CameraSessionManager

    var body: some View {
        Form {
            Section("Connected Cameras") {
                if cameraManager.cameraViewModels.isEmpty {
                    Text("No cameras detected").foregroundColor(.secondary)
                } else {
                    ForEach(cameraManager.cameraViewModels) { vm in
                        HStack {
                            Toggle(isOn: enabledBinding(for: vm.id)) {
                                Text(vm.displayName)
                            }
                            Spacer()
                            if vm.id == settings.defaultCameraID {
                                Text("★ Default")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else {
                                Button("Set Default") {
                                    settings.defaultCameraID = vm.id
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                        }
                    }
                }
            }

            Section("Fallback Behavior") {
                HStack {
                    Text("Delay before returning to default")
                    Slider(value: $settings.fallbackDelay, in: 0...10, step: 0.5)
                    Text(String(format: "%.1fs", settings.fallbackDelay))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func enabledBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { settings.enabledCameraIDs.contains(id) },
            set: { enabled in cameraManager.setEnabled(enabled, for: id) }
        )
    }
}
```

- [ ] **Step 2: Create `Sources/Views/Settings/AppearanceTab.swift`**

```swift
import SwiftUI

struct AppearanceTab: View {

    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Overlay Colors") {
                ColorPicker("Looking at camera", selection: settings.lookingColorBinding)
                ColorPicker("Looking away", selection: settings.awayColorBinding)
            }
            Section("Overlay Strength") {
                HStack {
                    Text("Opacity")
                    Slider(value: $settings.overlayOpacity, in: 0...1)
                    Text("\(Int(settings.overlayOpacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

- [ ] **Step 3: Create `Sources/Views/Settings/DetectionTab.swift`**

```swift
import SwiftUI

struct DetectionTab: View {

    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Gaze Sensitivity") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Yaw threshold (left/right)")
                    Text("Max head-turn angle to count as 'looking'")
                        .font(.caption).foregroundColor(.secondary)
                    HStack {
                        Slider(value: $settings.yawThreshold, in: 5...45, step: 1)
                        Text("\(Int(settings.yawThreshold))°")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pitch threshold (up/down)")
                    Text("Max head-tilt angle to count as 'looking'")
                        .font(.caption).foregroundColor(.secondary)
                    HStack {
                        Slider(value: $settings.pitchThreshold, in: 5...45, step: 1)
                        Text("\(Int(settings.pitchThreshold))°")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

- [ ] **Step 4: Create `Sources/Views/Settings/SettingsView.swift`**

```swift
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
```

- [ ] **Step 5: Build (`Cmd+B`)** — no errors.

- [ ] **Step 6: Commit**

```bash
git add Sources/Views/Settings/
git commit -m "feat: add Settings views — Cameras, Appearance, Detection tabs"
```

---

## Task 10: ContentView and PermissionDeniedView

**Files:**
- Create: `Sources/Views/ContentView.swift`
- Create: `Sources/Views/PermissionDeniedView.swift`

- [ ] **Step 1: Create `Sources/Views/PermissionDeniedView.swift`**

```swift
import SwiftUI

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("Camera Access Required")
                .font(.title2.bold())
            Text("FaceTracker needs permission to access your cameras.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
```

- [ ] **Step 2: Create `Sources/Views/ContentView.swift`**

```swift
import SwiftUI

struct ContentView: View {

    @ObservedObject var cameraManager: CameraSessionManager
    @ObservedObject var controller: ActiveCameraController
    @ObservedObject var settings: AppSettings

    private var columns: [GridItem] {
        let count = cameraManager.cameraViewModels.count
        let cols = count <= 1 ? 1 : count <= 4 ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 6), count: cols)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Camera grid
            if cameraManager.cameraViewModels.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(cameraManager.cameraViewModels) { vm in
                        if let session = cameraManager.sessions[vm.id]?.session {
                            CameraTileView(
                                viewModel: vm,
                                session: session,
                                lookingColor: settings.lookingColor,
                                isDefault: vm.id == settings.defaultCameraID
                            )
                            .aspectRatio(16/9, contentMode: .fit)
                        }
                    }
                }
                .padding(6)
            }

            // Status bar
            statusBar
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text("FaceTracker")
                    .font(.headline)
            }
            ToolbarItem {
                if let activeID = controller.activeCameraID,
                   let vm = cameraManager.cameraViewModels.first(where: { $0.id == activeID }) {
                    Label(vm.displayName, systemImage: "camera.fill")
                        .foregroundColor(settings.lookingColor)
                }
            }
            ToolbarItem {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera").font(.system(size: 48)).foregroundColor(.secondary)
            Text("No cameras found").font(.title3).foregroundColor(.secondary)
            Text("Connect a camera and check Settings → Cameras")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack {
            Text("\(cameraManager.cameraViewModels.count) camera\(cameraManager.cameraViewModels.count == 1 ? "" : "s") active")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if let countdown = controller.fallbackCountdown {
                Text(String(format: "Falling back in %.1fs…", countdown))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }
}
```

**Note:** `ContentView` accesses `cameraManager.sessions` which is currently private. In Task 11 you will expose `sessions` as `internal` (not `private`) in `CameraSessionManager`.

- [ ] **Step 3: Expose `sessions` in CameraSessionManager**

In `Sources/Camera/CameraSessionManager.swift`, change:
```swift
private var sessions: [String: CameraSession] = [:]
```
to:
```swift
var sessions: [String: CameraSession] = [:]
```

Also add a `session` computed property on `CameraSession` to expose its internal session:

In `Sources/Camera/CameraSession.swift`, make `session` accessible:
```swift
// Change: private let session = AVCaptureSession()
// To:
let session = AVCaptureSession()
```

- [ ] **Step 4: Build (`Cmd+B`)** — no errors.

- [ ] **Step 5: Commit**

```bash
git add Sources/Views/ContentView.swift Sources/Views/PermissionDeniedView.swift
git add Sources/Camera/CameraSession.swift Sources/Camera/CameraSessionManager.swift
git commit -m "feat: add ContentView with adaptive grid, toolbar, status bar, and permission denied view"
```

---

## Task 11: App Entry Point — Wire Everything Together

**Files:**
- Create: `Sources/FaceTrackerApp.swift`

- [ ] **Step 1: Create `Sources/FaceTrackerApp.swift`**

```swift
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
                    ProgressView("Requesting camera access…")
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
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 540)

        Settings {
            SettingsView(settings: settings, cameraManager: cameraManager)
        }
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
                    if granted { cameraManager.enumerateAndSync() }
                }
            }
        @unknown default:
            cameraAuthorized = false
        }
    }
}
```

**Note:** `enumerateAndSync()` is currently private in `CameraSessionManager`. Change its access level:

In `Sources/Camera/CameraSessionManager.swift`:
```swift
// Change: private func enumerateAndSync()
// To:
func enumerateAndSync()
```

- [ ] **Step 2: Build (`Cmd+B`)** — no errors expected.

- [ ] **Step 3: Commit**

```bash
git add Sources/FaceTrackerApp.swift Sources/Camera/CameraSessionManager.swift
git commit -m "feat: wire app entry point — permission check, WindowGroup, Settings scene"
```

---

## Task 12: Manual Smoke Test

*Run the app and verify all spec requirements work end-to-end.*

- [ ] **Step 1: Run the app in Xcode** (`Cmd+R`)

- [ ] **Step 2: Verify camera permission prompt appears on first launch**

Expected: macOS shows "FaceTracker would like to access the camera" dialog.

- [ ] **Step 3: Grant permission and verify cameras appear as tiles**

Expected: All connected cameras show in the tiled grid. Each tile shows "NO FACE" badge initially.

- [ ] **Step 4: Look directly at one camera**

Expected: That tile shows a green overlay and "LOOKING" badge. Other tiles show red or no overlay.

- [ ] **Step 5: Look away**

Expected: All tiles go red (face detected) or no overlay (no face). Fallback countdown appears in status bar. After `fallbackDelay` seconds, no active border is shown (fallen back to default).

- [ ] **Step 6: Open Settings (`Cmd+,`)**

Expected: Settings window appears with three tabs: Cameras, Appearance, Detection.

- [ ] **Step 7: Change "Looking at camera" color** in Appearance tab

Expected: macOS native color picker opens. After selecting a new color, all green overlays update immediately.

- [ ] **Step 8: Adjust overlay opacity**

Expected: Overlay transparency updates in real time.

- [ ] **Step 9: Adjust yaw threshold** (Detection tab, drag to a very small value like 5°)

Expected: Detection becomes very strict — only looking dead-on triggers green.

- [ ] **Step 10: Toggle a camera off** in Cameras tab

Expected: Tile disappears from grid; session stops.

- [ ] **Step 11: Verify default camera star badge**

Expected: The camera marked as default has a ★ badge in its tile's top-left corner.

- [ ] **Step 12: Final commit**

```bash
git add -A
git commit -m "feat: complete FaceTracker POC — all smoke tests passing"
```

---

## Appendix: Running Unit Tests

From Xcode: Select `FaceTrackerTests` scheme → `Cmd+U`.

Tests cover:
- `GazeStateTests` — FaceAnalyzer threshold logic
- `AppSettingsTests` — Color hex round-trip, JSON encoding
- `CameraViewModelTests` — overlay color priority
- `ActiveCameraControllerTests` — selection, tie-breaking, fallback

AVFoundation/Vision integration and all UI behavior verified via the manual smoke test in Task 12.
