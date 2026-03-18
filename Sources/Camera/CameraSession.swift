import AVFoundation
import Vision
import Combine

class CameraSession: NSObject {

    let device: AVCaptureDevice
    let viewModel: CameraViewModel
    let session = AVCaptureSession()

    private let sessionQueue: DispatchQueue
    private let analyzer = FaceAnalyzer()
    private weak var settings: AppSettings?
    private var restartAttempted = false
    private var runtimeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var interruptionEndObserver: NSObjectProtocol?

    init(device: AVCaptureDevice, viewModel: CameraViewModel, settings: AppSettings) {
        self.device = device
        self.viewModel = viewModel
        self.settings = settings
        self.sessionQueue = DispatchQueue(label: "facetracker.camera.\(device.uniqueID)", qos: .userInteractive)
        super.init()
        configure()
        observeErrors()
    }

    func start() {
        sessionQueue.async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
        removeObservers()
    }

    private func configure() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .medium

            guard let input = try? AVCaptureDeviceInput(device: self.device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: self.sessionQueue)
            output.alwaysDiscardsLateVideoFrames = true
            if self.session.canAddOutput(output) {
                self.session.addOutput(output)
            }

            self.session.commitConfiguration()
        }
    }

    private func observeErrors() {
        let nc = NotificationCenter.default

        runtimeObserver = nc.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: session,
            queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            if !self.restartAttempted {
                self.restartAttempted = true
                self.sessionQueue.async {
                    self.session.startRunning()
                    if !self.session.isRunning {
                        DispatchQueue.main.async { self.viewModel.isErrored = true }
                    }
                }
            } else {
                DispatchQueue.main.async { self.viewModel.isErrored = true }
            }
        }

        interruptionObserver = nc.addObserver(
            forName: .AVCaptureSessionWasInterrupted,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.viewModel.gazeState = .noFace
        }

        interruptionEndObserver = nc.addObserver(
            forName: .AVCaptureSessionInterruptionEnded,
            object: session,
            queue: nil
        ) { [weak self] _ in
            self?.sessionQueue.async { self?.session.startRunning() }
        }
    }

    private func removeObservers() {
        [runtimeObserver, interruptionObserver, interruptionEndObserver]
            .compactMap { $0 }
            .forEach { NotificationCenter.default.removeObserver($0) }
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let settings = settings else { return }
        let state = analyzer.analyze(
            sampleBuffer,
            yawThreshold: settings.yawThreshold,
            pitchThreshold: settings.pitchThreshold
        )
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.gazeState = state
        }
    }
}
