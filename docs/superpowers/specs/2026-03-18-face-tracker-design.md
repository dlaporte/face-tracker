# FaceTracker — Design Spec
**Date:** 2026-03-18
**Status:** Approved

---

## Overview

FaceTracker is a macOS-native proof-of-concept app that monitors multiple webcam feeds simultaneously, detecting whether the user is looking at each camera using the Vision framework. Each camera tile is tinted green when the user is looking at it and red when a face is detected but looking away. The app tracks which camera the user is currently looking at ("active camera") and manages selection with configurable fallback behavior — groundwork for eventual automatic camera switching in video call apps like Zoom.

---

## Goals & Non-Goals

**In scope:**
- Live video preview of multiple cameras in a single tiled window
- Face orientation detection (yaw + pitch) via Vision framework
- Color overlay (green/red/none) per camera tile based on gaze state
- Active camera selection with instant switch and debounced fallback to a configurable default
- Settings panel for colors, opacity, sensitivity, default camera, and fallback delay
- Camera permission handling and graceful degradation

**Out of scope:**
- Actual video input switching in Zoom or other apps
- Gaze vector estimation (requires depth sensor / TrueDepth camera)
- Recording or logging gaze data
- iOS/iPadOS support

---

## Architecture

### Technology Stack

- **Language:** Swift
- **UI:** SwiftUI with `Settings` scene (handles `Cmd+,` automatically), plus `NSViewRepresentable` for camera preview
- **Camera:** AVFoundation (`AVCaptureSession`, `AVCaptureVideoDataOutput`, `AVCaptureVideoPreviewLayer`)
- **Face detection:** Vision — `VNDetectFaceRectanglesRequest`, which returns `VNFaceObservation` objects carrying `.yaw` (macOS 10.14+) and `.pitch` (macOS 12+). No landmarks request needed — yaw/pitch are on the base observation.
- **Camera enumeration:** `AVCaptureDevice.DiscoverySession` with `.video` media type. Device types: `.builtInWideAngleCamera` (always included); `.external` on macOS 14+ (`#available(macOS 14, *)`); on macOS 12–13, external USB cameras appear via `AVCaptureDevice.devices(for: .video)` filtered by `deviceType != .builtInMicrophone`. Implementation should union both approaches.
- **Persistence:** `@AppStorage` for primitives; JSON-encoded strings for collection types
- **Minimum macOS:** 12.0 (Monterey) — required for `VNFaceObservation.pitch` and SwiftUI `ColorPicker`

### GazeState Enum

```swift
enum GazeState: Equatable {
    case lookingAtCamera   // face detected, |yaw| <= yawThreshold AND |pitch| <= pitchThreshold
    case lookingAway       // face detected, outside threshold; or yaw/pitch are nil
    case noFace            // no face detected in frame
}
```

`FaceAnalyzer` mapping rules:
- No observations returned → `.noFace`
- `observation.yaw == nil || observation.pitch == nil` → `.lookingAway`
- `abs(yaw) <= yawThreshold && abs(pitch) <= pitchThreshold` → `.lookingAtCamera`
- Otherwise → `.lookingAway`

### Component Layers

```
Hardware (cameras)
    ↓ AVFoundation sample buffers
CameraSessionManager + CameraSession (one per camera, own serial queue each)
    ↓ CMSampleBuffer frames (per-camera background queue)
FaceAnalyzer → GazeState
    ↓ DispatchQueue.main.async
CameraViewModel + ActiveCameraController + AppSettings
    ↓ SwiftUI @Published bindings
ContentView → CameraTileView (NSViewRepresentable) + SettingsView
```

### Key Components

#### `CameraSession`
- Owns one `AVCaptureSession` per physical camera
- Creates its own dedicated serial `DispatchQueue` — never shared with other sessions
- Configures `AVCaptureVideoDataOutputSampleBufferDelegate` on that queue
- Passes frames to `FaceAnalyzer` synchronously on the session queue; a new `VNImageRequestHandler` is created per frame (not reused)
- Passes `orientation: .up` to `VNImageRequestHandler(cmSampleBuffer:orientation:options:)` — standard webcams deliver frames in natural (upright) orientation; this is sufficient for the POC
- Owns the `AVCaptureVideoPreviewLayer` for the tile view (gravity: `.resizeAspectFill`)
- On `AVCaptureSessionRuntimeErrorNotification`: attempts one `stopRunning` / `startRunning` restart; if the session fails to start again, publishes `isErrored = true`
- Does NOT attempt restart on `AVCaptureSessionWasInterruptedNotification` (e.g., another app taking the camera) — waits for `AVCaptureSessionInterruptionEndedNotification` instead

