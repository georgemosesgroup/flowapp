#!/usr/bin/env bash
# Publish an already-built Flow release to production.
#
# Does the whole "ship it" pipeline in one pass:
#   1. rsync  dist/Flow-*.dmg + .zip   → $RELEASE_HOST:$RELEASE_DIR/
#   2. probe  the public URL over HTTPS (sanity check)
#   3. patch  /opt/flowapp/.env on the server in place
#             (idempotent: strips any previous DESKTOP_LATEST_* block
#             before appending the new one — rerunning doesn't
#             accumulate cruft)
#   4. restart the backend container so the new env loads
#   5. verify /api/v1/desktop/latest now returns the new version
#
# Once this exits cleanly, every Flow client running a build number
# strictly below the one you just shipped will see the UpdateBanner
# on its next poll (≤ 6 h — there's a boot probe too, so anyone who
# cmd-Q's and reopens will see it immediately).
#
# Usage:
#   # One-time in your shell profile — dedicated flowapp server
#   # (or set via GH Actions secret if publishing from CI):
#   export RELEASE_HOST=root@165.245.214.29
#
#   # Every release:
#   cd desktop
#   tools/build-release.sh
#   NOTES="Sidebar polish + update banner" tools/publish-release.sh
#
# Env knobs:
#   RELEASE_HOST   required ssh target (user@host)
#   RELEASE_DIR    where DMGs live on the server (default /srv/flow-downloads)
#   SERVER_REPO    /opt/flowapp path on the server (where .env lives)
#   PUBLIC_BASE    public URL prefix (default https://downloads.flow.mosesdev.com)
#   NOTES          one-line release notes surfaced in the UpdateBanner
#   MIN_BUILD      force-update floor — clients on build < MIN_BUILD
#                  get a banner with no "×" (use for security fixes only)
#   DRY_RUN=1      print every remote command instead of running it

set -euo pipefail

# ── Config ─────────────────────────────────────────────────────────
: "${RELEASE_HOST:?Set RELEASE_HOST=user@host — ssh target for the prod server}"
RELEASE_DIR="${RELEASE_DIR:-/srv/flow-downloads}"
SERVER_REPO="${SERVER_REPO:-/opt/flowapp}"
PUBLIC_BASE="${PUBLIC_BASE:-https://downloads.flow.mosesdev.com}"
NOTES="${NOTES:-}"
MIN_BUILD="${MIN_BUILD:-0}"
DRY_RUN="${DRY_RUN:-0}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

run_remote() {
    # Tiny helper — honours DRY_RUN and keeps the caller readable.
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "  [dry-run] ssh $RELEASE_HOST $*"
    else
        ssh -o BatchMode=yes "$RELEASE_HOST" "$@"
    fi
}

# ── Parse version from pubspec.yaml ────────────────────────────────
VERSION_LINE="$(grep '^version:' pubspec.yaml)"
VERSION="$(echo "$VERSION_LINE" | sed -E 's/version: *([0-9.]+)\+([0-9]+)/\1/')"
BUILD="$(echo "$VERSION_LINE" | sed -E 's/version: *([0-9.]+)\+([0-9]+)/\2/')"
DMG="dist/Flow-$VERSION-$BUILD.dmg"
ZIP="dist/Flow-$VERSION-$BUILD.zip"

if [[ ! -f "$DMG" ]]; then
    echo "✗ $DMG missing. Run tools/build-release.sh first."
    exit 1
fi
if [[ ! -f "$ZIP" ]]; then
    echo "✗ $ZIP missing. Run tools/build-release.sh first."
    exit 1
fi

echo "▶︎ Publishing Flow $VERSION ($BUILD)"
echo "  target: $RELEASE_HOST:$RELEASE_DIR"
echo "  public: $PUBLIC_BASE"
[[ "$DRY_RUN" == "1" ]] && echo "  (DRY RUN — no writes to the server)"

# ── 1. Ensure remote dir exists ────────────────────────────────────
run_remote "mkdir -p $RELEASE_DIR"

# ── 2. Upload ──────────────────────────────────────────────────────
# `--chmod=F644` — nginx runs as its own uid inside the container,
# so files must be world-readable regardless of the uid we rsync as.
# `--partial --progress` — a dropped connection mid-upload resumes
# instead of losing the whole 50 MB.
if [[ "$DRY_RUN" == "1" ]]; then
    echo "  [dry-run] rsync $DMG $ZIP $RELEASE_HOST:$RELEASE_DIR/"
else
    rsync -avz --partial --progress \
        --chmod=F644 \
        "$DMG" "$ZIP" \
        "$RELEASE_HOST:$RELEASE_DIR/"
fi

URL="$PUBLIC_BASE/Flow-$VERSION-$BUILD.dmg"
echo ""
echo "✓ Uploaded. Files live at:"
echo "  $URL"
echo "  $PUBLIC_BASE/Flow-$VERSION-$BUILD.zip"

