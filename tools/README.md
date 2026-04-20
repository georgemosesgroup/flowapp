# Desktop release tooling

Scripts in this directory are one-off helpers for building and shipping the
macOS Flow app outside of `flutter run`. All paths are relative to the
`desktop/` directory.

## Contents

| File | Purpose |
|---|---|
| `generate_icon.swift` | Draws the Flow AppIcon at 1024×1024 using the brand colours from `lib/theme/tokens.dart`. |
| `generate_icon.sh` | Runs the Swift generator, downscales via `sips`, installs PNGs into `macos/Runner/Assets.xcassets/AppIcon.appiconset/`. |
| `build-release.sh` | Builds a signed `.app` + `.dmg` + `.zip` under `desktop/dist/`. |
| `publish-release.sh` | Rsyncs a built DMG/ZIP to `downloads.flow.mosesdev.com`, patches `.env` on the prod server, restarts backend, and verifies `/api/v1/desktop/latest` reflects the new build. |
| `release.sh` | One-command bump + build + publish + git tag. The real "ship it" entrypoint. |

---

## Regenerating the app icon

```bash
cd desktop
tools/generate_icon.sh
```

Asset catalog PNGs are overwritten in place. Changes only take effect on a
full Flutter build (not hot reload) — stop the running `flutter run` and
restart it.

If the brand colours change, edit the constants at the top of
`generate_icon.swift` and re-run.

---

## Building a release

### Ad-hoc build (no Apple Developer account)

```bash
cd desktop
tools/build-release.sh
```

Produces:

- `dist/Flow.app` — signed ad-hoc (`codesign --sign -`)
- `dist/Flow-<version>-<build>.dmg` — draggable installer
- `dist/Flow-<version>-<build>.zip` — same app, archived (useful later for
  Sparkle update feeds)

**On this Mac** the app launches normally.

**On a tester's Mac** Gatekeeper will block first launch with a "Flow is
damaged and can't be opened" message. The tester has two choices:

1. Right-click the `.app` → *Open* → *Open* (only needed once per Mac)
2. From Terminal: `xattr -d com.apple.quarantine /Applications/Flow.app`

This is expected for ad-hoc builds. Real notarized releases don't trigger
this prompt.

### Signed build (Apple Developer ID)

Once the Apple Developer account is active:

```bash
cd desktop
SIGNING_IDENTITY="Developer ID Application: George Moses (TEAMID)" \
    tools/build-release.sh
```

