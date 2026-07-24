---
name: release-mac-media-keys
description: Cut an official release of MacMediaKeys - version bump, commit, notarize, staple, tag, push, GitHub release
---

Ships a new version of MacMediaKeys end to end: bump version, commit, build a
notarized+stapled Release build, tag, push, and create the GitHub release
(which auto-triggers the Homebrew cask update via
`.github/workflows/update-homebrew-cask.yml`).

## One-time setup (already done as of 2026-07-24, skip unless it stops working)

Notarization needs a `notarytool` keychain profile named `mac-media-keys` in
the **local login keychain** — not the same as whatever Xcode itself may show
in Keychain Access under a name like `com.apple.gke.notary.tool` (that's
Xcode's own internal item and is NOT readable by `xcrun notarytool
--keychain-profile`, even though it looks similar). If `xcrun notarytool
history --keychain-profile mac-media-keys` fails, the user needs to run,
themselves, in an interactive terminal (needs an app-specific Apple ID
password from appleid.apple.com):

```bash
xcrun notarytool store-credentials "mac-media-keys" \
  --apple-id <their-apple-id> --team-id C7U9V3BCYY --password <app-specific-password>
```

This can't be done non-interactively / on the user's behalf.

## Steps

1. **Decide the version bump** (semver: patch for fixes, minor for new features).

2. **Bump `MARKETING_VERSION`** in `MacMediaKeys.xcodeproj/project.pbxproj` — it
   appears twice (Debug and Release build configs). Both must match:
   ```bash
   sed -i '' 's/MARKETING_VERSION = OLD;/MARKETING_VERSION = NEW;/' MacMediaKeys.xcodeproj/project.pbxproj
   ```
   Leave `CURRENT_PROJECT_VERSION` at `1` (it's never been bumped across releases).

3. **Commit the code changes + version bump together**, in one commit. Follow
   the existing convention (see `git log`): a descriptive summary ending with
   `(vX.Y.Z)` in the subject line. Example from a past release:
   `Fix Automation permission prompt never appearing (v1.0.9)`.

4. **Run the release script** to build, notarize, staple, and produce the
   final zip:
   ```bash
   .claude/skills/release-mac-media-keys/release.sh X.Y.Z
   ```
   This takes several minutes (notarization submission + wait). It fails loudly
   if the built app's version doesn't match what you passed in (usually means
   step 2 was missed or the build is stale).

5. **Tag and push**:
   ```bash
   git tag vX.Y.Z
   git push origin main
   git push origin vX.Y.Z
   ```
   Tags in this repo are lightweight (not annotated) — `git tag vX.Y.Z` with no
   `-m` matches existing tags.

6. **Create the GitHub release**, attaching the zip the script produced
   (`build/DerivedData/Build/Products/Release/MacMediaKeys-X.Y.Z.zip`):
   ```bash
   gh release create vX.Y.Z "build/DerivedData/Build/Products/Release/MacMediaKeys-X.Y.Z.zip" \
     --title "vX.Y.Z" --notes "..."
   ```
   Write release notes describing user-facing changes — see past releases
   (`gh release view vX.Y.Z-1`) for tone/format.

7. **Verify the Homebrew cask workflow ran automatically**:
   ```bash
   gh run list --limit 3
   ```
   Should show `Update Homebrew Cask` as `completed success` for the new tag,
   triggered by the `release: published` event. No manual action needed.

## Gotchas

- The zip must be named `MacMediaKeys-X.Y.Z.zip` and be the **first** release
  asset — `update-homebrew-cask.yml` reads `assets[0].browser_download_url`.
- Don't skip notarization silently — Gatekeeper will show an "unidentified
  developer" warning for unnotarized zips. If credentials genuinely aren't
  available, say so explicitly and ask before shipping unnotarized.
- `release.sh` uses a fixed `-derivedDataPath ./build/DerivedData` (not
  Xcode's default hashed DerivedData path) so the output path is predictable
  across runs.
