import SwiftUI

struct AppearanceTab: View {

    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Overlay Colors") {
                ColorPicker("Looking at camera", selection: settings.lookingColorBinding)
                ColorPicker("Looking away", selection: settings.awayColorBinding)
            }
            Section("Overlay Strength") {
                HStack {
                    Text("Opacity")
                    Slider(value: $settings.overlayOpacity, in: 0...1)
                    Text("\(Int(settings.overlayOpacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
