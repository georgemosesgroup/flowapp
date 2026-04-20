# Flow Desktop CI — setup instructions for an AI agent

## Что это

Инструкция для другого агента: активировать уже собранный release-pipeline
для Flow Desktop (macOS app). Инфраструктура в репе уже есть, нужно только
провести bootstrap: PAT, секреты, SSH-ключи, первый тестовый релиз.

**Не пересоздавай файлы, которые уже в репо.** Проверь их существование и
используй.

---

## Контекст проекта

- **Монорепа (source of truth):** Bitbucket — `git@bitbucket.org:mosesdevelopment/flowapp.git`
  - На этой машине лежит в `/Volumes/Moses/IT/PROJECTS/voice-assistant-saas/`
  - Desktop-код — в подкаталоге `desktop/`
- **GH release-зеркало:** `https://github.com/georgemosesgroup/flowapp` (публичный)
  - Сейчас, вероятно, пустой или с одним README
- **Прод-сервер:** `165.245.214.29` (dedicated DigitalOcean FRA1 droplet
  since 2026-04-20), SSH-пользователь `root`, alias `flowapp` в
  `~/.ssh/config`. Старый shared-bookfit host `142.93.170.139` снесён.
- **Домен для бинарников:** `downloads.flow.mosesdev.com` (уже создан,
  прокинут через in-tree caddy → flowapp-nginx — собственный caddy-сервис
  в docker-compose.prod.yml, не bookfit-caddy)

### Целевая архитектура

```
Dev:    tools/release.sh --ci 1.0.1 "Notes"
          ↓ git tag + push на Bitbucket
BB:     bitbucket-pipelines.yml (root) — клонит flowapp, overlay-ит
          desktop/ контент, force-push-ит main + тег
GH:     flowapp/.github/workflows/release.yml — runs-on: macos-latest
          → flutter pub get → tools/build-release.sh → tools/publish-release.sh
Прод:   rsync DMG → /srv/flow-downloads  +  patch .env
          +  docker compose restart backend
Клиент: UpdateBanner на следующем polling'е (≤ 6 ч; мгновенно на reopen)
```

---

## Проверь сначала — что уже есть в репе

Все эти файлы **должны** существовать. Если нет — остановись и запроси
человека, перед тем как писать их:

```bash
ls -la /Volumes/Moses/IT/PROJECTS/voice-assistant-saas/bitbucket-pipelines.yml
ls -la /Volumes/Moses/IT/PROJECTS/voice-assistant-saas/desktop/tools/ci/flowapp-release.yml
ls -la /Volumes/Moses/IT/PROJECTS/voice-assistant-saas/desktop/tools/ci/README.md
ls -la /Volumes/Moses/IT/PROJECTS/voice-assistant-saas/desktop/tools/release.sh
ls -la /Volumes/Moses/IT/PROJECTS/voice-assistant-saas/desktop/tools/build-release.sh
ls -la /Volumes/Moses/IT/PROJECTS/voice-assistant-saas/desktop/tools/publish-release.sh
ls -la /Volumes/Moses/IT/PROJECTS/voice-assistant-saas/nginx/nginx.conf
grep -A1 downloads.flow.mosesdev.com /Volumes/Moses/IT/PROJECTS/voice-assistant-saas/nginx/nginx.conf
grep flow-downloads /Volumes/Moses/IT/PROJECTS/voice-assistant-saas/docker-compose.prod.yml
```

Все команды должны что-то находить. Если какая-то ничего не вернула —
значит кто-то откатил изменения, ищи в git log.

---

## Что нужно от человека (агент не может сделать)

Запроси у него **до начала работы** эти три вещи:

1. **SSH hostname прод-сервера** — default `165.245.214.29`, SSH user
   `root` (alias `flowapp` в `~/.ssh/config`).
2. **Запустил ли он уже шаг 1 (PAT).** Если нет — дай ему инструкцию
   из §1 и жди, пока он не скинет тебе токен.
3. **Есть ли у тебя (агента) `gh` CLI, аутентифицированный на
   `georgemosesgroup`.** Если нет — ему нужно `gh auth login` и
   подтвердить права на запись в репо (scopes: `repo`, `workflow`).
   Без `gh` многие шаги придётся отдавать человеку вручную через UI.

