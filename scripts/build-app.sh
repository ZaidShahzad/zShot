#!/bin/sh
# Builds build/zShot.app. Run from the repo root: scripts/build-app.sh [debug|release]
# Signs with the "zShot Development" certificate when it exists (see make-dev-cert.sh),
# so macOS keeps the Screen Recording permission across rebuilds.
set -eu

CONFIG="${1:-release}"
IDENTITY="${ZSHOT_SIGN_IDENTITY:-zShot Development}"
APP="build/zShot.app"

swift build -c "$CONFIG" --product zShot
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/zShot" "$APP/Contents/MacOS/zShot"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# No -v: a self-signed certificate is untrusted, and -v would hide it.
if security find-identity -p codesigning | grep -F "\"$IDENTITY\"" >/dev/null; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    cat >&2 <<EOF
warning: no "$IDENTITY" signing identity; signing ad hoc.
macOS treats each ad-hoc build as a new app, so Screen Recording permission resets on every build.
After rebuilding, run 'tccutil reset ScreenCapture io.github.zaidshahzad.zshot', quit any running zShot,
then open the new build and allow it again. To avoid this, run scripts/make-dev-cert.sh once.
EOF
    codesign --force --sign - "$APP"
fi

echo "Built $APP"
