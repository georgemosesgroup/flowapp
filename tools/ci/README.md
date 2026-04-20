# Full CI setup — tag push → automatic release

This wires the release pipeline end-to-end:

```
Dev Mac:   tools/release.sh --ci 1.0.1 "Notes"
             ↓ git tag desktop-v1.0.1-N; git push --tags
Bitbucket: bitbucket-pipelines.yml  (linux, free tier, ~30s)
             ↓ clones GH flowapp, overlays desktop/ contents, force-pushes main + tag
GitHub:    flowapp .github/workflows/release.yml  (macos-latest, ~8-12 min)
             ↓ flutter pub get → build-release.sh → publish-release.sh
Prod:      rsync DMG → downloads.flow.mosesdev.com  +  patch .env  +  restart backend
             ↓
Clients:   UpdateBanner appears on next poll (≤ 6 h; immediate on reopen)
```

After the one-time setup below, every release is one command on any Mac
(or any machine with git), fully hands-off. This dev Mac no longer
has to be the build host — you can ship a release from a phone via
the Bitbucket web UI's "Create tag" button if you wanted to.

GH Actions on `macos-latest` is **free and unlimited** for public
repositories — which is why `georgemosesgroup/flowapp` must be
public. That's fine: the desktop binary is already distributed as
a signed DMG, so the source carries no additional leak risk, and
no Flutter code paths touch secrets (all API keys live on the
backend).

---

## One-time setup

### 1. Generate a GitHub fine-grained PAT for Bitbucket → GitHub sync

Bitbucket Pipelines needs write access to `georgemosesgroup/flowapp`
to mirror `desktop/` contents there on every tag push.

1. Go to <https://github.com/settings/personal-access-tokens/new>
2. **Resource owner:** `georgemosesgroup`
3. **Repository access:** *Only select repositories* → `flowapp`
4. **Permissions:** Repository permissions → **Contents: Read and write**
5. Set expiry to 1 year (or longer if you prefer). Set a calendar
   reminder to rotate before expiry.
6. Generate, copy the token once.

### 2. Store the PAT in Bitbucket Pipelines variables

1. Open the monorepo on Bitbucket → **Repository settings** → **Pipelines**
   → **Repository variables**.
2. If Pipelines is not yet enabled, flip the toggle. Free tier =
   50 build minutes/month; the mirror step is ~30 s so that's
   roughly 100 releases before you'd hit it.
3. Add variable:
   - Name: `GH_TOKEN`
   - Value: the PAT from step 1
   - **Secured** ✓ (masked in logs)

### 3. Bootstrap the flowapp repo with the workflow file

The workflow lives at `flowapp/.github/workflows/release.yml`.
Bitbucket's mirror step explicitly preserves `.github/` during
every sync, but we need it there the first time.

```bash
git clone git@github.com:georgemosesgroup/flowapp.git /tmp/flowapp
cd /tmp/flowapp
mkdir -p .github/workflows
cp /path/to/voice-assistant-saas/desktop/tools/ci/flowapp-release.yml \
   .github/workflows/release.yml

# A tiny README is a good idea too — flowapp's landing page.
cat > README.md <<'EOF'
# Flow Desktop

Dictation app for macOS. Landing page + release artifacts.

- **Install:** [downloads.flow.mosesdev.com](https://downloads.flow.mosesdev.com)
- **Changelog:** [Releases](https://github.com/georgemosesgroup/flowapp/releases)

Source of truth lives in the private monorepo on Bitbucket;
`main` here is a release mirror force-pushed by CI on every tag.
EOF

git add .
git commit -m "ci: release workflow + landing README"
git push
```

### 4. Generate a deploy SSH key for CI → prod

GitHub Actions runners are ephemeral, so they can't reuse your
personal SSH key. Provision a dedicated key that can rsync + ssh
to the prod server.

