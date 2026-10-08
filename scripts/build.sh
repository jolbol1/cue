#!/bin/zsh
# Builds dist/Cue.app. Optional environment:
#   CUE_UNIVERSAL=1   build for both Apple silicon and Intel
#   CUE_VERSION=1.2.3 stamp the marketing version (CFBundleShortVersionString)
#   CUE_BUILD=42      stamp the build number (CFBundleVersion)
#   CUE_SIGN_IDENTITY="Developer ID Application: …"  sign for distribution (default: ad-hoc)
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/cue-clang-cache"
SWIFT_CACHE="${TMPDIR:-/tmp}/cue-swift-cache"
FLAGS=(-c release --disable-sandbox --product Cue -Xswiftc -module-cache-path -Xswiftc "$SWIFT_CACHE")
if [[ -n "${CUE_UNIVERSAL:-}" ]]; then FLAGS+=(--arch arm64 --arch x86_64); fi
swift build "${FLAGS[@]}"
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)"
APP="$PWD/dist/Cue.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# SwiftPM records the deployment target as the SDK version, which runs the app in
# compatibility mode on newer macOS. Record the real SDK so Cue gets the current system design.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
vtool -set-build-version macos 14.0 "$SDK_VERSION" -replace -output "$APP/Contents/MacOS/Cue" "$BIN/Cue"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${CUE_VERSION:-}" ]]; then /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $CUE_VERSION" "$APP/Contents/Info.plist"; fi
if [[ -n "${CUE_BUILD:-}" ]]; then /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CUE_BUILD" "$APP/Contents/Info.plist"; fi
if [[ -f Resources/Cue.icns ]]; then cp Resources/Cue.icns "$APP/Contents/Resources/Cue.icns"; fi
IDENTITY="${CUE_SIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --sign - --identifier com.james.cue --entitlements Resources/Cue.entitlements "$APP"
else
  # Notarization requires the hardened runtime and a secure timestamp.
  codesign --force --sign "$IDENTITY" --options runtime --timestamp --identifier com.james.cue \
    --entitlements Resources/Cue.entitlements "$APP"
fi
echo "Built $APP"
