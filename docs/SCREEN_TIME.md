# Automatic eye breaks on iPhone (Screen Time)

This copies the mechanism Opal-style apps use: iOS counts the time spent in the
monitored apps, even with TWNI closed, then TWNI locks those apps until the user
rests their eyes.

## How it works

1. **Access.** The app asks for Screen Time access with
   `AuthorizationCenter.requestAuthorization(for: .individual)`. The user picks
   **All apps** or **Selected apps** (`FamilyActivityPicker`). The choice is stored
   in the App Group `group.com.twni.app`.
2. **Counting.** `ScreenTimeShared.arm()` starts a repeating day-long
   `DeviceActivitySchedule` with one event: *N minutes of use* of those apps
   (`includesPastActivity: false`, so it counts from now). With no apps listed, the
   event counts all device use. Locked phone time doesn't count.
3. **Lock.** When the threshold is reached, iOS wakes the **monitor extension**
   (`ScreenTimeExtensions/Monitor`). It checks the callback isn't early (a known
   iOS 26 issue: use can't outrun the clock, so an early one re-arms for the time
   left), shields the apps with `ManagedSettingsStore(named: "twni.break")` and
   sends a notification: "Time for an eye break".
4. **Break.** Two ways to unlock:
   - **On the shield** (`ShieldConfiguration` + `ShieldAction` extensions): tap
     "Start 20-second break", look away, then tap "Done". Done only works after the
     break length. A notification says when the time is up.
   - **In TWNI:** tap the notification, or "Guided break in TWNI" on the shield
     (an extension can't open the app, so it sends a notification). With the apps
     locked and TWNI open, the guided break starts by itself. Finishing or skipping
     it (if the break style allows) unlocks the apps.
5. **Again.** Finishing logs the cycle to the App Group, clears the shield and
   starts counting from zero. The app imports logged cycles into its history, so
   the Break Score and streak include them.

Without Screen Time access, iPhone falls back to screen sessions (timer-based
reminders).

## Targets

| Target | Bundle ID | Extension point |
|---|---|---|
| TWNIMonitor | `com.twni.app.DeviceActivityMonitor` | `com.apple.deviceactivity.monitor-extension` |
| TWNIShieldConfiguration | `com.twni.app.ShieldConfiguration` | `com.apple.ManagedSettingsUI.shield-configuration-service` |
| TWNIShieldAction | `com.twni.app.ShieldAction` | `com.apple.ManagedSettings.shield-action-service` |

All three and the app have the `com.apple.developer.family-controls` entitlement and
the App Group. `TWNI/Shared/ScreenTimeShared.swift` is compiled into all four.
The extensions are embedded only in the iOS build (`platformFilter = ios`).

## Before this can ship: Apple approval

- **Development builds work now**: run from Xcode on your own iPhone. The
  development Family Controls capability comes with the paid developer account.
  Screen Time doesn't work in the Simulator.
- **TestFlight and the App Store need the Family Controls (Distribution)
  entitlement**, requested by the Account Holder at
  https://developer.apple.com/contact/request/family-controls-distribution for the
  app **and each of the three extension bundle IDs**. Forum reports range from
  1 day to 6+ weeks.
- **Until it's approved, merging this into `main` breaks the Xcode Cloud ->
  TestFlight upload**, because App Store signing can't include the entitlement yet.

## Test on a device

1. Xcode: select your iPhone, run the TWNI scheme. Xcode registers the App Group and
   the three extension App IDs with automatic signing.
2. Settings > Automatic breaks > Allow Screen Time access > All apps > Turn on.
   For a quick test, set a custom rule of 5 minutes first.
3. Use other apps for 5 minutes. They should lock, and a notification should arrive.
4. On the shield: Start, wait, Done. The apps unlock; TWNI shows the completed break.
5. Repeat and use the notification instead: TWNI opens the guided break; finishing
   it unlocks the apps.
6. Check: locked-phone time doesn't count; Selected apps only counts those apps;
   Strict mode hides Skip in TWNI.

Unverified until tested on a device: whether "All apps" also shields TWNI itself
(if so, the shield's own Start/Done flow still unlocks), and whether the shield
unlocks immediately after Done or needs the app reopened.
