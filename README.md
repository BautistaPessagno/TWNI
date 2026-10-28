# TWNI — eye breaks, the screen-time-app way

A SwiftUI app for iOS and macOS built around the 20-20-20 habit: every 20 minutes of screen time, look at
something about 6 m (20 ft) away for 20 seconds. It borrows the format of screen-time apps like Opal:
a quick personal onboarding, a daily **Break Score**, a **streak**, and a firm "look away" moment.

TWNI is a wellness tool, not a medical device. It measures breaks, not eyes.

## Features

### Everywhere
- **Onboarding** with a personal number (your yearly screen hours), one sourced fact, and your plan.
- **Guided 20-second breaks** with rotating look-far prompts and a blink cue at the end.
- **Break styles:** Gentle (tap to skip), Standard (hold to skip, two snoozes), Strict (no skipping).
- **Break Score (0–100):** the share of today's 20-minute screen blocks that ended with a rest.
  Stepping away on your own counts as a rest.
- **Streak:** days that reach your goal (default 70). Light days don't count either way.
- **Progress:** week of scores, breaks (rested / skipped / missed) and screen time.
- **The science** page with the sources behind every claim.

### macOS
- Lives in the menu bar with score, streak, countdown and quick controls.
- Counts screen time only while you're using the Mac. Locking the screen, sleeping, or 5 minutes away
  counts as a rest.
- **Smart pause:** holds breaks while the microphone is in use (calls) and keeps counting while a video plays.
- **Full-screen break** on every display and Space, above full-screen apps. In Standard and Strict mode the
  countdown only runs while your hands are off the keyboard and mouse.
- Pause for 30 minutes, 1 hour or until tomorrow. Open at login.

### iOS
- **Screen sessions:** iPhone doesn't let apps see your screen time without special Apple approval, so you
  start a session (30 min to 4 h) when you settle in. TWNI reminds you every 20 minutes, even in other apps.
- Reminder actions: Rest my eyes, In 5 minutes, Skip.
- App shields in the style of Opal are next; see [docs/ROADMAP.md](docs/ROADMAP.md).

## Requirements
- iOS 18.0+ / macOS 15.0+
- Xcode 16+

## Building and testing

```bash
xcodebuild -project TWNI.xcodeproj -scheme TWNI -destination 'platform=macOS' build
```

The timer, score and streak logic lives in `TWNI/Core` (Foundation only) and has unit tests:

```bash
cd CoreTests && swift test
```

For internal iPhone builds and the device smoke test, see [TestFlight](docs/TESTFLIGHT.md).

## Project structure

```
TWNI/
├── TWNIApp.swift              # Scenes; creates and configures TimerManager once
├── ContentView.swift          # Onboarding or tabs; iOS break overlay
├── Core/                      # Pure Swift, unit-tested (CoreTests/)
│   ├── EyeTimerEngine.swift   # Screen-time / break state machine
│   ├── BreakScore.swift       # Daily score, streak, day grouping
│   ├── ReminderPlanner.swift  # iOS reminder dates
│   └── EyeExercises.swift     # Break prompts
├── Models/CycleEntry.swift    # SwiftData record of each screen-time cycle
├── Services/
│   ├── TimerManager.swift     # Engine + clock + storage + notifications + settings
│   └── NotificationService.swift
├── Views/                     # Dashboard, Break overlay, Stats, Settings, Onboarding, Science
├── Components/                # Cards, buttons, score ring, hold-to-skip, motion lines
├── Platform/macOS/            # Presence monitor, full-screen overlay, menu bar
└── Extensions/TimeFormatting.swift
CoreTests/                     # Swift package that tests TWNI/Core
docs/ROADMAP.md
```

## Author

**Bautista Pessagno**

- GitHub: https://github.com/BautistaPessagno
- Email: bautista.pessagno@gmail.com
- Website: https://www.bpessagno.com
