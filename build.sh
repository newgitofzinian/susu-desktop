#!/bin/zsh
set -euo pipefail
PROJECT_DIR=${0:A:h}
RELEASE_DIR="$PROJECT_DIR/release"
mkdir -p "$RELEASE_DIR"
STAGE_DIR=$(mktemp -d /private/tmp/susu-build.XXXXXX)
trap 'rm -rf "$STAGE_DIR"' EXIT
APP_DIR="$STAGE_DIR/溯溯.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
swiftc -swift-version 5 -O -target "$(uname -m)-apple-macosx13.0" -module-cache-path /private/tmp/susu-desktop-module-cache \
  -framework AppKit -framework Security "$PROJECT_DIR/Sources/ChatSupport.swift" "$PROJECT_DIR/Sources/StudioState.swift" "$PROJECT_DIR/Sources/CompanionActivities.swift" "$PROJECT_DIR/Sources/CompanionStore.swift" "$PROJECT_DIR/Sources/TaskPlans.swift" "$PROJECT_DIR/Sources/Playground.swift" "$PROJECT_DIR/Sources/DesktopActions.swift" "$PROJECT_DIR/Sources/DesktopControls.swift" "$PROJECT_DIR/Sources/TaskBoard.swift" "$PROJECT_DIR/Sources/AlphaHitMask.swift" "$PROJECT_DIR/Sources/ActivitiesRoom.swift" "$PROJECT_DIR/Sources/ScarfRenderer.swift" "$PROJECT_DIR/Sources/SeasonArtwork.swift" "$PROJECT_DIR/Sources/SeasonDressing.swift" "$PROJECT_DIR/Sources/NestScene.swift" "$PROJECT_DIR/Sources/CloseupView.swift" "$PROJECT_DIR/Sources/StudioRoom.swift" "$PROJECT_DIR/Sources/ChatRoom.swift" "$PROJECT_DIR/Sources/DesktopChat.swift" "$PROJECT_DIR/Sources/DesktopBounds.swift" "$PROJECT_DIR/Sources/main.swift" \
  -o "$APP_DIR/Contents/MacOS/SusuDesktop"
swiftc -swift-version 5 -O -target "$(uname -m)-apple-macosx13.0" -module-cache-path /private/tmp/susu-desktop-module-cache "$PROJECT_DIR/Sources/ChatSupport.swift" "$PROJECT_DIR/Sources/StudioState.swift" "$PROJECT_DIR/Sources/CompanionActivities.swift" "$PROJECT_DIR/Sources/CompanionStore.swift" "$PROJECT_DIR/Sources/TaskPlans.swift" "$PROJECT_DIR/CLI/main.swift" -o "$APP_DIR/Contents/MacOS/susu"
cp -R -X "$PROJECT_DIR/Assets/frames" "$APP_DIR/Contents/Resources/"
cp -R -X "$PROJECT_DIR/Assets/home" "$APP_DIR/Contents/Resources/"
cp -R -X "$PROJECT_DIR/Assets/seasons" "$APP_DIR/Contents/Resources/"
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
<key>CFBundleShortVersionString</key><string>2.11</string>
<key>CFBundleVersion</key><string>19</string>
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
xattr -cr "$PROJECT_DIR/溯溯.app"
codesign --verify --deep --strict "$PROJECT_DIR/溯溯.app"
ditto -c -k --norsrc --keepParent "$APP_DIR" "$RELEASE_DIR/溯溯桌面版-2.11.zip"
print "Built: $PROJECT_DIR/溯溯.app"
print "Package: $RELEASE_DIR/溯溯桌面版-2.11.zip"
