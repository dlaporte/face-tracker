import SwiftUI

struct DetectionTab: View {

    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Gaze Sensitivity") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Yaw threshold (left/right)")
                    Text("Max head-turn angle to count as 'looking'")
                        .font(.caption).foregroundColor(.secondary)
                    HStack {
                        Slider(value: $settings.yawThreshold, in: 0...90, step: 1)
                        Text("\(Int(settings.yawThreshold))°")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pitch threshold (up/down)")
                    Text("Max head-tilt angle to count as 'looking'")
                        .font(.caption).foregroundColor(.secondary)
                    HStack {
                        Slider(value: $settings.pitchThreshold, in: 0...90, step: 1)
                        Text("\(Int(settings.pitchThreshold))°")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
