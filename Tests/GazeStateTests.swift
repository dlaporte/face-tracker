import XCTest
@testable import FaceTracker

final class GazeStateTests: XCTestCase {

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
