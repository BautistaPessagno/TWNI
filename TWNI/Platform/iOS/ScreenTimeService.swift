#if os(iOS)
import FamilyControls
import Foundation

/// The app side of automatic eye breaks: Screen Time access, which apps count,
/// and the bridge to the extensions' shared state.
@MainActor @Observable
final class ScreenTimeService {
    private(set) var authorization: AuthorizationStatus = AuthorizationCenter.shared.authorizationStatus
    private(set) var mode: ScreenTimeShared.Mode = ScreenTimeShared.mode
    private(set) var selection: FamilyActivitySelection = ScreenTimeShared.selection
    private(set) var isShieldActive = ScreenTimeShared.isShieldActive
    private(set) var lastError: String?

    var isAuthorized: Bool { authorization == .approved }
    /// Counting app use and locking apps is on.
    var isActive: Bool { isAuthorized && mode != .off }

    var selectedCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            lastError = nil
        } catch {
            lastError = "Screen Time access wasn't granted. You can allow it in Settings > Screen Time."
        }
        authorization = AuthorizationCenter.shared.authorizationStatus
    }

    /// Turns automatic breaks on for all apps or the selected ones, or off.
    func setMode(_ newMode: ScreenTimeShared.Mode) {
        ScreenTimeShared.mode = newMode
        mode = newMode
        if newMode == .off {
            ScreenTimeShared.stopCounting()
            isShieldActive = false
        } else {
            rearm()
        }
    }

    func setSelection(_ newSelection: FamilyActivitySelection) {
        ScreenTimeShared.selection = newSelection
        selection = newSelection
        if mode == .selectedApps, !isShieldActive { rearm() }
    }

    /// Keeps the extensions on the same rule as the app.
    func updateRule(intervalMinutes: Int, breakSeconds: Int) {
        let changed = ScreenTimeShared.intervalMinutes != intervalMinutes
        ScreenTimeShared.intervalMinutes = intervalMinutes
        ScreenTimeShared.breakSeconds = breakSeconds
        if changed, isActive, !isShieldActive { rearm() }
    }

    /// Re-reads state the extensions may have changed. Cheap; called every tick.
    func refresh() {
        let shield = ScreenTimeShared.isShieldActive
        if shield != isShieldActive { isShieldActive = shield }
        let status = AuthorizationCenter.shared.authorizationStatus
        if status != authorization { authorization = status }
    }

    /// Makes sure counting is running (after launch, or after access was granted).
    func ensureCounting() {
        guard isActive, !isShieldActive, ScreenTimeShared.armedAt == nil else { return }
        rearm()
    }

    /// The guided break in the app finished or was skipped: unlock and count again.
    func finishBreak(outcome: CycleOutcome, restedSeconds: TimeInterval) {
        ScreenTimeShared.finishBreak(outcome: outcome.rawValue, restedSeconds: restedSeconds)
        isShieldActive = false
    }

    /// Cycles finished on the shield or in the app, waiting to be saved.
    func drainFinishedCycles() -> [CycleRecord] {
        ScreenTimeShared.drainLog().map { cycle in
            CycleRecord(
                startedAt: cycle.startedAt,
                endedAt: cycle.endedAt,
                focusedSeconds: cycle.focusedSeconds,
                restedSeconds: cycle.restedSeconds,
                snoozeCount: 0,
                outcome: CycleOutcome(rawValue: cycle.outcome) ?? .completed
            )
        }
    }

    private func rearm() {
        do {
            try ScreenTimeShared.arm()
            lastError = nil
        } catch {
            lastError = "TWNI couldn't start counting app use: \(error.localizedDescription)"
        }
    }
}
#endif
