#!/bin/zsh
# Build Robyty.app into ~/Applications and install a login LaunchAgent.
set -euo pipefail

REPO="${0:A:h:h}"
APP_DIR="${HOME}/Applications/Robyty.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
PLIST_LABEL="com.chriskipp.robyty"
PLIST_DEST="${HOME}/Library/LaunchAgents/${PLIST_LABEL}.plist"
LOG_DIR="${HOME}/Library/Logs/Robyty"

echo "→ Building Robyty (release)"
cd "${REPO}"
swift build -c release --product Robyty

BIN="${REPO}/.build/release/Robyty"
if [[ ! -x "${BIN}" ]]; then
  echo "Build failed: ${BIN} missing" >&2
  exit 1
fi

echo "→ Installing ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${APP_DIR}/Contents/Resources"
cp "${BIN}" "${MACOS_DIR}/Robyty"
cp "${REPO}/Info.plist" "${APP_DIR}/Contents/Info.plist"
if [[ -f "${REPO}/Assets/AppIcon.icns" ]]; then
  cp "${REPO}/Assets/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi
chmod +x "${MACOS_DIR}/Robyty"

# Ad-hoc sign so macOS will launch a local unsigned SwiftPM binary.
codesign --force --sign - --identifier "${PLIST_LABEL}" "${APP_DIR}" >/dev/null

echo "→ Login LaunchAgent (${PLIST_LABEL})"
mkdir -p "${LOG_DIR}"
cat >"${PLIST_DEST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>${APP_DIR}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "${PLIST_DEST}"

echo "→ Launching"
open -a "${APP_DIR}"
echo "Робити installed. Dock icon, menu-bar ring, hotkey ⌃⌥D."
