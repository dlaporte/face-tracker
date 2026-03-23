## Signing and Virtual Camera Handoff

This project includes a macOS app target and a CoreMediaIO system extension target:

- `FaceTracker`
- `FaceTrackerVirtualCamera`

The virtual camera cannot be installed from an ad-hoc signed build. A developer with an Apple Developer Program team must open the project in Xcode and assign a signing team to both targets.

### Xcode steps

1. Open `FaceTracker.xcodeproj` in Xcode.
2. Select the `FaceTracker` project in the navigator.
3. Select the `FaceTracker` target.
4. Open `Signing & Capabilities`.
5. Enable `Automatically manage signing`.
6. Choose your Apple Developer team.
7. Repeat for the `FaceTrackerVirtualCamera` target.
8. Confirm the bundle identifiers remain:
   - `com.facetracker.app`
   - `com.facetracker.app.virtualcamera`
9. Build and run the app.
10. Copy or archive the signed `FaceTracker.app` into `/Applications`.
11. Launch `/Applications/FaceTracker.app`.
12. Open `Settings` in the app, then go to `Virtual Cam`.
13. Click `Install Virtual Camera`.
14. Approve the system extension in macOS `Privacy & Security` if prompted.

### Important notes

- The current virtual camera implementation is still a test-pattern camera, not the live selected physical camera feed.
- The app is intentionally using a sheet-based settings UI because the earlier separate SwiftUI settings scene caused launch beachballing on this machine.
- Zoom integration is currently manual-only inside the settings sheet for the same stability reason.

### Quick verification

After signing, these should no longer report `Signature=adhoc`:

```bash
codesign -dv /Applications/FaceTracker.app 2>&1 | head
codesign -dv /Applications/FaceTracker.app/Contents/Library/SystemExtensions/FaceTrackerVirtualCamera.systemextension 2>&1 | head
```
