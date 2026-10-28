# TWNI roadmap

The relaunch copies the format of screen-time apps (Opal, Brainrot, one sec) for eye health:
personal onboarding, a daily score, a streak, and a firm "look away" moment.
Research notes behind these decisions are summarized in the audit report shared with the team.

## Done in v2 (this branch)

- New timer engine (`TWNI/Core`), unit-tested: counts real screen time on macOS (idle, sleep, lock,
  video and calls handled), no fake breaks, correct day attribution, persisted across launches.
- Onboarding: hook, screen-hours question, symptoms, personal "mirror" number, one sourced fact,
  plan with break style (Gentle / Standard / Strict), how it works on this device, permission, first break.
- Break Score (0–100, explainable in one sentence) and streak with light days.
- Guided 20-second break with rotating look-far prompts and a blink cue; snooze (limited) and
  hold-to-skip; "hands off" verification on macOS.
- macOS: full-screen break on every display and Space, menu bar score/streak/controls, pause for
  30 min / 1 h / until tomorrow, launch at login fixed.
- iOS: screen sessions with background reminders whose actions (Rest / In 5 minutes / Skip) work.
- Accessibility: AA contrast, VoiceOver labels, Reduce Motion, 44 pt targets.

## Next

### 1. iOS app shields (the core Opal mechanic) — needs Apple approval first
Apply now: the Family Controls (Distribution) entitlement must be requested by the Account Holder for
the app **and each extension bundle ID**. 2026 forum reports show 1 day to 6+ weeks.

Targets to add (iOS only, all sharing an App Group such as `group.com.twni.app`):
- **DeviceActivityMonitor extension** — the real "20 minutes of phone use" trigger.
  Recommended design (from Apple forum guidance; threshold callbacks are unreliable on iOS 26.x):
  - Rolling one-shot activity per cycle: `startMonitoring(.cycle(n), during: <now … 23:59:59, no repeat>,
    events: [.due(n): DeviceActivityEvent(threshold: 20 min, includesPastActivity: false)])`.
    Empty app/category sets count all device use.
  - In `eventDidReachThreshold`, validate against a start timestamp stored in the App Group. If the
    callback is early, re-arm for the remainder. Then apply a shield and post a time-sensitive notification.
  - Backup ladder (20, 40, 60 … min on a daily schedule) to detect a dead monitor.
  - Split at midnight. The extension has a ~6 MB memory cap, so no SwiftData there.
- **ShieldConfiguration extension** — only icon, title, subtitle, colours and two buttons can be customised.
  Copy: "Eye break: look 6 m away for 20 s".
- **ShieldAction extension** — primary button: start the break (record timestamp, `.defer` to refresh the
  shield into "keep looking away… 20 s"), lift the shield once 20 s have passed. On iOS 26.5+,
  `openParentalControlsApp` can open TWNI for the guided break; fall back to a notification.
- `EyeTimerEngine` stays the source of truth for scoring; the extensions write cycle records to the App Group
  and the app imports them.

Avoid: monetizing the Screen Time API itself (App Review 4.10). Keep the core shield free.

### 2. Ambient surfaces (no approval needed; each needs a Widget Extension target)
- Live Activity / Dynamic Island: "next eye break in 12 min" during a session, and the 20 s countdown
  (use `Text(timerInterval:)`, no pushes needed; 8 h limit).
- Home and Lock Screen widgets: Break Score, streak, next break. Interactive "Rest now" button (App Intent).
- Time Sensitive notifications capability (no approval needed) so reminders can break through Focus,
  opt-in only.

### 3. Mac ↔ iPhone
- Sync cycle history via CloudKit (`CycleEntry` already has defaults on every property and a `device` field).
- When a Mac break starts, shield the iPhone for the same 20 s (LookAway Mirror does this).

### 4. Smart pause, round two (macOS)
- Camera in use (`AVCaptureDevice.isInUseByAnotherApplication`), screen sharing/recording, full-screen
  presentation via `CGWindowListCopyWindowInfo`, Focus filters (`SetFocusFilterIntent`).
- Short pre-break heads-up (10 s) with a "not now" that defers to the next natural pause.

### 5. Business model
- Core 20-20-20 free forever. Pro around $19.99–29.99/year plus lifetime (~$49.99); no weekly plans.
  Pro: Strict mode extras, cross-device shield, exercise library, long-term trends, widget themes.
- Paywall after the first completed break or on day 3, with a visible close, the price, and a trial
  reminder. Avoid the patterns that earn Opal/Brainrot bad reviews: hard paywalls, rating prompts before
  the price, trial-to-annual surprises, opaque scores.

### 6. Housekeeping
- Commit a shared scheme (`xcshareddata/xcschemes/TWNI.xcscheme`) and stop tracking `xcuserdata/`.
- Separate iOS and macOS entitlements files (`CODE_SIGN_ENTITLEMENTS[sdk=...]`) before adding Family Controls.
- Proper macOS app-icon sizes (all slots currently point at one 1024 px PNG).
- Manually verify on device: microphone and video detection inside the App Sandbox, the overlay above
  full-screen apps, and notification actions after the app was killed.
