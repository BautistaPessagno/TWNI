import Foundation
import Combine

#if os(macOS)
import CoreGraphics

@MainActor @Observable
final class MacActivityDetector {
    var isIdle = false

    private var pollTimer: AnyCancellable?
    private let idleThresholdSeconds: TimeInterval = 30
    private weak var timerManager: TimerManager?

    func start(timerManager: TimerManager) {
        self.timerManager = timerManager

        pollTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkIdleState()
            }
    }

    func stop() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func checkIdleState() {
        let idleTime = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )

        let wasIdle = isIdle
        isIdle = idleTime > idleThresholdSeconds

        if isIdle && !wasIdle {
            timerManager?.handleIdlePause()
        } else if !isIdle && wasIdle {
            timerManager?.handleIdleResume()
        }
    }
}
#endif