**On any Mac** (doesn't have to be this one):

```bash
ssh-keygen -t ed25519 -f /tmp/flow-ci-deploy -N '' \
    -C "flow-ci-deploy (rotate annually)"
```

Two files pop out: `/tmp/flow-ci-deploy` (private) and
`/tmp/flow-ci-deploy.pub` (public).

**Add the public key to prod's authorized_keys:**

```bash
cat /tmp/flow-ci-deploy.pub | ssh root@165.245.214.29 \
    "cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

**Grab the host's SSH fingerprint** so the CI doesn't need
`StrictHostKeyChecking=no`:

```bash
ssh-keyscan -t ed25519 165.245.214.29
# Copy the whole line that prints — you'll paste it as a secret in step 5.
```

### 5. Add three secrets to the flowapp repo

<https://github.com/georgemosesgroup/flowapp/settings/secrets/actions> → *New repository secret*:

| Name | Value |
|---|---|
| `RELEASE_HOST` | `root@165.245.214.29` (dedicated flowapp server since 2026-04-20) |
| `SSH_PRIVATE_KEY` | Contents of `/tmp/flow-ci-deploy` — the whole file, including `-----BEGIN OPENSSH PRIVATE KEY-----` |
| `SSH_KNOWN_HOSTS` | The `ssh-keyscan` line from step 4 |

Then:

```bash
shred -u /tmp/flow-ci-deploy /tmp/flow-ci-deploy.pub
```

### 6. Verify once, end-to-end

From the monorepo:

```bash
cd desktop
tools/release.sh --ci 1.0.1 "First CI-driven release"
```

Then:

1. Bitbucket → **Pipelines** → should show a green run in ~30 s.
2. GitHub → **flowapp → Actions** → new "Release Flow Desktop" run
   on the tag, should go green in 8–12 min (first run is slower
   because caches are cold).
3. `curl -s https://api.flow.mosesdev.com/api/v1/desktop/latest`
   — should report `"build": <new-build>`.
4. Launch Flow on any older-build install — the UpdateBanner
   appears within 6 h (immediate on cmd-Q + reopen).

---

## Day-to-day — shipping a release

From any machine with git clone of the monorepo:

```bash
cd desktop
tools/release.sh --ci 1.0.2 "Fixed transcribe timeout, added EN dictionary"
```

That's it. You can close your laptop — CI handles the rest.

For a mandatory / security release:

```bash
MIN_BUILD=18 tools/release.sh --ci 1.0.3 "Security fix"
```

Clients below build 18 get the banner with no "×".

---

## What's happening under the hood

### Bitbucket side (`bitbucket-pipelines.yml` at monorepo root)

On any tag matching `desktop-v*` pushed to Bitbucket, Pipelines:

1. Clones `georgemosesgroup/flowapp` (so `.github/` workflows survive).
2. Wipes everything except `.git`, `.github`, `README.md`, `LICENSE`.
3. Copies the current monorepo's `desktop/` contents to the root.
4. Commits, force-pushes `main`, force-pushes the tag.

Force-push is intentional — `flowapp/main` is a release mirror,
not a human-editable branch. Each tag has its own commit,
reproducible from Bitbucket history.

### GitHub side (`flowapp/.github/workflows/release.yml`)

On a pushed `desktop-v*` tag:

1. Check out the tagged commit.
2. Install Flutter 3.38.6 (cached between runs).
3. `flutter pub get`.
4. Provision SSH (private key + known_hosts from secrets).
5. `tools/build-release.sh` — produces a signed `.app` + `.dmg` + `.zip`.
   Ad-hoc signed today; flip the commented-out `SIGNING_IDENTITY`
   block in the workflow once the Apple Developer ID cert is
   imported via
   [`Apple-Actions/import-codesign-certs`](https://github.com/Apple-Actions/import-codesign-certs).
6. `tools/publish-release.sh` — the same script that the local
   path runs. Rsync, probe, env patch, restart, verify.
7. Attach the DMG + ZIP to a GitHub Release object (convenience
   mirror; the canonical download URL remains on
   downloads.flow.mosesdev.com).

### Tag convention

`desktop-vX.Y.Z-N` where `N` is the `CFBundleVersion` build
number from `pubspec.yaml`. Marketing version and build are both
derived from pubspec by `tools/release.sh`, so there's no
tag/pubspec drift to worry about.

Other tag prefixes (e.g. `backend-v*`, `dashboard-v*`) are free
for future use — they won't trigger the desktop pipeline.

---

## Troubleshooting

**Bitbucket pipeline fails with "Authentication failed"**
→ `GH_TOKEN` is wrong, expired, or not scoped to `flowapp`.
Regenerate per step 1, re-add per step 2.

**GH Actions fails at "Configure SSH" with "invalid format"**
→ `SSH_PRIVATE_KEY` secret was pasted with CRLF line endings, or
missed the trailing newline. Re-paste from a Unix `cat` of the
file.

**GH Actions fails at "Publish" with "Permission denied (publickey)"**
→ Public half of the CI deploy key isn't in `/root/.ssh/authorized_keys`
on prod, OR it's there but with wrong permissions. Fix both:
`chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys`.

**GH Actions fails at "HTTP 404" during publish probe**
→ nginx on prod doesn't know about `downloads.flow.mosesdev.com`
yet (the server block from `nginx/nginx.conf` hasn't deployed).
Run `docker compose -f docker-compose.prod.yml up -d nginx` on
the server, or redeploy via the monorepo's Bitbucket webhook.

**"In-app UpdateBanner doesn't appear" after the run is green**
→ Client caches the 6 h poll. Quit Flow + reopen for an immediate
probe, or `curl -s https://api.flow.mosesdev.com/api/v1/desktop/latest`
to confirm the backend reports the new build.
