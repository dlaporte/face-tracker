import AVFoundation
import Vision
import os

struct FaceAnalyzer {

    /// Returns `.lookingAtCamera` or `.lookingAway` only — never `.noFace`.
    /// `.noFace` is produced by `analyze(_:yawThreshold:pitchThreshold:)` when no face is detected.
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
        let request = VNDetectFaceLandmarksRequest()
        let handler: VNImageRequestHandler
        do {
            handler = try VNImageRequestHandler(cmSampleBuffer: buffer, orientation: .up, options: [:])
            try handler.perform([request])
        } catch {
            os_log(.error, "FaceAnalyzer: Vision request failed: %{public}@", error.localizedDescription)
            return .noFace
        }

        guard let observations = request.results, !observations.isEmpty else {
            return .noFace
        }

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