---

## §1. Fine-grained GitHub PAT (ТОЛЬКО ЧЕЛОВЕК)

Агент **не может** сгенерировать fine-grained PAT — это требует UI с 2FA.
Попроси человека:

> Зайди на https://github.com/settings/personal-access-tokens/new
>
> - **Token name:** `flow-ci-bb-mirror`
> - **Expiration:** 1 year
> - **Resource owner:** `georgemosesgroup`
> - **Repository access:** *Only select repositories* → `flowapp`
> - **Repository permissions:** Contents → **Read and write**
> - Нажми **Generate token**, скопируй значение (оно показывается
>   один раз).
> - Пришли мне значение в ответном сообщении.

Когда человек пришлёт токен — **не логируй его, не коммить, не пиши в
файл.** Используй только в памяти и при передаче на Bitbucket
(шаг §5).

---

## §2. Bootstrap репы `georgemosesgroup/flowapp` воркфлоу-файлом

GitHub flowapp — пустой или почти пустой. Нужно положить туда
`.github/workflows/release.yml` (бекап — `desktop/tools/ci/flowapp-release.yml`
в монорепе). Bitbucket Pipelines'овский mirror-шаг явно сохраняет
`.github/` между запусками, так что после первого bootstrap'а туда
можно не возвращаться.

### Через `gh` CLI (если есть)

```bash
cd /tmp
git clone https://github.com/georgemosesgroup/flowapp.git
cd flowapp

mkdir -p .github/workflows
cp /Volumes/Moses/IT/PROJECTS/voice-assistant-saas/desktop/tools/ci/flowapp-release.yml \
   .github/workflows/release.yml

# Если в репе нет README — создай минимальный (bookkeeping для landing-page):
if [[ ! -f README.md ]]; then
    cat > README.md <<'EOF'
# Flow Desktop

macOS dictation app. Landing page + release artifacts.

- **Install:** https://downloads.flow.mosesdev.com
- **Changelog:** [Releases](https://github.com/georgemosesgroup/flowapp/releases)

Source of truth lives in the private monorepo on Bitbucket;
`main` here is a release mirror force-pushed by CI on every tag.
EOF
fi

git add .
git commit -m "ci: bootstrap release workflow"
git push origin main
```

### Ручной fallback (без `gh` CLI)

Отдай человеку команды выше — он выполнит у себя.

### Проверка

```bash
gh workflow list --repo georgemosesgroup/flowapp
# Должен вывести "Release Flow Desktop"
```

Если `gh` нет — открой
https://github.com/georgemosesgroup/flowapp/actions — там должен быть
workflow "Release Flow Desktop".

---

## §3. Сгенерируй deploy SSH ключ для GH Actions → прод

GH Actions runners — эфемерные. Нужен отдельный SSH ключ, **не**
переиспользуй личный ключ пользователя.

```bash
# Сгенерируй в /tmp (никогда не коммить в репу!)
ssh-keygen -t ed25519 -f /tmp/flow-ci-deploy -N '' \
    -C "flow-ci-deploy (rotate annually — $(date +%Y-%m-%d))"

# Два файла:
ls -la /tmp/flow-ci-deploy{,.pub}
#   /tmp/flow-ci-deploy       (приватный — ТОЛЬКО в GH Secret)
#   /tmp/flow-ci-deploy.pub   (публичный — в ~/.ssh/authorized_keys на проде)
```

---

## §4. Установи публичный ключ на прод-сервере

Агенту нужен SSH-доступ на прод. Если у тебя он есть (через ключ
пользователя в `~/.ssh/`):

```bash
# Default — новый dedicated сервер flowapp, root user.
RELEASE_HOST="root@165.245.214.29"

# Добавь публичку в authorized_keys. Для root пользователя authorized_keys
# уже обычно есть (установлен ssh ключ dev-мака при provisioning'е droplet'а).
cat /tmp/flow-ci-deploy.pub | ssh "$RELEASE_HOST" \
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
     cat >> ~/.ssh/authorized_keys && \
     chmod 600 ~/.ssh/authorized_keys"

# Проверь — должен зайти без пароля с только-что-созданным ключом
ssh -i /tmp/flow-ci-deploy -o BatchMode=yes "$RELEASE_HOST" "echo ok && hostname"
# Если напечатал "ok" + hostname — готово.

# Собери ssh-keyscan для known_hosts (нужно будет в §5)
ssh-keyscan -t ed25519 "${RELEASE_HOST#*@}" 2>/dev/null > /tmp/flow-ci-known-hosts
cat /tmp/flow-ci-known-hosts
# Эта строка пойдёт в GH Secret SSH_KNOWN_HOSTS.
```

