# TWNI - 20-20-20 Eye Protection

A SwiftUI multiplatform app that helps protect your eyes using the 20-20-20 rule: every 20 minutes, take a 20-second break to look at something 20 feet away.

## Features

### Core Functionality

- **Automatic Screen Time Tracking** - Monitors your screen usage automatically in the background
- **Break Reminders** - Full-screen overlay prompts you to take breaks at the right time
- **Two Timer Modes**
  - **Auto Mode** - Classic 20-20-20 rule (20 min work, 20 sec break)
  - **Manual Mode** - Customize your interval and break duration
- **Statistics Dashboard** - Track your screen time, breaks taken, and compliance over time with interactive charts

### macOS-Specific

- **Menu Bar Integration** - Quick access to timer status and controls from the menu bar
- **Idle Detection** - Automatically pauses tracking when you're away from your computer (30+ seconds of inactivity)

### iOS-Specific

- **App Blocking** - Optional enforcement mode that blocks selected apps during breaks (requires Screen Time API authorization)

## Requirements

- **iOS** 18.0 or later
- **macOS** 15.0 (Sequoia) or later
- Xcode 16.0+ for building

## Building

```bash
# Build for macOS (primary development target)
xcodebuild -scheme TWNI -destination 'platform=macOS' build

# Clean build
xcodebuild -scheme TWNI -destination 'platform=macOS' clean build
```

> **Note**: No iOS Simulator SDK is installed on the development machine. iOS-specific code is verified via the macOS multiplatform target.

## Technical Stack

- **SwiftUI** - Modern declarative UI framework
- **SwiftData** - Data persistence for sessions and break records
- **Swift Charts** - Interactive statistics visualizations
- **Observation Framework** - Modern `@Observable` pattern (not `ObservableObject`)
- **FamilyControls** (iOS) - App blocking during breaks
- **MenuBarExtra** (macOS) - Native menu bar integration

## Project Structure

```
TWNI/
├── TWNIApp.swift              # App entry point, scenes, ModelContainer
├── ContentView.swift          # Tab navigation + break overlay
├── Services/
│   └── TimerManager.swift     # Core state machine (auto-tracking)
├── Views/
│   ├── DashboardView.swift    # Main timer interface
│   ├── BreakOverlayView.swift # Full-screen break screen
│   ├── StatsView.swift        # Statistics and charts
│   └── SettingsView.swift     # Timer and app configuration
├── Models/
│   ├── ScreenSession.swift    # SwiftData model for work sessions
│   └── BreakRecord.swift      # SwiftData model for breaks
└── Platform/
    ├── macOS/
    │   ├── MenuBarView.swift       # Menu bar popover
    │   └── MacActivityDetector.swift # Idle detection
    └── iOS/
        └── AppBlockingService.swift # FamilyControls integration
```

## Architecture Highlights

### State Machine

The app uses a three-state timer managed by `TimerManager`:

1. **disabled** - Timer is off
2. **active** - Tracking screen time, counting up to break interval
3. **breakActive** - Break time, counting down break duration

The timer auto-starts on app launch and runs continuously in auto or manual mode.

### Data Persistence

SwiftData models track:

- `ScreenSession` - Work intervals with start/end times
- `BreakRecord` - Break events with completion status

### Background Handling

- On backgrounding, a local notification is scheduled for the next break
- On foregrounding, elapsed time recalculates from the tracking start timestamp

## Development Notes

- Platform-specific code uses `#if os(iOS)` / `#if os(macOS)` compile-time checks
- The `.pbxproj` file uses handcrafted IDs with prefixed patterns (AA/AB/AC/etc.)
- FamilyControls entitlement is not in the entitlements plist (requires dev signing)
- Idle detection on macOS uses a silent `idlePaused` flag without changing visible state

## License

[Add your license here]

## Author

**Bautista Pessagno**

- GitHub: https://github.com/BautistaPessagno
- Email: bautista.pessagno@gmail.com
- Website: https://www.bpessagno.com