#### `CameraSessionManager`
- Enumerates cameras via `AVCaptureDeviceDiscoverySession`:
  - Device types: `.builtInWideAngleCamera` plus `.externalUnknown` (macOS 12–13) / `.external` (macOS 14+, checked via `#available`)
  - Media type: `.video`, position: `.unspecified`
- Observes `AVCaptureDevice.wasConnectedNotification` and `wasDisconnectedNotification`; re-runs enumeration on each notification
- Creates `CameraSession` only for cameras in `AppSettings.enabledCameraIDs`; stops and deallocates the session when a camera is disabled (no session runs for disabled cameras)
- On disconnect of active camera: removes tile, immediately triggers `ActiveCameraController` fallback to default

#### `FaceAnalyzer`
- Stateless struct: `func analyze(_ buffer: CMSampleBuffer, settings: AppSettings) -> GazeState`
- Creates a fresh `VNImageRequestHandler` per call (thread-safe; no shared state)
- Runs `VNDetectFaceRectanglesRequest` synchronously; reads `.yaw` and `.pitch` from `VNFaceObservation`
- Uses the first observation sorted by bounding box area (largest face) when multiple faces are detected

#### `CameraViewModel` (ObservableObject, one per camera)
- All mutations happen on main queue
- `@Published var gazeState: GazeState = .noFace`
- `@Published var isActive: Bool = false` — set by `ActiveCameraController`
- `@Published var isErrored: Bool = false` — set when `CameraSession` publishes a permanent error
- `var overlayColor: Color?` — computed in priority order:
  1. `isErrored == true` → `nil` (no color overlay; ERROR badge shown instead)
  2. `.lookingAtCamera` → `AppSettings.lookingColor` at `overlayOpacity`
  3. `.lookingAway` → `AppSettings.awayColor` at `overlayOpacity`
  4. `.noFace` → `nil` (no overlay rendered)

#### `ActiveCameraController` (ObservableObject, lives on main queue)
- Subscribes to all `CameraViewModel.gazeState` publishers via Combine on main queue; all updates arrive on main — no race with `@Published` observers
- **Immediate switch:** when any camera transitions to `.lookingAtCamera`, cancel any running timer, set `activeCameraID` instantly
- **Tie-breaking (simultaneous .lookingAtCamera on multiple cameras):** prefer `defaultCameraID`; if default is not among them, prefer the camera with the lowest index in `AppSettings.enabledCameraIDs`. The `enabledCameraIDs` list is also the display order in the Cameras settings tab; reordering in the UI updates the list order and therefore the tie-break priority.
- **Timer start condition:** the fallback timer starts whenever the set of cameras reporting `.lookingAtCamera` becomes empty — regardless of which camera was previously active
- **Debounced fallback:** after `fallbackDelay` seconds, set `activeCameraID = defaultCameraID`. If `defaultCameraID` is not currently in `enabledCameraIDs`, fall back to `enabledCameraIDs.first`. If `enabledCameraIDs` is empty, set `activeCameraID = nil`.
- **Timer cancellation:** if any camera reports `.lookingAtCamera` before the timer fires, cancel immediately
- `@Published var activeCameraID: String?` — reset to `defaultCameraID` on app launch (not persisted)
- `@Published var fallbackCountdown: Double?` — `nil` when no timer running; otherwise seconds remaining, updated every 0.1s via a separate repeating `Timer`

#### `AppSettings` (ObservableObject)

| Field | Type | Default | Storage |
|-------|------|---------|---------|
| `lookingColor` | `Color` (sRGB hex string) | `#00FF7F` | `@AppStorage("lookingColor")` |
| `awayColor` | `Color` (sRGB hex string) | `#FF3B30` | `@AppStorage("awayColor")` |
| `overlayOpacity` | `Double` | 0.30 | `@AppStorage("overlayOpacity")` |
| `yawThreshold` | `Double` (degrees) | 20.0 | `@AppStorage("yawThreshold")` |
| `pitchThreshold` | `Double` (degrees) | 15.0 | `@AppStorage("pitchThreshold")` |
| `defaultCameraID` | `String` | first enumerated | `@AppStorage("defaultCameraID")` |
| `fallbackDelay` | `Double` (seconds) | 3.0 | `@AppStorage("fallbackDelay")` |
| `enabledCameraIDs` | `[String]` (ordered) | all available | `@AppStorage("enabledCameraIDs")` as JSON string |

