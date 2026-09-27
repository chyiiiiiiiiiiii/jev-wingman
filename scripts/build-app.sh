#!/bin/bash
# Build build/Wingman.app and sign it with a stable identity, so the Accessibility grant
# survives rebuilds (an ad-hoc signature changes every build and macOS forgets the grant).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Wingman
app=build/Wingman.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Wingman "$app/Contents/MacOS/Wingman"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$app/Contents/Resources/"

identity="${WINGMAN_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')}"
codesign --force --options runtime --sign "${identity:--}" "$app"
echo "built $app (signed with ${identity:-ad-hoc})"
