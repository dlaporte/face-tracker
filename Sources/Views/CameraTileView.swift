import SwiftUI
import AVFoundation
import AppKit

// MARK: - NSViewRepresentable wrapper for AVCaptureVideoPreviewLayer

struct VideoPreviewView: NSViewRepresentable {

    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.session = session
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.session = session
    }
}

class PreviewNSView: NSView {

    var session: AVCaptureSession? {
        didSet { previewLayer.session = session }
    }

    private let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

// MARK: - CameraTileView

struct CameraTileView: View {

    @ObservedObject var viewModel: CameraViewModel
    let session: AVCaptureSession
    let lookingColor: Color
    var isDefault: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Video preview
            VideoPreviewView(session: session)

            // Color overlay
            if let color = viewModel.overlayColor {
                color
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Top-right badge: gaze state
            Text(viewModel.badgeName)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(badgeBackground)
                .cornerRadius(4)
                .padding(6)
        }
        .overlay(
            // Default camera star (top-left)
            VStack {
                HStack {
                    if isDefault {
                        Text("★")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.yellow)
                            .padding(6)
                    }
                    Spacer()
                }
                Spacer()
            }
        )
        .overlay(
            // Active camera border
            RoundedRectangle(cornerRadius: 6)
                .stroke(viewModel.isActive ? lookingColor : .clear, lineWidth: 3)
        )
        .cornerRadius(6)
        .clipped()
    }

    private var badgeBackground: Color {
        switch viewModel.badgeName {
        case "LOOKING": return .green.opacity(0.8)
        case "AWAY":    return .red.opacity(0.8)
        case "ERROR":   return .orange.opacity(0.8)
        default:        return .black.opacity(0.5)
        }
    }
}