# ── 3. Probe public URL ────────────────────────────────────────────
# HEAD through flowapp-caddy to confirm TLS + routing work before we
# touch .env — if caddy doesn't know about the subdomain yet we'd
# rather fail now than have clients find a broken Update button.
echo ""
echo "▶︎ probing $URL"
status="$(curl -s -o /dev/null -w '%{http_code}' -I "$URL" || true)"
case "$status" in
    200)
        echo "  HTTP 200 — reachable"
        ;;
    000)
        echo "  ⚠ couldn't reach host."
        echo "    → DNS not propagated, or caddy doesn't know about"
        echo "      downloads.flow.mosesdev.com yet. Check"
        echo "      /opt/flowapp/caddy/Caddyfile + docker compose logs caddy."
        exit 1
        ;;
    404)
        echo "  ⚠ HTTP 404 — nginx reached but file not served."
        echo "    → Volume mount probably not live. On the server:"
        echo "        cd $SERVER_REPO && docker compose -f docker-compose.prod.yml up -d nginx"
        exit 1
        ;;
    *)
        echo "  ⚠ HTTP $status — unexpected. Nginx logs on the server:"
        echo "      docker logs flowapp-nginx-1 --tail 50"
        exit 1
        ;;
esac

# ── 4. Patch .env on the server ────────────────────────────────────
# Build the block locally, then pipe it + a short update script to
# the server over one ssh call. Idempotent: drops any previous
# DESKTOP_LATEST_* / DESKTOP_AUTO_UPDATE block before appending,
# so rerunning this never accumulates duplicate keys.
echo ""
echo "▶︎ updating .env on server"

block="$(mktemp)"
{
    echo "# DESKTOP_AUTO_UPDATE — written by tools/publish-release.sh"
    echo "# Shipped $(date -u +'%Y-%m-%dT%H:%M:%SZ') from $(hostname)"
    echo "DESKTOP_LATEST_VERSION=$VERSION"
    echo "DESKTOP_LATEST_BUILD=$BUILD"
    echo "DESKTOP_LATEST_URL=$URL"
    [[ -n "$NOTES" ]] && echo "DESKTOP_LATEST_NOTES=$NOTES"
    [[ "$MIN_BUILD" != "0" ]] && echo "DESKTOP_LATEST_MIN_BUILD=$MIN_BUILD"
} > "$block"

if [[ "$DRY_RUN" == "1" ]]; then
    echo "  [dry-run] would write the following block to $SERVER_REPO/.env:"
    sed 's/^/      /' "$block"
    rm -f "$block"
else
    # Upload the new block to a temp file on the server, then apply
    # atomically. Two-step so a dropped ssh connection in the middle
    # can't leave .env in a half-written state.
    scp -o BatchMode=yes -q "$block" "$RELEASE_HOST:/tmp/flow-env-block"
    rm -f "$block"

    ssh -o BatchMode=yes "$RELEASE_HOST" bash -s -- "$SERVER_REPO" <<'SSHEOF'
set -euo pipefail
SERVER_REPO="$1"
cd "$SERVER_REPO"

if [[ ! -f .env ]]; then
    echo "  ✗ $SERVER_REPO/.env not found on server"
    exit 1
fi

# Timestamped backup — cheap insurance, easy rollback path.
cp .env ".env.bak.$(date +%s)"

# Strip any prior DESKTOP_LATEST_* / DESKTOP_AUTO_UPDATE block so
# rerunning this script doesn't pile up duplicate keys.
tmp="$(mktemp)"
grep -v -E '^(DESKTOP_LATEST_|# DESKTOP_AUTO_UPDATE|# Shipped )' \
    .env > "$tmp" || true

# Trim trailing blanks so our new block lands clean.
awk 'NR==FNR{if(NF)last=NR; next} FNR<=last' "$tmp" "$tmp" > .env
rm -f "$tmp"

# Append the new block (keeps file ending with a newline).
echo "" >> .env
cat /tmp/flow-env-block >> .env
rm -f /tmp/flow-env-block

echo "  ✓ .env updated"
SSHEOF
fi

# ── 5. Restart backend so it picks up the new env ──────────────────
# Backend reads DESKTOP_LATEST_* once at startup (os.Getenv in the
# handler); a restart is enough, no full `up -d` needed.
echo ""
echo "▶︎ restarting backend"
run_remote "cd $SERVER_REPO && docker compose -f docker-compose.prod.yml restart backend"

# Give it a beat to come back — the restart is ~2-3s, then the first
# /api/v1/desktop/latest hit needs to pass through cf → caddy → nginx.
[[ "$DRY_RUN" == "1" ]] || sleep 4

# ── 6. Verify: endpoint now returns the version we just shipped ────
if [[ "$DRY_RUN" != "1" ]]; then
    echo ""
    echo "▶︎ verifying https://api.flow.mosesdev.com/api/v1/desktop/latest"
    body="$(curl -fsS https://api.flow.mosesdev.com/api/v1/desktop/latest || true)"
    if [[ -z "$body" ]]; then
        echo "  ⚠ endpoint returned empty — backend may still be starting."
        echo "    Recheck in 10s:  curl -s https://api.flow.mosesdev.com/api/v1/desktop/latest"
    elif echo "$body" | grep -q "\"build\":$BUILD"; then
        echo "  ✓ endpoint reports build $BUILD"
    else
        echo "  ⚠ endpoint returned unexpected body:"
        echo "      $body"
        echo "    Clients won't see the banner until this reports build=$BUILD."
    fi
fi

echo ""
echo "✓ Flow $VERSION ($BUILD) shipped."
echo "  Clients on an older build will see the UpdateBanner on"
echo "  their next poll (≤ 6 h; immediate on next cmd-Q + reopen)."
