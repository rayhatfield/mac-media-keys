#!/bin/bash
# Builds, notarizes, staples, and zips a Release build of MacMediaKeys for
# a GitHub release. Does NOT commit, tag, push, or create the GitHub release
# itself -- those steps involve judgement (commit message, release notes)
# and should be done by whoever/whatever is driving this script.
#
# Prerequisites:
# - MARKETING_VERSION in MacMediaKeys.xcodeproj/project.pbxproj already
#   bumped (both Debug and Release configs) and committed.
# - A notarytool keychain profile named "mac-media-keys" already stored
#   (one-time setup): `xcrun notarytool store-credentials "mac-media-keys" \
#     --apple-id <apple-id> --team-id C7U9V3BCYY --password <app-specific-password>`
#
# Usage: release.sh <version>   e.g. release.sh 1.1.2

set -euo pipefail

VERSION="${1:?Usage: release.sh <version> (e.g. 1.1.2)}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DERIVED_DATA="$REPO_ROOT/build/DerivedData"
RELEASE_APP="$DERIVED_DATA/Build/Products/Release/MacMediaKeys.app"
OUT_DIR="$DERIVED_DATA/Build/Products/Release"
NOTARY_PROFILE="mac-media-keys"

echo "==> Building Release configuration..."
cd "$REPO_ROOT"
xcodebuild -project MacMediaKeys.xcodeproj -scheme MacMediaKeys -configuration Release \
  -derivedDataPath "$DERIVED_DATA" build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:" || true

if [ ! -d "$RELEASE_APP" ]; then
  echo "ERROR: build did not produce $RELEASE_APP" >&2
  exit 1
fi

BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$RELEASE_APP/Contents/Info.plist")
if [ "$BUILT_VERSION" != "$VERSION" ]; then
  echo "ERROR: built app reports version $BUILT_VERSION, expected $VERSION." >&2
  echo "Did you forget to bump MARKETING_VERSION in project.pbxproj (both Debug and Release configs)?" >&2
  exit 1
fi

UNSTAPLED_ZIP="$OUT_DIR/MacMediaKeys-$VERSION-unstapled.zip"
FINAL_ZIP="$OUT_DIR/MacMediaKeys-$VERSION.zip"
rm -f "$UNSTAPLED_ZIP" "$FINAL_ZIP"

echo "==> Zipping for notarization submission..."
(cd "$OUT_DIR" && ditto -c -k --sequesterRsrc --keepParent MacMediaKeys.app "$UNSTAPLED_ZIP")

echo "==> Submitting for notarization (this can take a few minutes)..."
xcrun notarytool submit "$UNSTAPLED_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$RELEASE_APP"

echo "==> Verifying with spctl..."
spctl -a -vv "$RELEASE_APP"

echo "==> Creating final release zip..."
(cd "$OUT_DIR" && ditto -c -k --sequesterRsrc --keepParent MacMediaKeys.app "$FINAL_ZIP")

echo ""
echo "Done. Notarized, stapled release zip:"
echo "  $FINAL_ZIP"
echo ""
echo "Next steps (not done by this script):"
echo "  git tag v$VERSION"
echo "  git push origin main && git push origin v$VERSION"
echo "  gh release create v$VERSION \"$FINAL_ZIP\" --title \"v$VERSION\" --notes \"...\""
echo ""
echo "The Homebrew cask tap updates automatically via .github/workflows/update-homebrew-cask.yml"
echo "when the GitHub release is published -- no manual action needed."
