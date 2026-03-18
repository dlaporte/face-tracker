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

    func test_tieBreaking_prefersDefaultCamera() {
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
        settings.defaultCameraID = "cam-c"
        controller.update(cameras: [camA, camB, camC])

        camA.gazeState = .lookingAtCamera
        camB.gazeState = .lookingAtCamera
        controller.evaluateGazeStates()

        XCTAssertEqual(controller.activeCameraID, "cam-a")
    }

    // MARK: - Fallback target state

    func test_fallback_setsActiveToDefault() {
        let camA = CameraViewModel(deviceID: "cam-a", displayName: "A", settings: settings)
        let camB = CameraViewModel(deviceID: "cam-b", displayName: "B", settings: settings)
        settings.enabledCameraIDs = ["cam-a", "cam-b"]
        settings.defaultCameraID = "cam-b"
        controller.update(cameras: [camA, camB])

        controller.triggerFallback()

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
