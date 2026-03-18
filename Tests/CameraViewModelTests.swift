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
