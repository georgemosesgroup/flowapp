# Flow

macOS dictation app. Press a global hotkey anywhere on your Mac,
speak, release — the recognised text lands in whatever window has
focus. Multi-language (including a fine-tuned Armenian Whisper
under the hood), local dictionary, reusable snippets.

- **Install:** https://downloads.flow.mosesdev.com
- **Changelog:** [Releases](https://github.com/georgemosesgroup/flowapp/releases)
- **Landing page:** (coming soon on `flow.mosesdev.com`)

## About this repository

This directory is the desktop Flutter package. It lives inside a
private monorepo on Bitbucket alongside the backend, dashboard,
SDK and widget.

The **public** copy at
[`github.com/georgemosesgroup/flowapp`](https://github.com/georgemosesgroup/flowapp)
is a release mirror: on every `desktop-vX.Y.Z-N` tag push from
the private repo, a Bitbucket Pipeline overlays this directory's
contents onto `main` there and force-pushes. GitHub Actions then
builds a signed DMG on `macos-latest` and publishes it to
`downloads.flow.mosesdev.com`.

Why the split: GitHub gives unlimited macOS minutes for public
repos, which makes tag-push-to-DMG cost nothing. The Flutter
client carries no secrets (API keys live on the backend), so
publishing the source doesn't change the attack surface — anyone
could decompile the DMG anyway.

## Running locally

```bash
flutter pub get
flutter run -d macos
```

Points at the production API by default — override with
`--dart-define=API_BASE_URL=http://localhost:8180` when the backend
is on your Mac.

## Building a release

One-command, two modes:

```bash
# Local — build + publish from this Mac (~3 min)
tools/release.sh 1.0.1 "Release notes"

# CI — tag-only, GH Actions does the work (~8–12 min)
tools/release.sh --ci 1.0.1 "Release notes"
```

See [`tools/README.md`](tools/README.md) for the full flow, codesign
setup, and notarization hints once an Apple Developer ID is
provisioned. [`tools/ci/README.md`](tools/ci/README.md) covers the
one-time PAT + SSH-key + GH-secret setup for the CI path.

## Architecture at a glance

- Flutter 3.38 / Dart 3.10 macOS app
- `flow_bar_service.dart` — NSMenuBar-adjacent floating recorder UI
- `realtime_dictate_service.dart` — audio capture + streaming to backend
- `hotkey_service.dart` — global shortcut, customisable per-user
- `update_service.dart` — 6h polling + on-boot probe of
  `/api/v1/desktop/latest`; surfaces the in-app `UpdateBanner`
  when a newer build is available (and force-update mode when the
  new build sets `min_build`)

Backend code that Flow talks to (Go, PostgreSQL, Modal-hosted
Whisper models) lives in the private monorepo.
