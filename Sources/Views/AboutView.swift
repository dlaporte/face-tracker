import SwiftUI
import AVFoundation

struct AboutView: View {

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    private var macOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("FaceTracker")
                .font(.title.bold())

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()
                .frame(width: 200)

            Text("Monitors multiple camera feeds and detects which camera you're looking at using face orientation analysis.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(maxWidth: 320)

            VStack(alignment: .leading, spacing: 6) {
                InfoRow(label: "macOS", value: macOSVersion)
                InfoRow(label: "Cameras", value: "\(cameraCount) detected")
                InfoRow(label: "Detection", value: "Vision (face orientation)")
                InfoRow(label: "Frameworks", value: "AVFoundation, Vision, SwiftUI")
            }
            .font(.caption)
            .padding(.horizontal)

            Divider()
                .frame(width: 200)

            Text("Built as a proof of concept for automatic camera switching.")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .padding(30)
        .frame(width: 380)
    }

    private var cameraCount: Int {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14, *) { types.append(.external) }
        let count = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified
        ).devices.count
        return count
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
        }
    }
}
