# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build for macOS (primary development target)
xcodebuild -scheme TWNI -destination 'platform=macOS' build

# Clean build
xcodebuild -scheme TWNI -destination 'platform=macOS' clean build
```

No iOS Simulator SDK is installed on this machine. Verify iOS-specific code compiles via the macOS multiplatform target (the project uses `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` with `SDKROOT = auto`). There are no tests or linting configured.

## Project Overview

**TWNI** is a 20-20-20 eye protection app (SwiftUI, multiplatform: iOS 18.0 + macOS 15.0). It auto-tracks screen time and prompts users to take eye breaks. On iOS, it can optionally block apps during breaks via FamilyControls.

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

### Idle Detection (macOS only)
`MacActivityDetector` polls `CGEventSource.secondsSinceLastEventType` every second. When idle >30s, it sets `TimerManager.idlePaused = true` which silently stops incrementing elapsed time without changing the visible state.

### App Blocking (iOS only)
`AppBlockingService` uses `FamilyControls` + `ManagedSettings` behind `#if canImport(FamilyControls)` guards. It blocks selected apps when a break starts and unblocks when the break ends. The FamilyControls entitlement is **not** in the entitlements plist (it requires dev signing); the feature is hidden in UI when unavailable.

### Data Flow
- `TWNIApp` creates `TimerManager` as `@State` and passes it down via init parameters (not environment)
- SwiftData `ModelContainer` with `ScreenSession` and `BreakRecord` models
- `ModelContext` is injected into `TimerManager` via `configure(modelContext:)`

### Platform Separation
All platform-specific code uses `#if os(iOS)` / `#if os(macOS)` compile-time checks. macOS has a `MenuBarExtra` scene with a status popover. iOS has the `AppBlockingService`.

## Key Patterns

- **`@Observable` (not `ObservableObject`)** — The codebase uses the modern Observation framework. Views take `TimerManager` as a plain `var`, not `@ObservedObject`.
- **Handcrafted pbxproj** — File IDs use prefixed patterns: `AA` (build files), `AB` (file refs), `AC` (product refs), `AD` (frameworks), `AE` (groups), `AF` (targets), `B0` (project), `B1` (config lists), `B2` (configs). Add new files following this convention.
- **`Swift.min()`/`Swift.max()`** — In the `Int` extension at the bottom of `TimerManager.swift`, `min()`/`max()` must be qualified with `Swift.` to avoid resolving to the instance method.
- **Background handling** — When the app backgrounds, a local notification is scheduled for the remaining interval time. On foreground, `handleForeground()` runs a while-loop that reconciles multiple interval+break cycles that may have elapsed in the background (not just one). This is the most complex piece of timer logic.
- **Settings via UserDefaults** — `timerMode`, `intervalMinutes`, `breakDurationSeconds`, `soundEnabled` are stored as UserDefaults. The computed properties in `TimerManager` read/write directly (no AppStorage).
- **Design system** — Monochrome theme using named colors from Assets.xcassets: `monoAccent`, `monoCard`, `monoBorder`, `monoPrimary`, `monoSecondary`. Reusable styles in `MonochromeCardModifier.swift` (`.monochromeCard()` modifier, `MonochromePrimaryButtonStyle`, `MonochromeSecondaryButtonStyle`).
- **Timers use Combine** — `Timer.publish(every:on:in:)` with `.autoconnect().sink {}`, not async/await or `Task.sleep`. `NotificationService` is `@unchecked Sendable` (not `@Observable`) with `@preconcurrency import UserNotifications`.
- **Stub files** — `ScreenTimeProtocol.swift`, `MacScreenTimeReader.swift`, `iOSScreenTimeService.swift` are intentionally empty stubs from removed legacy code. They can be ignored.
