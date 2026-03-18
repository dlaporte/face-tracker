import Foundation
import Combine
import SwiftUI

class ActiveCameraController: ObservableObject {

    @Published var activeCameraID: String?
    @Published var fallbackCountdown: Double?

    private let settings: AppSettings
    private var cameras: [CameraViewModel] = []
    private var fallbackTimer: Timer?
    private var countdownTimer: Timer?
    private var fallbackDeadline: Date?
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings
    }

    func update(cameras: [CameraViewModel]) {
        self.cameras = cameras
        cancellables.removeAll()
        for cam in cameras {
            cam.$gazeState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.evaluateGazeStates() }
                .store(in: &cancellables)
        }
        if activeCameraID == nil || !cameras.contains(where: { $0.id == activeCameraID }) {
            activeCameraID = resolvedDefaultID()
        }
        updateIsActiveFlags()
    }

    func evaluateGazeStates() {
        let looking = cameras.filter { $0.gazeState == .lookingAtCamera }

        if looking.isEmpty {
            if fallbackTimer == nil {
                startFallbackTimer()
            }
        } else {
            cancelTimers()
            let winner = pickWinner(from: looking)
            activeCameraID = winner.id
            updateIsActiveFlags()
        }
    }

    func triggerFallback() {
        cancelTimers()
        activeCameraID = resolvedDefaultID()
        updateIsActiveFlags()
    }

    private func pickWinner(from looking: [CameraViewModel]) -> CameraViewModel {
        if let def = looking.first(where: { $0.id == settings.defaultCameraID }) {
            return def
        }
        let order = settings.enabledCameraIDs
        return looking.min(by: {
            (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max)
        }) ?? looking[0]
    }

    private func resolvedDefaultID() -> String? {
        let enabled = settings.enabledCameraIDs
        if enabled.contains(settings.defaultCameraID) { return settings.defaultCameraID }
        return enabled.first
    }

    private func updateIsActiveFlags() {
        for cam in cameras {
            cam.isActive = cam.id == activeCameraID
        }
    }

    private func startFallbackTimer() {
        let delay = settings.fallbackDelay
        fallbackDeadline = Date().addingTimeInterval(delay)

        fallbackTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.triggerFallback()
        }

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let deadline = self.fallbackDeadline else { return }
            let remaining = deadline.timeIntervalSinceNow
            if remaining > 0 {
                self.fallbackCountdown = remaining
            } else {
                self.fallbackCountdown = nil
            }
        }
    }

    private func cancelTimers() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        fallbackDeadline = nil
        fallbackCountdown = nil
    }
}
