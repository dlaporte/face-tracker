import SwiftUI

struct ContentView: View {

    @ObservedObject var cameraManager: CameraSessionManager
    @ObservedObject var controller: ActiveCameraController
    @ObservedObject var settings: AppSettings
    @ObservedObject var zoomIntegration: ZoomIntegrationController
    @ObservedObject var virtualCameraManager: VirtualCameraSystemExtensionManager
    @State private var showingSettings = false

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
        .navigationTitle("FaceTracker")
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                settings: settings,
                cameraManager: cameraManager,
                controller: controller,
                zoomIntegration: zoomIntegration,
                virtualCameraManager: virtualCameraManager
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: emptyStateSymbolName)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(emptyStateTitle)
                .font(.title3)
                .foregroundColor(.secondary)

            Text(emptyStateMessage)
                .font(.caption)
                .foregroundColor(.secondary)

            if cameraManager.allDiscoveredDevices.isEmpty {
                Button(cameraManager.isDiscovering ? "Scanning..." : "Scan Cameras") {
                    cameraManager.enumerateAndSync()
                }
                .buttonStyle(.borderedProminent)
                .disabled(cameraManager.isDiscovering)
            } else {
                HStack(spacing: 10) {
                    Button("Enable First Camera") {
                        if let firstID = cameraManager.allDiscoveredDevices.first?.id {
                            cameraManager.setEnabled(true, for: firstID)
                        }
                    }

                    Button("Enable All Cameras") {
                        cameraManager.setEnabledForAllDiscoveredCameras()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        if cameraManager.isDiscovering {
            return "Scanning for cameras"
        }
        return cameraManager.allDiscoveredDevices.isEmpty ? "No cameras found" : "No cameras enabled"
    }

    private var emptyStateMessage: String {
        if cameraManager.isDiscovering {
            return "FaceTracker is checking available video devices in the background."
        }
        if cameraManager.allDiscoveredDevices.isEmpty {
            return cameraManager.hasCompletedDiscovery
                ? "No video devices were found. Connect a camera, then try Scan Cameras again."
                : "Camera access is granted. Click Scan Cameras when you're ready."
        }
        return "Camera access is granted. Enable one camera first so we can start more safely."
    }

    private var emptyStateSymbolName: String {
        if cameraManager.isDiscovering {
            return "camera"
        }
        return cameraManager.allDiscoveredDevices.isEmpty ? "camera.slash" : "camera.badge.ellipsis"
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
            Button("Settings") {
                showingSettings = true
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }
}
