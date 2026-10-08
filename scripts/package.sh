#!/bin/zsh
# Packages dist/Cue.app into a drag-to-Applications disk image at dist/Cue-<version>.dmg.
# Requires dmgbuild (`pipx install dmgbuild`). Signs the image when CUE_SIGN_IDENTITY
# is a Developer ID identity; notarization happens separately in the release workflow.
set -euo pipefail
cd "${0:A:h:h}"
if ! command -v dmgbuild >/dev/null; then echo "dmgbuild is required: pipx install dmgbuild" >&2; exit 1; fi
VERSION="${CUE_VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" dist/Cue.app/Contents/Info.plist)}"
DMG="dist/Cue-$VERSION.dmg"
rm -f "$DMG"
dmgbuild -s scripts/dmg-settings.py -D app=dist/Cue.app "Cue $VERSION" "$DMG"
if [[ -n "${CUE_SIGN_IDENTITY:-}" && "$CUE_SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$CUE_SIGN_IDENTITY" --timestamp "$DMG"
fi
echo "Packaged $DMG"