Если у тебя нет SSH — отдай человеку команду
`cat /tmp/flow-ci-deploy.pub` (копируй только публичку) и попроси:

> Выполни на прод-сервере:
> ```
> echo 'ВСТАВЬ_СЮДА_ПУБЛИЧНЫЙ_КЛЮЧ' >> ~/.ssh/authorized_keys
> chmod 600 ~/.ssh/authorized_keys
> ```

---

## §5. Добавь три GH Actions секрета на flowapp

### Через `gh` CLI (быстро)

```bash
RELEASE_HOST="root@165.245.214.29"

# 1. RELEASE_HOST — куда публиковать
echo "$RELEASE_HOST" | gh secret set RELEASE_HOST \
    --repo georgemosesgroup/flowapp

# 2. SSH_PRIVATE_KEY — приватка ключа из §3
gh secret set SSH_PRIVATE_KEY \
    --repo georgemosesgroup/flowapp \
    < /tmp/flow-ci-deploy

# 3. SSH_KNOWN_HOSTS — отпечаток хоста из §4
gh secret set SSH_KNOWN_HOSTS \
    --repo georgemosesgroup/flowapp \
    < /tmp/flow-ci-known-hosts

# Проверь что все три прописаны (значения скрыты — показывается только имя):
gh secret list --repo georgemosesgroup/flowapp
# Должно быть:
#   RELEASE_HOST
#   SSH_KNOWN_HOSTS
#   SSH_PRIVATE_KEY

# Удали временные файлы — приватка больше не нужна
shred -u /tmp/flow-ci-deploy /tmp/flow-ci-deploy.pub /tmp/flow-ci-known-hosts 2>/dev/null \
    || rm -P /tmp/flow-ci-deploy /tmp/flow-ci-deploy.pub /tmp/flow-ci-known-hosts
```

### Ручной fallback

Отправь человека на
https://github.com/georgemosesgroup/flowapp/settings/secrets/actions →
*New repository secret*, три раза (значения он возьмёт из `/tmp/`).

---

## §6. Добавь `GH_TOKEN` в Bitbucket Pipelines variables (ТОЛЬКО ЧЕЛОВЕК)

У Bitbucket API нет публичного доступа к secrets через CLI без OAuth.
Попроси человека:

> 1. Открой https://bitbucket.org/mosesdevelopment/flowapp/admin/addon/admin/pipelines/repository-variables
> 2. Если Pipelines не включены — переключи toggle (free tier, 50 минут/месяц).
> 3. Нажми **Add variable**:
>    - **Name:** `GH_TOKEN`
>    - **Value:** токен из §1
>    - **Secured** ✓ (маскируется в логах)
> 4. **Add**.

После этого `bitbucket-pipelines.yml` при пуше тега `desktop-v*` сможет
зеркалить в flowapp.

---

## §7. Проверь, что прод-сервер готов принимать DMG

**ЭТО УЖЕ СДЕЛАНО во время миграции на dedicated сервер 2026-04-20.**
Здесь только smoke-check чтобы подтвердить состояние:

```bash
RELEASE_HOST="root@165.245.214.29"

# 1. Директория
ssh "$RELEASE_HOST" 'ls -ld /srv/flow-downloads'
# Ожидаемо: drwxr-xr-x 2 root root ...

# 2. nginx server-block для downloads.flow.mosesdev.com
ssh "$RELEASE_HOST" 'grep -n downloads.flow.mosesdev.com /opt/flowapp/nginx/nginx.conf'
# Ожидаемо: "server_name downloads.flow.mosesdev.com;" block

# 3. caddy знает про subdomain (in-tree Caddyfile, не bookfit)
ssh "$RELEASE_HOST" 'grep downloads.flow.mosesdev.com /opt/flowapp/caddy/Caddyfile'
# Ожидаемо: "downloads.flow.mosesdev.com {" block

# 4. HEAD пробинг — 404 = nginx жив, корень закрыт. 200 = уже есть DMG.
curl -I https://downloads.flow.mosesdev.com/ 2>&1 | head -5
# Ожидаемо: "HTTP/2 404" до первой публикации
```

