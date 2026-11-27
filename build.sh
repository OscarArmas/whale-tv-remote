#!/usr/bin/env bash
# Builds Whale Remote with the macOS SDK (Command Line Tools or Xcode)
# and produces dist/WhaleRemote-<VERSION>.dmg.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/WhaleRemote"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
APP="$DIST/Whale Remote.app"
VERSION="1.9.3"
BUILD_NUM="13"
DMG="$DIST/WhaleRemote-${VERSION}.dmg"
ARCH="$(uname -m)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$BUILD" "$DIST"
mkdir -p "$BUILD" "$DIST"

swiftc -parse-as-library \
  -target "${ARCH}-apple-macosx13.0" \
  -sdk "$SDK" \
  -framework SwiftUI -framework AppKit -framework Foundation \
  "$SRC/WhaleRemoteApp.swift" \
  "$SRC/ContentView.swift" \
  "$SRC/RemoteViewModel.swift" \
  "$SRC/SsdpClient.swift" \
  "$SRC/DlnaRemote.swift" \
  "$SRC/RemoteKeys.swift" \
  "$SRC/UpnpHttp.swift" \
  "$SRC/AppVersion.swift" \
  -o "$BUILD/WhaleRemote.bin"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/WhaleRemote.bin" "$APP/Contents/MacOS/Whale Remote"
chmod +x "$APP/Contents/MacOS/Whale Remote"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Whale Remote</string>
	<key>CFBundleIdentifier</key>
	<string>com.local.WhaleRemote</string>
	<key>CFBundleName</key>
	<string>Whale Remote</string>
	<key>CFBundleDisplayName</key>
	<string>Whale Remote</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD_NUM}</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
		<key>NSAllowsLocalNetworking</key>
		<true/>
	</dict>
	<key>NSLocalNetworkUsageDescription</key>
	<string>Whale Remote looks for the TV on your Wi-Fi to send remote-control key presses.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" || true

STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
hdiutil create -volname "Whale Remote ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "Done: $DMG"
