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