Colors stored as sRGB hex strings (`#RRGGBB`). `Color` ↔ hex conversion via a `Color` extension using `NSColor(color).usingColorSpace(.sRGB)`. Opacity is stored separately in `overlayOpacity` and is not embedded in the hex value. `enabledCameraIDs` preserves insertion order; this order defines the tie-breaking index for `ActiveCameraController`.

Camera IDs use `AVCaptureDevice.uniqueID` (stable across reboots).

---

## Camera Permissions

On launch, before starting any sessions:
```
AVCaptureDevice.requestAccess(for: .video) { granted in
    DispatchQueue.main.async {
        if granted { startSessions() }
        else { showPermissionDeniedView() }
    }
}
```
- **Denied / restricted:** full-window placeholder with message and "Open System Settings" button (`x-apple.systempreferences:com.apple.preference.security?Privacy_Camera`)
- **Not determined:** request dialog shown automatically; app waits
- No sessions are created until authorization is confirmed

---

## Error Handling

| Condition | Behavior |
|-----------|----------|
| Camera authorization denied | Full-window placeholder + System Settings link |
| Camera disconnected mid-session | Tile removed; if it was active, immediate fallback to `defaultCameraID` |
| `AVCaptureSessionRuntimeErrorNotification` | One restart attempt; if restart fails, tile shows ERROR badge, no overlay |
| `AVCaptureSessionWasInterruptedNotification` | No restart; wait for `InterruptionEndedNotification`, then resume |
| Vision request fails | Treat frame as `.noFace`; log to console via `os_log` |
| No cameras available / all disabled | Main window shows "No cameras found" empty state |

---

## UI Design

### Main Window (`ContentView`)
- SwiftUI `WindowGroup` scene
- `LazyVGrid` with adaptive columns:
  - 1 camera: 1 column
  - 2 cameras: 2 columns
  - 3–4 cameras: 2 columns (2×2)
  - 5+ cameras: 3 columns; final row left-aligned (empty trailing cells)
  - No scroll; minimum tile size enforced by window minimum width. Max supported camera count in POC: 9 (3×3).
- Toolbar: app name, active camera display name, Settings button
- Status bar: camera count; fallback countdown (e.g., "Falling back in 2.3s…") while timer is running

### Camera Tile (`CameraTileView`)
- `NSViewRepresentable` hosting `NSView` with `AVCaptureVideoPreviewLayer`
- `ZStack`: preview layer + `Color` overlay (from `overlayColor`) + badges
- Top-right badge: "LOOKING" / "AWAY" / "NO FACE" / "ERROR" (ERROR takes priority over gaze state)
- Top-left badge: ★ for default camera
- Active camera tile (the one `ActiveCameraController.activeCameraID` points to): border in `lookingColor`. Non-active tiles have no border regardless of their gaze state.

### Settings Panel
- SwiftUI `Settings` scene (macOS 12+) — automatically wired to `Cmd+,` by the framework
- Three tabs via `TabView`:

**Cameras:**
- `List` of all detected cameras, each with: `Toggle` (enabled/disabled), camera display name, "Set as default" button (disabled if already default, shows ★)
- `Slider` for fallback delay: 0–10s, 0.5s steps

**Appearance:**
- `ColorPicker("Looking at camera", selection: $lookingColor)` — SwiftUI native; opens NSColorPanel
- `ColorPicker("Looking away", selection: $awayColor)`
- `Slider` for overlay opacity: 0–100%

**Detection:**
- `Slider` for yaw threshold: 5°–45°, integer steps, label shows `"\(Int(value))°"`
- `Slider` for pitch threshold: 5°–45°, integer steps

---

## Threading Model

| Thread | Responsibility |
|--------|---------------|
| Per-camera serial `DispatchQueue` | Frame delivery, Vision request execution (one dedicated queue per `CameraSession`) |
| Main queue | All `@Published` updates, SwiftUI rendering, Combine subscriptions, Timer callbacks, `ActiveCameraController` logic |

`FaceAnalyzer.analyze()` runs synchronously on the camera queue. Result is dispatched to main via `DispatchQueue.main.async`. Because `ActiveCameraController` subscribes to `CameraViewModel` publishers on the main queue and all updates arrive via `main.async`, all reads of `gazeState` in `ActiveCameraController` are on main — no race conditions.

---

## Future Considerations (out of scope for POC)

- Expose `activeCameraID` via XPC or local IPC for a Zoom plugin
- Menu bar icon showing current active camera
- Logging/analytics of gaze patterns over time
- Gaze confidence scoring if Apple expands Vision APIs
