# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and test

```bash
# Build for macOS (primary development target)
xcodebuild -project TWNI.xcodeproj -scheme TWNI -destination 'platform=macOS' build

# Clean build
xcodebuild -project TWNI.xcodeproj -scheme TWNI -destination 'platform=macOS' clean build

# Unit tests for the platform-independent logic (works on macOS and Linux)
cd CoreTests && swift test
```

No iOS Simulator SDK is installed on the main dev machine. Verify iOS-specific code compiles via the multiplatform target (`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`, `SDKROOT = auto`). There is no linting.

`CoreTests/` is a Swift package whose `Sources/TWNICore` is a symlink to `TWNI/Core`. The app target compiles those same files directly; the package only exists so the logic can be tested with `swift test`. Anything in `TWNI/Core` must stay Foundation-only (no SwiftUI, SwiftData, Combine, AppKit, UIKit).

## Project overview

**TWNI** is a 20-20-20 eye-break app (SwiftUI, multiplatform: iOS 18.0 + macOS 15.0), built in the format of screen-time apps like Opal: onboarding with a personal number, a daily Break Score, a streak, and a firm "look away" moment.

- **macOS:** menu bar app. Counts screen time only while the user is at the Mac, treats stepping away as a rest, holds breaks during calls, and shows the break full screen on every display.
- **iOS:** with Screen Time access, **automatic breaks**: DeviceActivity counts only the time spent in all apps or the selected ones (even with TWNI closed), then the apps are shielded until an eye break is done (see `docs/SCREEN_TIME.md`). Three extension targets in `ScreenTimeExtensions/` share `TWNI/Shared/ScreenTimeShared.swift` through the App Group `group.com.twni.app`. Without access, the user starts a **screen session** (timer-based reminders). Distribution needs Apple's Family Controls (Distribution) entitlement for the app and each extension.

## Architecture

### Core logic (`TWNI/Core`, pure Swift, unit-tested)
- `EyeTimerEngine` — value-type state machine. Phases: `off`, `focusing` (counting screen time), `resting(startedAt:)` (break running), `snoozed(until:)`. Fed `update(at:presence:)` once per second; returns `EyeTimerEvent`s (`breakStarted`, `snoozed`, `cycleEnded(CycleRecord)`). Codable, so it is saved to UserDefaults and restored on launch.
  - `Presence` = idle seconds, video playing, screen on, in a call.
  - Screen time counts only while input idle < 60 s (or video/call). Idle ≥ 5 min or screen off ≥ 60 s ends the cycle as a `natural` rest.
  - Ticks more than 15 s apart are a gap. `GapPolicy.away` (macOS) treats gaps as away (sleep); `GapPolicy.focus` (iOS sessions) assumes the user stayed on screens and records ignored reminders as `missed`.
  - Calls defer a due break until the call ends.
- `BreakScore` / `Streak` / `DayGrouping` — daily score = share of interval-sized blocks of screen time that ended with a rest (completed or natural), 0–100. Streak counts days at or above the goal; light days (< 3 blocks) don't count either way.
- `ReminderPlanner` — iOS notification dates that match the engine's `.focus` gap model.
- `EyeExerciseLibrary` — rotating look-far prompts plus a blink cue in the last 5 s. No medical claims.

### App layer
- `TimerManager` (`@MainActor @Observable`) owns the engine, the 1 s Combine ticker, settings, SwiftData persistence (`CycleEntry`), day rollover, iOS sessions and background notification scheduling, and on macOS the presence monitor and overlay. Created and configured once in `TWNIApp.init` (not in a view's `.task`), passed down via init parameters (not environment).
- Settings are **stored** properties with `didSet` that writes UserDefaults (so `@Observable` tracks them). Views bind with `@Bindable`. Keys `timerMode`, `intervalMinutes`, `breakDurationSeconds`, `soundEnabled` are kept from v1.
- `NotificationService` is the `UNUserNotificationCenterDelegate`; actions (Rest / In 5 minutes / Skip) route to `TimerManager`. macOS doesn't use notifications.
- SwiftData store is named `TWNI-v2` with one model, `CycleEntry`. v1 models (`ScreenSession`, `BreakRecord`) were dropped; their data isn't migrated. Container creation falls back to in-memory instead of crashing.

### Platform separation
All platform-specific code uses `#if os(iOS)` / `#if os(macOS)`. macOS-only files live in `Platform/macOS` and are wrapped in `#if os(macOS)`:
- `MacPresenceMonitor` — `CGEventSource` idle time, NSWorkspace sleep/wake/session notifications, `com.apple.screenIsLocked` (undocumented), `IOPMCopyAssertionsStatus` for video, CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere` for calls, and a `ProcessInfo` activity to stop App Nap from stalling the timer.
- `BreakOverlayController` — one borderless `NSPanel` per screen at `.screenSaver` level on all Spaces, hosting `BreakOverlayView`.
- `MenuBarView` / `MenuBarLabel`.

## Key patterns

- **`@Observable` (not `ObservableObject`)**. Views take `TimerManager` as a plain `var` (or `@Bindable var` when they bind settings).
- **Handcrafted pbxproj** — IDs use prefixed patterns: `AA` (build files), `AB` (file refs), `AC` (product refs), `AD` (frameworks), `AE` (groups), `AF` (targets), `B0` (project), `B1` (config lists), `B2` (configs). Add new files following this convention (next free: `AA000048`, `AB000050`, `AE000019`, `AF000040`).
- **`Swift.min()`/`Swift.max()`** — inside `Int` extensions, qualify `min`/`max` with `Swift.`.
- **Timers use Combine** — `Timer.publish(every:on:in:)` with `.autoconnect().sink {}`. `NotificationService` is `@unchecked Sendable` with `@preconcurrency import UserNotifications`.
- **Design system** — monochrome named colors in Assets.xcassets (`monoAccent`, `monoCard`, `monoBorder`, `monoPrimary`, `monoSecondary`, `monoTertiary`, `monoSurface`, `monoElevated`, `monoProgressFill`, `monoProgressTrack`). Secondary and tertiary text pass WCAG AA (≥ 4.5:1) on every surface; keep it that way. Reusable pieces: `.monochromeCard()`, `MonochromePrimaryButtonStyle`, `MonochromeSecondaryButtonStyle`, `CapsuleButtonStyle`, `ScoreRing`, `StreakBadge`, `InfoChip`, `HoldToSkipButton`.
- **Health copy** — never claim the app prevents or treats anything, or measures the eyes. Say "reminds", "Break Score" (not "Eye Score"). Every factual claim in `OnboardingView` must match a source listed in `ScienceView`.
- **Accessibility** — respect Reduce Motion (`MotionLinesView` freezes), give rings and badges VoiceOver labels/values, keep tap targets ≥ 44 pt.
