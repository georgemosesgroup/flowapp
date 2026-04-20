#!/usr/bin/env bash
# One-command Flow release — bump, build, publish, tag.
#
# Two modes:
#
#   Local (default) — this Mac builds + publishes directly.
#       tools/release.sh 1.0.1 "Sidebar polish + live update banner"
#     Bumps pubspec, runs build-release.sh + publish-release.sh,
#     commits + tags + pushes. You need SSH to prod in your shell
#     env (RELEASE_HOST set).
#
#   CI — tag-only; GitHub Actions does the build + publish on a
#        hosted macos-latest runner (wired up via bitbucket-pipelines.yml
#        that mirrors desktop/ → georgemosesgroup/flowapp on tag push).
#       tools/release.sh --ci 1.0.1 "Sidebar polish + live update banner"
#     Bumps pubspec, commits + tags + pushes to Bitbucket. Bitbucket
#     Pipelines mirrors to flowapp, GH Actions picks up and runs
#     tools/build-release.sh + tools/publish-release.sh itself.
#     No SSH or codesign state needed on this Mac — set up the GH
#     secrets once, then every release is hands-off after the push.
#
# Force-update floor (banner can't be dismissed below this build):
#     MIN_BUILD=17 tools/release.sh 1.0.2 "Security fix"
#     MIN_BUILD=17 tools/release.sh --ci 1.0.2 "Security fix"
#
# Env knobs for the LOCAL path (ignored in --ci):
#   RELEASE_HOST       ssh target for prod (required by publish)
#   SIGNING_IDENTITY   Developer ID for a notarizable build (optional)
#   NOTARIZE=1         run notarytool + stapler (needs SIGNING_IDENTITY)
#   SKIP_GIT=1         don't commit/tag/push — useful for reshipping
#                      an already-tagged build (rerun publish only)

set -euo pipefail

# ── Args ───────────────────────────────────────────────────────────
CI_MODE=0
if [[ "${1:-}" == "--ci" ]]; then
    CI_MODE=1
    shift
fi

if [[ $# -lt 1 ]]; then
    cat <<USAGE
Usage:
  tools/release.sh <new-version> [notes]          # local build + publish
  tools/release.sh --ci <new-version> [notes]     # tag + push, CI does the rest

Examples:
  tools/release.sh 1.0.1 "Sidebar polish + live update banner"
  tools/release.sh --ci 1.0.2 "Security fix"
USAGE
    exit 1
fi
NEW_VERSION="$1"
NOTES="${2:-Flow $NEW_VERSION}"
SKIP_GIT="${SKIP_GIT:-0}"
MIN_BUILD="${MIN_BUILD:-0}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# ── 1. Tree must be clean (we're about to commit + tag) ────────────
if [[ "$SKIP_GIT" != "1" ]]; then
    if ! git diff --quiet HEAD -- .; then
        echo "✗ working tree under desktop/ has uncommitted changes."
        echo "  commit or stash first, or rerun with SKIP_GIT=1."
        exit 1
    fi
fi

# ── 2. Bump pubspec.yaml ───────────────────────────────────────────
# The `+N` build number must strictly increase on every release Apple
# sees; we take whatever's in pubspec right now and add 1. The
# marketing version becomes whatever you passed in.
CURRENT_LINE="$(grep '^version:' pubspec.yaml)"
CURRENT_BUILD="$(echo "$CURRENT_LINE" | sed -E 's/version: *[0-9.]+\+([0-9]+)/\1/')"
NEW_BUILD=$((CURRENT_BUILD + 1))
NEW_LINE="version: $NEW_VERSION+$NEW_BUILD"

# Different sed flavours on macOS vs linux — use a portable tmp + mv.
tmp="$(mktemp)"
sed -E "s/^version: .+/$NEW_LINE/" pubspec.yaml > "$tmp"
mv "$tmp" pubspec.yaml

echo "▶︎ pubspec bumped: $CURRENT_LINE  →  $NEW_LINE"

# ── 3. Build + publish (LOCAL path only) ───────────────────────────
if [[ "$CI_MODE" != "1" ]]; then
    echo ""
    echo "▶︎ building locally…"
    tools/build-release.sh

    echo ""
    echo "▶︎ publishing locally…"
    NOTES="$NOTES" MIN_BUILD="$MIN_BUILD" tools/publish-release.sh
fi

# ── 4. Commit + tag + push ─────────────────────────────────────────
# In CI mode this is the entire "release action" — Bitbucket Pipelines
# catches the tag push, mirrors desktop/ → georgemosesgroup/flowapp,
# and GitHub Actions there runs build + publish on macos-latest.
if [[ "$SKIP_GIT" != "1" ]]; then
    TAG="desktop-v$NEW_VERSION-$NEW_BUILD"
    COMMIT_MSG="chore(desktop): release $NEW_VERSION+$NEW_BUILD"
    TAG_MSG="Flow $NEW_VERSION build $NEW_BUILD"
    if [[ -n "$NOTES" ]]; then
        COMMIT_MSG="$COMMIT_MSG

$NOTES"
        TAG_MSG="$TAG_MSG

$NOTES"
    fi
    # Propagate MIN_BUILD into the tag body so CI's publish step can
    # pick it up (the GH workflow reads the annotated tag body as NOTES,
    # and publish-release.sh honours MIN_BUILD from env — we fan it
    # out as a trailing marker the workflow greps for if needed).
    if [[ "$MIN_BUILD" != "0" ]]; then
        TAG_MSG="$TAG_MSG

MIN_BUILD=$MIN_BUILD"
    fi

    echo ""
    echo "▶︎ git commit + tag $TAG"
    git add pubspec.yaml
    git commit -m "$COMMIT_MSG"
    git tag -a "$TAG" -m "$TAG_MSG"

    # Push the commit + the tag. `origin` is Bitbucket (see
    # `git remote -v`). In CI mode this tag push is the trigger for
    # bitbucket-pipelines.yml's mirror step.
    git push origin HEAD
    git push origin "$TAG"
fi

echo ""
if [[ "$CI_MODE" == "1" ]]; then
    echo "✅ Tag pushed to Bitbucket. CI now handles build + publish:"
    echo "     https://bitbucket.org/mosesdevelopment/flowapp/addon/pipelines/home"
    echo "     → mirrors desktop/ → https://github.com/georgemosesgroup/flowapp"
    echo "     → GH Actions builds + ships on macos-latest"
    echo "   Watch: https://github.com/georgemosesgroup/flowapp/actions"
else
    echo "✅ Flow $NEW_VERSION ($NEW_BUILD) shipped."
fi
