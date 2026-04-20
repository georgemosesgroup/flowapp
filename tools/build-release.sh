#!/usr/bin/env bash
# Build a local release of Flow for macOS.
#
# Usage:
#   tools/build-release.sh                  # ad-hoc signed, for
#                                             bundling to testers
#   SIGNING_IDENTITY="Developer ID Application: George Moses (TEAMID)" \
#     tools/build-release.sh                # signed with Apple cert,
#                                             ready for notarization
#   NOTARIZE=1 tools/build-release.sh       # also runs notarytool +
#                                             stapler (needs SIGNING_IDENTITY
#                                             + NOTARY_PROFILE env vars)
#
# Outputs:
#   dist/Flow.app
#   dist/Flow-<version>-<build>.dmg
#   dist/Flow-<version>-<build>.zip   (for Sparkle-style update feeds later)
#
# Requirements:
#   - Xcode CLI tools (`xcodebuild`, `codesign`)
#   - Flutter 3.38+ (Dart 3.10)
#   - `create-dmg` for nice DMG packaging (`brew install create-dmg`);
#     falls back to `hdiutil` if create-dmg isn't on PATH.
#   - For notarization: `xcrun notarytool` needs a stored credential
#     profile — run `xcrun notarytool store-credentials flow-release`
#     once interactively to set it up, then pass `NOTARY_PROFILE=flow-release`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# ── Parse version from pubspec.yaml ────────────────────────────────
VERSION_LINE="$(grep '^version:' pubspec.yaml)"
VERSION="$(echo "$VERSION_LINE" | sed -E 's/version: *([0-9.]+)\+([0-9]+)/\1/')"
BUILD="$(echo "$VERSION_LINE" | sed -E 's/version: *([0-9.]+)\+([0-9]+)/\2/')"
echo "▶︎ Building Flow $VERSION ($BUILD)"

# ── Clean slate ────────────────────────────────────────────────────
DIST="$REPO_ROOT/dist"
rm -rf "$DIST"
mkdir -p "$DIST"

# ── Flutter release build ──────────────────────────────────────────
flutter clean
flutter pub get
flutter build macos --release \
    --build-name="$VERSION" \
    --build-number="$BUILD"

SRC_APP="$REPO_ROOT/build/macos/Build/Products/Release/Flow.app"
if [[ ! -d "$SRC_APP" ]]; then
    echo "✗ Expected build output not found: $SRC_APP"
    echo "  Double-check that PRODUCT_NAME in AppInfo.xcconfig is 'Flow'."
    exit 1
fi

DST_APP="$DIST/Flow.app"
cp -R "$SRC_APP" "$DST_APP"

# ── Code-signing ───────────────────────────────────────────────────
# No identity passed → ad-hoc sign (works on this Mac + any tester
# willing to right-click → Open). A real Developer ID identity
# unlocks Gatekeeper and is a prereq for notarization.
#
# Hardened Runtime nuance: --options=runtime turns on library
# validation, which at load time refuses any framework whose Team ID
# doesn't match the process's Team ID. For ad-hoc signing (no Team
# ID) that produces dyld errors at launch on testers' Macs ("mapping
# process and mapped file (non-platform) have different Team IDs"),
# even after a strip-quarantine. So we only enable Hardened Runtime
# when we have a real identity — notarization needs it, testers'
# ad-hoc launches break without skipping it.
IDENTITY="${SIGNING_IDENTITY:--}"
echo "▶︎ codesign identity: $IDENTITY"
SIGN_FLAGS=(--deep --force)
if [[ "$IDENTITY" != "-" ]]; then
    SIGN_FLAGS+=(--options=runtime)
fi
codesign "${SIGN_FLAGS[@]}" \
    --entitlements "$REPO_ROOT/macos/Runner/Release.entitlements" \
    --sign "$IDENTITY" \
    "$DST_APP"

codesign --verify --verbose=2 "$DST_APP" || true
echo "▶︎ signed: $DST_APP"

# ── Optional notarization ──────────────────────────────────────────
if [[ "${NOTARIZE:-0}" == "1" ]]; then
    PROFILE="${NOTARY_PROFILE:-flow-release}"
    echo "▶︎ notarizing via profile: $PROFILE"
    NOTARY_ZIP="$DIST/Flow-notary.zip"
    ditto -c -k --keepParent "$DST_APP" "$NOTARY_ZIP"
    xcrun notarytool submit "$NOTARY_ZIP" \
        --keychain-profile "$PROFILE" \
        --wait
    xcrun stapler staple "$DST_APP"
    rm -f "$NOTARY_ZIP"
fi

# ── Package: DMG for end-user installs + zip for update feeds ──────
ZIP_NAME="Flow-$VERSION-$BUILD.zip"
DMG_NAME="Flow-$VERSION-$BUILD.dmg"

echo "▶︎ packaging $ZIP_NAME"
( cd "$DIST" && ditto -c -k --keepParent Flow.app "$ZIP_NAME" )

echo "▶︎ packaging $DMG_NAME"
if command -v create-dmg >/dev/null 2>&1; then
    create-dmg \
        --volname "Flow" \
        --window-size 540 360 \
        --icon-size 96 \
        --icon "Flow.app" 140 170 \
        --app-drop-link 400 170 \
        --no-internet-enable \
        "$DIST/$DMG_NAME" \
        "$DST_APP" >/dev/null
else
    echo "  create-dmg not installed; falling back to plain hdiutil"
    hdiutil create -volname "Flow" -srcfolder "$DST_APP" \
        -ov -format UDZO "$DIST/$DMG_NAME" >/dev/null
fi

# ── Summary ────────────────────────────────────────────────────────
echo ""
echo "✓ Built Flow $VERSION ($BUILD)"
echo "  App : $DST_APP"
echo "  DMG : $DIST/$DMG_NAME"
echo "  ZIP : $DIST/$ZIP_NAME"
echo ""
if [[ "$IDENTITY" == "-" ]]; then
    cat <<'EOF'
⚠︎  This is an AD-HOC build (no Apple Developer identity).
    On a tester's Mac, Gatekeeper will refuse to open it with a
    "Flow is damaged / cannot be opened" message. They can bypass
    it one of two ways:

      1. Right-click Flow.app → Open → Open (first launch only)
      2. Or run:
           xattr -d com.apple.quarantine /Applications/Flow.app

    For clean install on arbitrary Macs you need an Apple Developer
    account ($99/yr) and should re-run this script with
    SIGNING_IDENTITY + NOTARIZE=1 set.
EOF
fi
