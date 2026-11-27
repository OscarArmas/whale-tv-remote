#!/usr/bin/env bash
# Builds Whale Remote with the macOS SDK (Command Line Tools or Xcode)
# and produces dist/WhaleRemote-<VERSION>.dmg.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/WhaleRemote"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
APP="$DIST/Whale Remote.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$SRC/Info.plist")"
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

cp "$SRC/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable Whale Remote' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.local.WhaleRemote' "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
hdiutil create -volname "Whale Remote ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "Done: $DMG"
