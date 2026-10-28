#!/bin/sh
set -eu

cd "$CI_PRIMARY_REPOSITORY_PATH"
icon_alpha=$(/usr/bin/sips -g hasAlpha TWNI/Assets.xcassets/AppIcon.appiconset/AppIcon.png | /usr/bin/awk '/hasAlpha:/{print $2}')
if [ "$icon_alpha" != no ]; then
    echo "The App Store PNG icon must be opaque and have no alpha channel." >&2
    exit 1
fi
/usr/bin/plutil -lint TWNI/PrivacyInfo.xcprivacy
swift test --package-path CoreTests
