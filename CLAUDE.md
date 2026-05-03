# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build for macOS (primary development target)
xcodebuild -scheme TWNI -destination 'platform=macOS' build

# Clean build
xcodebuild -scheme TWNI -destination 'platform=macOS' clean build
```

No iOS Simulator SDK is installed on this machine. Verify iOS-specific code compiles via the macOS multiplatform target (the project uses `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` with `SDKROOT = auto`). The two iOS extension targets (`TWNIDeviceActivityMonitor`, `TWNIShieldConfiguration`) only build for `iphoneos`/`iphonesimulator` and are skipped during macOS builds. There are no tests or linting configured.

## Project Overview

**TWNI** is a 20-20-20 eye protection app (SwiftUI, multiplatform: iOS 18.0 + macOS 15.0). It auto-tracks screen time and prompts users to take eye breaks. On iOS, it can block apps during breaks and on recurring schedules via FamilyControls, DeviceActivity, and ManagedSettings.

## Architecture

### State Machine (`TimerManager.swift`)
The core is `TimerManager`, an `@MainActor @Observable` class with three states:
- **`disabled`** → **`active`** (via `enable()`, called automatically on `configure()`)
- **`active`** → **`breakActive`** (auto-triggered when interval expires)
- **`breakActive`** → **`active`** (after break completes or is skipped)

Two modes via `TimerMode` enum:
- `.auto` — hardcoded 20min interval / 20sec break (zero config)
- `.manual` — user-configured interval and break duration

The timer auto-starts on app launch. There is no manual start/stop/pause — only an enable/disable toggle.

### iOS Timer Behavior (pause-based)
On iOS, the timer only advances while the app is actively foregrounded. `handleiOSBackground()` stops the timer; `handleiOSForeground()` resumes from the saved `elapsedSeconds` without adding background wall-clock time. When returning to foreground, it also checks `SharedDefaults.isBreakActive` to pick up breaks triggered externally by the DeviceActivity monitor extension.

### macOS Timer Behavior (wall-clock)
On macOS, `handleMacOSForeground()` reconciles wall-clock background time with a while-loop catching up multiple interval+break cycles. `MacActivityDetector` polls `CGEventSource.secondsSinceLastEventType` every second; when idle >30s, it pauses the counter via `handleIdlePause()`/`handleIdleResume()`.

### App Blocking & Scheduling (iOS only)
Three layers handle iOS blocking:

1. **`AppBlockingService`** — in-app service using `FamilyControls` + `ManagedSettings`. Uses two `ManagedSettingsStore` instances (default for schedule shields, named `"twni.break"` for break shields) so they don't collide.
2. **`iOSScreenTimeService`** — coordinates `DeviceActivityCenter` registration. Registers each `BlockSchedule` as a `DeviceActivitySchedule` with a 20-minute usage threshold event. Manages authorization refresh and schedule sync.
3. **`DeviceActivityMonitorExtension`** (`TWNIDeviceActivityMonitor` target) — runs in the background. `intervalDidStart`/`intervalDidEnd` apply/remove schedule shields. `eventDidReachThreshold` applies break shields and writes break state to `SharedDefaults`.

A **`ShieldConfigurationExtension`** (`TWNIShieldConfiguration` target) customizes the overlay shown on blocked apps with context-aware messages (scheduled block vs eye break).

### Shared Code (`TWNI/Shared/`)
Code shared between the main app and both extensions:
- `SharedConstants.swift` — App Group ID and UserDefaults keys
- `SharedDefaults.swift` — App Group-backed `UserDefaults` wrapper for schedules, block reason, break state
- `ScheduleModels.swift` — `BlockSchedule`, `BlockReason`, `CategoryPreset`, `ScheduleTimeOfDay`

All shared data flows through the App Group `group.com.twni.app`.

### Data Flow
- `TWNIApp` creates `TimerManager`, `AppBlockingService`, and `iOSScreenTimeService` as `@State` and wires them together
- SwiftData `ModelContainer` with `ScreenSession` and `BreakRecord` models
- `ModelContext` is injected into `TimerManager` via `configure(modelContext:)`

### Platform Separation
All platform-specific code uses `#if os(iOS)` / `#if os(macOS)` compile-time checks. macOS has a `MenuBarExtra` scene with a status popover. iOS has blocking services, Screen Time extensions, and the scheduler UI.

## Key Patterns

- **`@Observable` (not `ObservableObject`)** — The codebase uses the modern Observation framework. Views take `TimerManager` as a plain `var`, not `@ObservedObject`.
- **Handcrafted pbxproj** — File IDs use prefixed patterns: `AA` (build files), `AB` (file refs), `AC` (product refs), `AD` (frameworks), `AE` (groups), `AF` (targets/build phases), `B0` (project), `B1` (config lists), `B2` (configs), `B3` (container item proxies), `B4` (target dependencies). Add new files following this convention.
- **`Swift.min()`/`Swift.max()`** — In the `Int` extension at the bottom of `TimerManager.swift`, `min()`/`max()` must be qualified with `Swift.` to avoid resolving to the instance method.
- **Separate ManagedSettingsStore instances** — Schedule shields use the default store; break shields use `ManagedSettingsStore(named: "twni.break")`. This prevents break end from clearing active schedule blocks.
- **Settings via UserDefaults** — `timerMode`, `intervalMinutes`, `breakDurationSeconds`, `soundEnabled` are stored as UserDefaults. Schedule/blocking data uses App Group-backed `SharedDefaults`.
- **Design system** — Monochrome theme using named colors from Assets.xcassets: `monoAccent`, `monoCard`, `monoBorder`, `monoPrimary`, `monoSecondary`, `monoTertiary`, `monoSurface`. Reusable styles in `MonochromeCardModifier.swift` (`.monochromeCard()` modifier, `MonochromePrimaryButtonStyle`, `MonochromeSecondaryButtonStyle`).
- **Timers use Combine** — `Timer.publish(every:on:in:)` with `.autoconnect().sink {}`, not async/await or `Task.sleep`. `NotificationService` is `@unchecked Sendable` (not `@Observable`) with `@preconcurrency import UserNotifications`.
- **Stub files** — `ScreenTimeProtocol.swift`, `MacScreenTimeReader.swift` are intentionally empty stubs from removed legacy code. They can be ignored.

## On-Device Validation

Full validation requires a real iPhone with correct provisioning (FamilyControls entitlement, App Group). Key scenarios to test:

1. **Authorization**: FamilyControls auth request, recovery of `isAuthorized` after relaunch
2. **Schedule lifecycle**: schedule start/end triggers shields, shields survive app kill
3. **Per-schedule selection**: each schedule uses its own `FamilyActivitySelection`
4. **Category presets**: toggling presets reflects in schedule editor UI
5. **Break trigger**: 20-minute usage threshold fires `eventDidReachThreshold`, break shields applied
6. **Break end**: break shields cleared after 20 seconds, schedule shields remain if active
7. **Shield overlay**: custom shield message shows correct reason (schedule vs break) and context
8. **Foreground sync**: returning to TWNI picks up break state set by extension
9. **Timer pause**: iOS timer does not advance while app is backgrounded
