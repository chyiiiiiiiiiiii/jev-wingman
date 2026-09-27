#!/bin/bash
# Build Wingman, put it in /Applications (Launchpad, Spotlight, login items expect it there), relaunch.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
pkill -x Wingman || true
rm -rf /Applications/Wingman.app
cp -R build/Wingman.app /Applications/Wingman.app
open /Applications/Wingman.app
echo "installed /Applications/Wingman.app"
