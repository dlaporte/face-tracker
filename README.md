# FaceTracker

A macOS-native app that monitors multiple webcam feeds and detects which camera you're looking at using face orientation analysis. Each camera tile is tinted green when you're looking at it and red when you're looking away — a proof of concept for automatic camera switching in video call apps like Zoom.

## How It Works

FaceTracker uses Apple's **Vision framework** to detect face orientation (yaw and pitch) from each camera feed in real time. Each camera runs its own `AVCaptureSession` on a dedicated background queue, with Vision requests analyzing frames independently. Results are published to the UI via Combine.

**Detection flow:**
1. AVFoundation captures video frames from each connected camera
2. Vision's `VNDetectFaceRectanglesRequest` extracts face yaw/pitch (in radians)
3. Angles are compared against configurable thresholds to determine gaze state
4. The UI overlays green (looking), red (looking away), or no tint (no face detected)

**Active camera selection:**
- When you look at a camera, it becomes the "active" camera instantly
- When you look away from all cameras, a configurable timer counts down before falling back to a default camera
- Tie-breaking: prefers the default camera, then the lowest-index enabled camera

## Features

- Multiple camera support with adaptive tiled grid layout (1-9 cameras)
- Real-time face orientation detection via Vision framework
- Configurable overlay colors (standard macOS color picker)
- Adjustable detection sensitivity (yaw/pitch thresholds)
- Configurable overlay opacity
- Default camera selection with debounced fallback timer
- Optional Zoom Workplace camera sync via macOS automation
- Virtual camera system-extension scaffold for Zoom/Meet compatibility
- Camera hot-plug support (connect/disconnect detected automatically)
- Safer first launch: cameras are discovered after permission, but not auto-started until you enable them
- Settings panel with Cameras, Appearance, and Detection tabs
- Camera permission handling with graceful degradation
- Reset to defaults

## Requirements

- macOS 13.0 (Ventura) or later
- One or more connected cameras
- Camera permission

## Building

```bash
# Install xcodegen if needed
brew install xcodegen

# Generate the Xcode project
xcodegen generate

# Build
xcodebuild build -project FaceTracker.xcodeproj -scheme FaceTracker -destination 'platform=macOS'

# Run tests
xcodebuild test -project FaceTracker.xcodeproj -scheme FaceTracker -destination 'platform=macOS'
```

Or open `FaceTracker.xcodeproj` in Xcode and press `Cmd+R`.

## Architecture

| Layer | Components | Responsibility |
|-------|-----------|----------------|
| Camera | `CameraSession`, `CameraSessionManager` | AVFoundation capture, device enumeration, hot-plug |
| Detection | `FaceAnalyzer`, `GazeState` | Vision face detection, yaw/pitch → gaze state |
| State | `CameraViewModel`, `ActiveCameraController`, `AppSettings` | Per-camera state, active selection logic, persistence |
| UI | `ContentView`, `CameraTileView`, `SettingsView` | SwiftUI grid, NSViewRepresentable preview, settings |

Threading: each camera has its own serial dispatch queue for frame capture and Vision processing. All `@Published` updates hop to the main queue. No shared mutable state between queues.

## Settings

- **Cameras** — Enable/disable cameras, set default, configure fallback delay (0-60s)
- **Appearance** — Overlay colors for looking/away states, overlay opacity
- **Detection** — Yaw threshold (0-90°), pitch threshold (0-90°)

## Future

This is a proof of concept. Potential next steps:
- Replace the current AppleScript-based Zoom bridge with a first-party Zoom App / SDK integration
- Feed the active physical camera into the new FaceTracker virtual camera extension
- Menu bar icon showing current active camera
- Gaze confidence scoring

## License

MIT
