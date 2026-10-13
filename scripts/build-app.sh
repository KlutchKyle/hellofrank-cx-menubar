#!/usr/bin/env bash
# Builds "HelloFrank CX.app" from the Swift package.
#
#   scripts/build-app.sh            # build into build/
#   scripts/build-app.sh --install  # also copy to /Applications and launch
#
# Signs ad hoc by default. Set SIGN_IDENTITY to a "Apple Development: …"
# identity to keep Keychain access stable across rebuilds.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP_NAME="HelloFrank CX"
APP="build/${APP_NAME}.app"

swift build -c "$CONFIG" --product HelloFrankCX
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/HelloFrankCX" "$APP/Contents/MacOS/HelloFrankCX"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign "${SIGN_IDENTITY:--}" --timestamp=none "$APP"
codesign --verify "$APP"
echo "Built $APP ($(du -sh "$APP" | cut -f1))"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e "quit app \"${APP_NAME}\"" >/dev/null 2>&1 || true
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "$APP" /Applications/
  open "/Applications/${APP_NAME}.app"
  echo "Installed to /Applications and launched"
fi