Если любая из проверок не сработала — см.
`docs/handoff/2026-04-20-server-migration.md` + `docs/runbooks/DEPLOY.md`.

---

## §8. Запусти первый тестовый релиз через CI

Всё готово. Проверь end-to-end:

```bash
cd /Volumes/Moses/IT/PROJECTS/voice-assistant-saas/desktop

# Узнай текущую версию в pubspec
grep '^version:' pubspec.yaml
# Допустим, "version: 1.0.0+1" — будем релизить 1.0.0 -> 1.0.0+2 или
# бампанём до 1.0.1+2. Скрипт сам увеличит build.

# Запусти CI-режим (НЕ собирает локально — только тегает и пушит)
tools/release.sh --ci 1.0.1 "First CI-driven release"
```

Скрипт сделает:
1. bump pubspec.yaml до `1.0.1+<next-build>`
2. git commit + git tag `desktop-v1.0.1-<build>` + git push на Bitbucket
3. Напишет ссылки куда смотреть прогресс

### Наблюдай за прогрессом

```bash
# Bitbucket pipeline (линукс, ~30 сек)
open https://bitbucket.org/mosesdevelopment/flowapp/addon/pipelines/home

# GH Actions (macos-latest, ~8-12 мин первый раз, ~3-5 мин с кешем)
gh run watch --repo georgemosesgroup/flowapp
# или
open https://github.com/georgemosesgroup/flowapp/actions
```

### Проверь результат

```bash
# 1. Endpoint отдаёт новую версию
curl -s https://api.flow.mosesdev.com/api/v1/desktop/latest | jq
# {
#   "version": "1.0.1",
#   "build": <new-build>,
#   "url": "https://downloads.flow.mosesdev.com/Flow-1.0.1-<build>.dmg",
#   "notes": "First CI-driven release",
#   "min_build": 0
# }

# 2. DMG физически доступен
curl -I https://downloads.flow.mosesdev.com/Flow-1.0.1-*.dmg
# HTTP/2 200

# 3. GH Release создан
gh release view "desktop-v1.0.1-<build>" --repo georgemosesgroup/flowapp
```

Если **всё три** проверки прошли — CI живой. Каждый следующий релиз =
одна команда из любой точки, где есть git-клон монорепы.

---

## Troubleshooting

### BB pipeline падает на `Authentication failed` при push на GH
`GH_TOKEN` некорректен / протух / не scoped на `flowapp`.
Перегенерируй по §1, пересохрани по §6.

### GH Actions падает на шаге "Configure SSH" → `invalid format`
Секрет `SSH_PRIVATE_KEY` вставлен с CRLF (Windows line endings) или без
последнего переноса строки. Пересохрани через `gh secret set` — оно
пропустит файл через stdin корректно:
```bash
gh secret set SSH_PRIVATE_KEY --repo georgemosesgroup/flowapp < /tmp/flow-ci-deploy
```

### GH Actions падает на "Publish" → `Permission denied (publickey)`
Публичка из §3 не в `authorized_keys` на проде, или с неправильными правами.
Проверь на сервере: `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`.

### GH Actions падает на "HTTP 404" в publish probe
Nginx ещё не подцепил volume mount / server block для
`downloads.flow.mosesdev.com`. Выполни шаг §7 снова (`docker compose up -d nginx`).

### Релиз зелёный, но UpdateBanner не появился в приложении
Клиент кеширует 6-часовой polling. Quit (cmd-Q) + reopen Flow →
мгновенный probe. Проверь ещё раз `curl /api/v1/desktop/latest`.

---

## Что передать человеку в финале

Одну команду для каждого следующего релиза:

```bash
cd desktop
tools/release.sh --ci 1.0.2 "Fixes X, adds Y"
```

Никаких SSH, секретов, serverside-действий. CI делает всё. Сломается —
troubleshooting выше.
