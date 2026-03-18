import SwiftUI

struct ContentView: View {

    @ObservedObject var cameraManager: CameraSessionManager
    @ObservedObject var controller: ActiveCameraController
    @ObservedObject var settings: AppSettings

    private var columns: [GridItem] {
        let count = cameraManager.cameraViewModels.count
        let cols = count <= 1 ? 1 : count <= 4 ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 6), count: cols)
    }

    var body: some View {
        VStack(spacing: 0) {
            if cameraManager.cameraViewModels.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(cameraManager.cameraViewModels) { vm in
                        if let camSession = cameraManager.sessions[vm.id] {
                            CameraTileView(
                                viewModel: vm,
                                session: camSession.session,
                                lookingColor: settings.lookingColor,
                                isDefault: vm.id == settings.defaultCameraID
                            )
                            .aspectRatio(16/9, contentMode: .fit)
                        }
                    }
                }
                .padding(6)
            }

            statusBar
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text("FaceTracker")
                    .font(.headline)
            }
            ToolbarItem {
                if let activeID = controller.activeCameraID,
                   let vm = cameraManager.cameraViewModels.first(where: { $0.id == activeID }) {
                    Label(vm.displayName, systemImage: "camera.fill")
                        .foregroundColor(settings.lookingColor)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera").font(.system(size: 48)).foregroundColor(.secondary)
            Text("No cameras found").font(.title3).foregroundColor(.secondary)
            Text("Connect a camera and check Settings \u{2192} Cameras")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack {
            Text("\(cameraManager.cameraViewModels.count) camera\(cameraManager.cameraViewModels.count == 1 ? "" : "s") active")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if let countdown = controller.fallbackCountdown {
                Text(String(format: "Falling back in %.1fs\u{2026}", countdown))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }
}
