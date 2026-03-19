import XCTest
@testable import FaceTracker

final class ZoomIntegrationTests: XCTestCase {

    func test_appleScriptEscapesQuotes() {
        let escaped = ZoomAppleScriptBuilder.escape("Logitech \"Front\" Cam")
        XCTAssertEqual(escaped, "Logitech \\\"Front\\\" Cam")
    }

    func test_appleScriptIncludesCameraName() {
        let script = ZoomAppleScriptBuilder.cameraSelectionScript(
            bundleIdentifier: "us.zoom.xos",
            processName: "zoom.us",
            cameraName: "Desk Cam"
        )

        XCTAssertTrue(script.contains("Desk Cam"))
        XCTAssertTrue(script.contains("application id \"us.zoom.xos\""))
        XCTAssertTrue(script.contains("whose name is \"zoom.us\""))
    }
}
