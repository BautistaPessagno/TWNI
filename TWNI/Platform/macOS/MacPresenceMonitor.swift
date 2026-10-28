#if os(macOS)
import AppKit
import CoreAudio
import CoreGraphics
import IOKit.pwr_mgt

/// Tells the eye-break engine whether the user is at the Mac: input idle time,
/// screen lock / display sleep, video playback and calls.
@MainActor
final class MacPresenceMonitor {
    private var isScreenLocked = false
    private var areScreensAsleep = false
    private var isSystemAsleep = false
    private var isSessionInactive = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var activity: NSObjectProtocol?

    func start() {
        guard observers.isEmpty else { return }

        // App Nap would delay the 1-second timer while TWNI is in the
        // background, which would look like the user walked away.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Counting screen time for eye breaks"
        )

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.areScreensAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.areScreensAsleep = false }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.isSystemAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.isSystemAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.isSessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.isSessionInactive = false }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.isScreenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.isScreenLocked = false }
    }

    func snapshot(detectCalls: Bool, detectVideo: Bool) -> Presence {
        let idle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
        let screenOn = !(isScreenLocked || areScreensAsleep || isSystemAsleep || isSessionInactive)
        // Cap video detection so an app that keeps the display awake forever
        // (caffeinate and friends) doesn't hide a long absence.
        let watching = detectVideo && screenOn && idle < 3 * 3600 && Self.isDisplayHeldAwake()
        let inCall = detectCalls && screenOn && Self.isMicrophoneInUse()
        return Presence(idleSeconds: idle, isWatchingMedia: watching, isScreenOn: screenOn, isInCall: inCall)
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        update: @escaping @Sendable @MainActor (MacPresenceMonitor) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self)
            }
        }
        observers.append((center, token))
    }

    // MARK: - System probes

    /// Something (usually a video player or a call) is preventing display sleep.
    private static func isDisplayHeldAwake() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let dictionary = status?.takeRetainedValue() as? [String: Any] else { return false }
        let count = (dictionary["PreventUserIdleDisplaySleep"] as? Int) ?? 0
        return count > 0
    }

    /// The default input device is being used by some app (call or meeting).
    /// Only reads a device property; it never records or opens the microphone.
    private static func isMicrophoneInUse() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let found = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard found == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else { return false }

        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        let read = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running)
        return read == noErr && running != 0
    }
}
#endif
