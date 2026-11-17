#!/bin/zsh
set -euo pipefail
PROJECT_DIR=${0:A:h}
STAGE_DIR=$(mktemp -d /private/tmp/susu-build.XXXXXX)
trap 'rm -rf "$STAGE_DIR"' EXIT
APP_DIR="$STAGE_DIR/溯溯.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
swiftc -swift-version 5 -O -target "$(uname -m)-apple-macosx13.0" -module-cache-path /private/tmp/susu-desktop-module-cache \
  -framework AppKit "$PROJECT_DIR/Sources/DesktopBounds.swift" "$PROJECT_DIR/Sources/main.swift" \
  -o "$APP_DIR/Contents/MacOS/SusuDesktop"
cp -R -X "$PROJECT_DIR/Assets/frames" "$APP_DIR/Contents/Resources/"
cp -R -X "$PROJECT_DIR/Assets/layers" "$APP_DIR/Contents/Resources/"
if [[ -f "$PROJECT_DIR/Assets/AppIcon.icns" ]]; then
  cp -X "$PROJECT_DIR/Assets/AppIcon.icns" "$APP_DIR/Contents/Resources/"
fi
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SusuDesktop</string>
<key>CFBundleIdentifier</key><string>local.zinian.susu.desktop</string>
<key>CFBundleName</key><string>溯溯</string>
<key>CFBundleDisplayName</key><string>溯溯</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
ditto --norsrc "$APP_DIR" "$PROJECT_DIR/溯溯.app"
ditto -c -k --norsrc --keepParent "$APP_DIR" "$PROJECT_DIR/溯溯桌面版-1.2.zip"
print "Built: $PROJECT_DIR/溯溯.app"
