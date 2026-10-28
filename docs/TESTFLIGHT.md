# TestFlight on iPhone

TWNI uses the existing Xcode Cloud `default` workflow for internal testing.

## Delivery path

```text
PR merged into main
  -> Xcode Cloud clones main
  -> ci_scripts/ci_post_clone.sh runs the core regression tests
  -> Archive - iOS builds the shared TWNI scheme
  -> TestFlight Internal Testing distributes the iOS archive to group yo
  -> Open TWNI in the TestFlight app on the iPhone and tap Install or Update
```

The workflow watches changes to `main`. Its iOS distribution preparation is
`TestFlight (Internal Testing Only)`, and its iOS post-action selects the existing
`yo` group. That group contains the account holder's existing internal tester.
The separate external-testing workflow is not used for this path.

The project uses team `CX6Q34K8F6` and bundle ID `com.twni.app`. Version 2.0 starts
with local build number 46; Xcode Cloud assigns its own increasing build numbers.
The shared scheme is committed under `TWNI.xcodeproj/xcshareddata/xcschemes/`.
iOS uses `TWNI-iOS.entitlements`; macOS keeps the App Sandbox entitlement.
The current app uses no non-exempt encryption, declared in the generated Info.plist.
The bundled privacy manifest declares app-local UserDefaults usage with reason
`CA92.1`. The PNG app icon is opaque; the post-clone script checks for an alpha
channel before spending time on tests and archives.

## Check a delivery

1. In App Store Connect, open TWNI > Xcode Cloud > Builds. Confirm the build is
   for the merged `main` commit, the core tests passed, and the iOS archive and
   TestFlight post-action succeeded.
2. Open TWNI > TestFlight > iOS. Wait for Apple to finish processing the new
   version 2.0 build, then check that it is available in the internal `yo` group.
   A successful local unsigned archive alone does not verify cloud signing,
   upload, processing, or installation.
3. On the iPhone, use TestFlight with the existing tester's Apple Account. Open
   TWNI and choose Install or Update. The iPhone must run iOS 18 or later.

## Smoke test on the phone

- Complete onboarding, allow notifications, and start a screen session.
- Put the app in the background. Confirm a reminder arrives while using another app.
- Choose Rest my eyes and finish the guided break. Reopen the app and confirm one
  completed break was recorded.
- In Standard mode, snooze twice. The next reminder must not offer another snooze.
  An old notification's rejected Snooze action must not create a completed break.
- Finish a break in the background, then tap Eye break done. This must open the app
  without starting another break.
- Try Skip, Strict mode, and reopening after the app was terminated. Check that
  ignored reminders are not recorded as completed breaks.

## Local validation

```sh
swift test --package-path CoreTests
xcodebuild -project TWNI.xcodeproj -scheme TWNI \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/TWNI-iOS.xcarchive CODE_SIGNING_ALLOWED=NO archive
xcodebuild -project TWNI.xcodeproj -scheme TWNI \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Apple references: [Xcode Cloud distribution through TestFlight](https://developer.apple.com/documentation/xcode/distributing-your-xcode-cloud-builds-through-testflight)
and [custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts).
