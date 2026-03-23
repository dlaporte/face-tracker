## Summary

Fix the macOS startup beachball after camera permission, then restore Zoom and virtual camera controls through a safer in-window settings sheet.

## What changed

- defer camera discovery until the user explicitly clicks `Scan Cameras`
- avoid auto-starting all discovered cameras on first launch
- replace the separate SwiftUI `Settings` scene with a sheet opened from the main window
- restore camera, appearance, detection, Zoom, and virtual camera controls inside that sheet
- keep Zoom integration manual-only for stability
- add a `Close` button to the settings sheet
- improve virtual camera install messaging and detect unsupported non-`/Applications` launches
- add signing handoff notes for testing the system extension

## Why

Sampling and spindumps showed the app was hanging in SwiftUI scene/menu update work rather than AVFoundation. Moving settings out of a separate scene and removing automatic integration refreshes eliminated the beachball while preserving app functionality.

## Notes

- the virtual camera currently publishes a test-pattern device, not the live selected camera feed
- installing the system extension still requires a properly signed build from an Apple Developer team
- ad-hoc signed builds from local development cannot install the virtual camera

## Validation

- `xcodebuild build -project FaceTracker.xcodeproj -scheme FaceTracker -destination 'platform=macOS' -derivedDataPath .derivedData`
- confirmed locally that granting camera access no longer causes the app to beachball
- confirmed the in-window settings sheet opens and closes cleanly
- confirmed the Zoom and Virtual Cam tabs can be opened inside the sheet without reintroducing the launch hang
