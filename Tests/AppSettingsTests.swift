import XCTest
import SwiftUI
@testable import FaceTracker

final class AppSettingsTests: XCTestCase {

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
