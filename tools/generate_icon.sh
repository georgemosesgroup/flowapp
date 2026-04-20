#!/usr/bin/env bash
# Render the Flow AppIcon set from scratch.
#
# Usage: desktop/tools/generate_icon.sh
#
# Produces the PNGs at every size the `AppIcon.appiconset/Contents.json`
# manifest references (16/32/64/128/256/512/1024) and drops them into
# the asset catalog. Run whenever the brand colours change or the
# bar-chart silhouette in `generate_icon.swift` is tweaked.

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$DIR/../macos/Runner/Assets.xcassets/AppIcon.appiconset"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

echo "→ rendering 1024×1024 master"
swift "$DIR/generate_icon.swift" "$STAGING/app_icon_1024.png"

echo "→ downscaling to 16/32/64/128/256/512"
for size in 16 32 64 128 256 512; do
    sips -z "$size" "$size" \
        "$STAGING/app_icon_1024.png" \
        --out "$STAGING/app_icon_${size}.png" >/dev/null
done

echo "→ installing into $OUT_DIR"
for size in 16 32 64 128 256 512 1024; do
    install -m 0644 "$STAGING/app_icon_${size}.png" "$OUT_DIR/"
done

echo "done. re-run \`flutter run -d macos\` (or hot restart) to pick up."
