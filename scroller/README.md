# Bible Scroller

Instagram-style vertical Bible reels: full-screen verse cards with background art, likes, nested comments, translation switching, and chapter voiceovers.

## Structure

```
scroller/
├── client/                 Flutter app (reels UI)
├── server/                 FastAPI backend
├── deploy/                 Production VM configs (nginx, compose snippet, DEPLOY.md)
└── docker-compose.dev.yml  Local dev: Postgres + API
```

## Quick start

### Local dev (Docker)

```bash
cd scroller
docker compose -f docker-compose.dev.yml up -d --build
```

### Production deploy

See **[deploy/DEPLOY.md](deploy/DEPLOY.md)** for the navedu.uk VM (`bscroller.navedu.uk`).

### Backend (bare metal)

```bash
cd server
cp .env.example .env
# Add BIBLE_BRAIN_API_KEY to .env (request at https://4.dbt.io/api_key/request)
pip install -r requirements.txt
alembic upgrade head   # or rely on auto init_db on first startup
uvicorn src.main:app --reload --host 0.0.0.0 --port 8000
```

On first startup the server creates tables and seeds reels (default: first 30 groups from John test manifest). For the full Bible:

```bash
python -m src.seed_cli --manifest ../../pipeline/output/groups/manifest.json --limit 0 --force
```

API docs: http://127.0.0.1:8000/docs

### Flutter client

```bash
cd client
flutter pub get
flutter run
```

**Android emulator** uses `http://10.0.2.2:8000` by default. Override with:

```bash
flutter run --dart-define=API_BASE_URL=http://YOUR_LAN_IP:8000
```

**Physical device** must use your machine's LAN IP, not `localhost`.

### Browser (Flutter web)

The same reels UI runs in Chrome. Locally:

```bash
# Terminal 1 — API
cd server && uvicorn src.main:app --reload --host 0.0.0.0 --port 8000

# Terminal 2 — Flutter web (points at local API)
cd client
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

**Production / same-origin:** build web with an empty API base URL, copy into the server image, then open `https://bscroller.navedu.uk/`:

```bash
cd client
flutter build web --release --no-tree-shake-icons --dart-define=API_BASE_URL=
# PowerShell: copy build\web -> ..\server\static\web  (see server/static/README.md)
```

On web, last-viewed reel is stored in the `bscroller_last_reel_id` cookie and restored on return. Desktop browsers show a phone-width (430px) frame centered on a black background.

Smoke: open `/` → scroll a few reels → reload → same reel; `GET /health` and `GET /reels` still return JSON.

## Features (current)

| Feature | Status |
|---------|--------|
| Vertical reel feed (PageView) | Done |
| Background image + verse overlay | Done |
| Like / unlike reels | Done |
| Nested comment replies | Done |
| Comment likes | Done |
| Translation picker (Bible Brain API proxy) | Done |
| Chapter voiceover playback | Done |
| Share | Not started (deferred) |
| User accounts / auth | Google + email/password + 6-digit email verify |
| Pipeline-generated images | Wired — serves `pipeline/output` at `/media/pipeline` |
| Alembic migrations | Initial schema + comment replies + auth accounts |
| Autoplay voiceover | On by default; long-press Listen to toggle |
| Haptic feedback | Likes trigger light haptic |
| Offline verse cache | Hive caches verse text per reel + translation |
| Profile display name | `PATCH /users/me` |
| Docker deploy (local) | `docker compose -f docker-compose.dev.yml up --build` |
| Docker deploy (VM) | See [deploy/DEPLOY.md](deploy/DEPLOY.md) — `movinin/apps:bscroller_backend` |
| Browser / Flutter web | Served at `/` from FastAPI when `server/static/web` is present |
| Resume position (web) | Cookie `bscroller_last_reel_id` + `GET /reels?from_id=` |

## Storage (client)

- **SharedPreferences**: device ID, selected translation version (default **NIV**), autoplay preference
- **Hive**: local cache of liked reel IDs and verse text

## Tests

```bash
# Backend
cd server && pytest

# Client
cd client && flutter test
```

---

## Product decisions (locked)

| Area | Decision |
|------|----------|
| Bible API | **Bible Brain** (Faith Comes By Hearing / DBP v4 at `4.dbt.io`) |
| Default translation | **NIV** |
| Audio | **Full chapter** when reel shown / Listen tapped; **autoplay on** |
| Initial content | **John only** — first 30 sections from manifest (configurable via `SEED_LIMIT`) |
| Feed order | **Manifest order** (ascending reel id) |
| Images | VM read-only mount at `/home/opc/data/bscroller/output` |
| Auth (now) | **JWT** after Google or verified email/password; device ID used for account linking |
| Comments | **Nested replies** (Instagram-style) |

### Bible Brain API key

Request a free key at https://4.dbt.io/api_key/request

Add to `server/.env`:

```env
BIBLE_BRAIN_API_KEY=your_key_here
```

Without a key, verse text and audio URLs return placeholders locally.

The client never holds the key — the server proxies `/bible/*`.

---

## Auth

- **Google Sign-In** and **email/password** via FastAPI JWTs (`POST /auth/google`, `/auth/register`, `/auth/login`)
- Email/password accounts require a **6-digit verification code** (`POST /auth/verify-email`) before activation
- Feed/comments are readable without login; likes and comments require a verified JWT
- Set `JWT_SECRET` (≥32 chars; required in production), `GOOGLE_CLIENT_IDS` (Web + Android + iOS client IDs, comma-separated), and `RESEND_API_KEY` (+ `RESEND_FROM`)
- Flutter: client IDs in `client/lib/config/google_oauth_config.dart` (override Web ID with `--dart-define=GOOGLE_WEB_CLIENT_ID=...` if needed)
- Local/dev: `ALLOW_CONSOLE_MAILER=true` logs codes to the console; production must use Resend (or SMTP fallback)
- Auth endpoints rate-limit register/verify/resend (429 when exceeded)
- Apple Sign-In and password reset remain deferred

---

## Deferred (not blocking launch)

| Topic | Notes |
|-------|-------|
| Comment moderation | Report/delete, admin tools |
| Like visibility | Show who liked vs counts only |
| Offline audio cache | Verse text cached in Hive; audio not yet |
| Share | Preferred channels TBD |
| Apple Sign-In / password reset | Deferred |
| Verse-synced audio | Bible Brain audio timings API — future enhancement |
| CDN/S3 for images | VM mount works for launch; CDN optional later |
| Full Bible seed | CLI supports `--limit 0`; startup defaults to John subset |

---

## Architecture notes

- **Feed**: cursor-paginated `GET /reels`, ordered by ascending id (manifest order)
- **Bible proxy**: client never holds Bible Brain keys; server proxies `/bible/*`
- **Mobile UI**: dark full-bleed cards, right-side action rail (Reels pattern), bottom sheet comments with threaded replies

## TDD coverage

- Server: feed pagination, reel likes, comments (including replies), comment likes, Bible Brain client, health
- Client: JSON model parsing, action bar widget, storage service
