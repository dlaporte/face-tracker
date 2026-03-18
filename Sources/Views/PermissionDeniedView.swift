import SwiftUI

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("Camera Access Required")
                .font(.title2.bold())
            Text("FaceTracker needs permission to access your cameras.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