Replace `TEAMID` with the 10-character Team ID from
[developer.apple.com/account](https://developer.apple.com/account) →
*Membership details*. The identity string must match exactly what
`security find-identity -v -p codesigning` prints for your Developer ID
certificate (check with that command first).

### Signed + notarized (shippable build)

```bash
cd desktop

# One-time setup — interactively provides Apple ID + app-specific password,
# stored in the keychain under the profile name.
xcrun notarytool store-credentials flow-release \
    --apple-id you@example.com \
    --team-id TEAMID

# Every build from now on:
SIGNING_IDENTITY="Developer ID Application: George Moses (TEAMID)" \
NOTARIZE=1 \
NOTARY_PROFILE=flow-release \
    tools/build-release.sh
```

The DMG produced by this flow opens cleanly on any Mac without Gatekeeper
warnings.

---

## Publishing a release

Hosting: `downloads.flow.mosesdev.com` — our own nginx, binary files
live in `/srv/flow-downloads/` on the prod server, rsync'd there
from this dev Mac. No GitHub Actions / CI at the default tier —
desktop builds need macOS + Xcode, the monorepo lives on Bitbucket,
and solo-dev release cadence doesn't justify a self-hosted runner
yet. One command ships it end-to-end. (See "Full CI" at the bottom
for upgrading to tag-push-triggered builds later.)

### First-time setup

**On this dev Mac** — put this in your shell profile so the release
script can ssh to prod:

```bash
export RELEASE_HOST=root@165.245.214.29      # dedicated flowapp server
# Optional — script assumes these defaults if unset:
export RELEASE_DIR=/srv/flow-downloads
export SERVER_REPO=/opt/flowapp
export PUBLIC_BASE=https://downloads.flow.mosesdev.com
```

**On the prod server** — since the 2026-04-20 migration to the
dedicated DigitalOcean droplet, `/srv/flow-downloads/` already exists
(owned by `root`, 755), the `downloads.flow.mosesdev.com` server
block is already in `nginx/nginx.conf`, and the in-tree Caddy service
(`caddy/Caddyfile`) already holds the TLS cert for it. Nothing to do
on first publish — the rsync just lands files into a live dir.

If you need to verify the wiring:

```bash
ssh $RELEASE_HOST '
  ls -ld /srv/flow-downloads
  grep downloads.flow.mosesdev.com /opt/flowapp/nginx/nginx.conf
  grep downloads.flow.mosesdev.com /opt/flowapp/caddy/Caddyfile
'
curl -I https://downloads.flow.mosesdev.com/   # HTTP/2 404 until first DMG
```

### Shipping a release — one command

```bash
cd desktop
tools/release.sh 1.0.1 "Sidebar polish + live update banner"
```

That script does, in order:

1. Bumps build number in `pubspec.yaml` (keeps the marketing
   version you passed, increments `+N` by 1).
2. `tools/build-release.sh` — signed `.app` + `.dmg` + `.zip`.
3. `tools/publish-release.sh`:
   - rsync `Flow-*.dmg` + `Flow-*.zip` → `downloads.flow.mosesdev.com`
   - HTTPS HEAD probe to confirm caddy + nginx + file are all wired
   - patches `/opt/flowapp/.env` on the server in place
     (idempotent — strips any prior `DESKTOP_LATEST_*` block before
     appending, keeps a timestamped `.bak` as rollback insurance)
   - `docker compose restart backend`
   - verifies `https://api.flow.mosesdev.com/api/v1/desktop/latest`
     now reports the new build number
4. `git commit` the pubspec bump + `git tag desktop-v1.0.1-<build>`
   + `git push origin HEAD` + `git push origin --tags` to Bitbucket.

Clients running an older build see the UpdateBanner on their next
poll — the Flutter `UpdateService` probes on app boot and every 6 h
thereafter, so anyone who cmd-Q's and reopens sees it immediately.
The banner's "Update" button opens the DMG URL in the default
browser; macOS handles the download + drag-to-Applications flow
the native way. When we switch to Sparkle after the Developer ID
arrives, that same DMG URL feeds the appcast for silent in-app
updates.

### Dry-run first

Paranoid about the server-side env patch? Every publish can be
dry-run — prints every remote command without executing:

```bash
DRY_RUN=1 tools/publish-release.sh
```

### Force-updates

For a security fix where users shouldn't be able to dismiss the
banner, pass `MIN_BUILD`:

```bash
MIN_BUILD=17 tools/release.sh 1.0.2 "Security fix — mandatory"
```

Clients on build < 17 get the banner with no "×" and a warning
(orange) tint. Clients on build ≥ 17 see nothing.

### Rolling back

Mis-shipped a build? Two options:

1. **Roll forward** — ship a new release with a higher build
   number, users auto-prompt to upgrade.
2. **Revert env** — `publish-release.sh` leaves a timestamped
   `.env.bak.<epoch>` next to the live file every
   time. On the server:

   ```bash
   cd /opt/flowapp
   ls -lt .env.bak.*                     # pick the one from before the bad ship
   cp .env.bak.1714406891 .env
   docker compose -f docker-compose.prod.yml restart backend
   ```

Existing installs of the bad build stay as-is (no downgrade path),
but the banner stops advertising the broken release.

### Reshipping without re-tagging

If you need to redo a publish for an existing build (e.g. you
re-uploaded the DMG) without bumping pubspec or tagging again:

```bash
# Just rerun publish — it reads version+build from pubspec.
SKIP_GIT=1 tools/release.sh $(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1) ""
# Or more directly:
tools/publish-release.sh
```

---

## Full CI — automatic release on tag push

Local (`tools/release.sh`) and CI (`tools/release.sh --ci`) paths
are both wired. Pick per call.

- **Local** builds + publishes from this Mac in ~3 min. Needs
  SSH access to prod (`RELEASE_HOST`), the ad-hoc codesign path is
  free — a Developer ID identity is optional (and required for
  notarization).
- **CI** builds + publishes on GitHub's `macos-latest` hosted
  runner in ~8-12 min. No Mac/SSH needed on the machine calling
  `tools/release.sh --ci` — can ship from any box with git, or
  even the Bitbucket web UI.

### CI architecture (already in this repo)

```
Dev:        tools/release.sh --ci 1.0.1 "notes"
              ↓ git tag + push to Bitbucket
BB:         bitbucket-pipelines.yml (root)  — mirrors desktop/ →
              georgemosesgroup/flowapp (public) on desktop-v* tags
GH flowapp: .github/workflows/release.yml  — macos-latest runner:
              flutter pub get → build-release.sh → publish-release.sh
Prod:       rsync DMG, patch .env, docker compose restart backend
Clients:    UpdateBanner appears on next poll
```

First-time setup (PAT, GitHub secrets, CI deploy SSH key,
bootstrapping the workflow into `flowapp`) is spelled out in
**[tools/ci/README.md](ci/README.md)** — ~15 minutes total.

### Shipping via CI

```bash
cd desktop
tools/release.sh --ci 1.0.1 "Sidebar polish + live update banner"
```

Close laptop. Watch progress at
<https://github.com/georgemosesgroup/flowapp/actions>.

### When to use which path

| | Local (`release.sh`) | CI (`release.sh --ci`) |
|---|---|---|
| Build happens on | This Mac | GitHub macos-latest runner |
| Time to live | ~3 min | ~8-12 min |
| SSH needed on caller | yes (`RELEASE_HOST`) | no |
| Works offline | yes | no (needs tag push to BB) |
| Can ship from iPad / phone | no | yes (BB web UI tag create → CI takes over) |
| Codesign state required | on this Mac | in GH runner keychain (once Apple Dev cert is provisioned) |

For solo-dev hacking on a release right now: local is faster.
For regular releases + multi-dev ergonomics: CI.

---

## Versioning

`pubspec.yaml`:

```yaml
version: 1.2.0+17
         ^^^^^ ^^
          │    └─ build number (CFBundleVersion) — must strictly increase
          │       on every release Apple ever sees (notarization enforces
          │       this). Bump by 1 per shipped build.
          └───── marketing version (CFBundleShortVersionString) — what the
                 user sees. Semver is conventional but not required by
                 Apple.
```

`build-release.sh` parses this line and passes both values into
`flutter build macos --build-name/--build-number`.

---

## Troubleshooting

- **`Expected build output not found: build/.../Flow.app`** — the
  `PRODUCT_NAME` in `macos/Runner/Configs/AppInfo.xcconfig` isn't
  `Flow`. Don't change it back to `voice_assistant_desktop`.
- **`codesign --verify` fails** — Xcode or Keychain got confused about
  certificate trust. Close Xcode, rerun. If still broken,
  `security find-identity -v -p codesigning` should list the expected
  identity; if it doesn't, the cert isn't installed.
- **Notarization rejected** — download the log with
  `xcrun notarytool log <submission-id> --keychain-profile flow-release`.
  Most common: missing `com.apple.security.automation.apple-events`
  entitlement, `LSUIElement` typo, or unsigned nested binaries under
  `Frameworks/`. The current `Release.entitlements` is correct for the
  features Flow uses today.
