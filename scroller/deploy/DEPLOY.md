# Bscroller production deploy (navedu.uk VM)

Production follows the same pattern as `prequests`, `cevents`, and `bverse` on `192.9.142.147`:

- Central `~/docker-compose.yml` on user `opc`
- `nginx-proxy` container terminates TLS (Cloudflare origin certs)
- App container **`bscroller`** exposes port 8000 on the Docker network only
- Host Postgres at `172.18.0.1:5432`
- Reel images: read-only mount of `/home/opc/data/bscroller/output` (pipeline **output** folder only — no pipeline runner on VM)

## Prerequisites

- Cloudflare DNS: `bscroller` A → `192.9.142.147` (proxied)
- Cloudflare SSL mode: **Full (strict)**
- Origin cert/key installed on VM as `~/certs/bscroller_cert.pem` and `~/certs/bscroller_key.pem` (key `chmod 600`)
- Docker Hub push access for `movinin/apps:bscroller_backend`
- **Bible Brain API key** from https://4.dbt.io/api_key/request

**Security:** Never commit TLS keys, SSH keys, or `~/env` to git.

---

## 1. Build and push image (local machine, ARM64)

The VM is `aarch64`. Include the Flutter web bundle so `https://bscroller.navedu.uk/` serves the app:

```bash
# From repo root — build web (empty API_BASE_URL = same origin)
cd scroller/client
flutter build web --release --dart-define=API_BASE_URL=
# Sync into the Docker build context (PowerShell)
Remove-Item -Recurse -Force ..\server\static\web -ErrorAction SilentlyContinue
Copy-Item -Recurse build\web ..\server\static\web
cd ../..
```

### Web renderer benchmark (2026-07-18)

Measured release build artifacts on this project:

| Build | Primary runtime payload | Notes |
|-------|-------------------------|-------|
| **CanvasKit (default)** | `main.dart.js` ~2.9 MB + `canvaskit.wasm` ~7.0 MB ≈ **10 MB** | Best cross-browser compatibility; current production default |
| **`--wasm` (skwasm)** | `main.dart.wasm` ~2.4 MB + `skwasm.wasm` ~3.4 MB ≈ **5.8 MB** | ~42% smaller cold download on WASM-capable Chrome; includes JS fallback bundle |

**Recommendation:** Keep the default CanvasKit build for production until skwasm is validated on target devices. To try skwasm:

```bash
flutter build web --release --wasm --dart-define=API_BASE_URL=
```

The server now serves immutable long-cache headers for `/canvaskit/**`, `/assets/**`, and `/icons/**` so repeat visits load from disk/CDN cache. Entry files (`index.html`, `flutter_bootstrap.js`, `main.dart.js`) stay `no-cache` for safe deploys.

```bash
docker buildx build --platform linux/arm64 \
  -t movinin/apps:bscroller_backend \
  --push ./scroller/server
```

If Docker Desktop is not running locally, see **§2b** to build on the VM instead (sync `static/web` before packing the server source).

---

## 2. Host Postgres (one-time, on VM)

Uses the shared `db_user` account (same as `cevents` / `bverse`), not a separate Postgres role. Docker network `172.16.0.0/12` is already allowed in `pg_hba.conf`.

```bash
ssh -i prequests_private.key opc@192.9.142.147
bash ~/vm-setup-postgres.sh   # creates bscroller DB, grants db_user
bash ~/vm-fix-db-access.sh    # sets BSCROLLER_DATABASE_URL from CEVENTS_SQL_URL pattern
```

Or manually:

```bash
sudo -u postgres psql -c "CREATE DATABASE bscroller OWNER db_user;"
```

Add to `~/env`:

```env
BSCROLLER_DATABASE_URL=postgresql://db_user:...@172.18.0.1:5432/bscroller?sslmode=disable
BIBLE_BRAIN_API_KEY=your_bible_brain_key
MEDIA_BASE_URL=https://bscroller.navedu.uk
GOOGLE_CLIENT_IDS=315895045315-54809ltm3mnp79qurdl7512c55mvbveo.apps.googleusercontent.com,315895045315-5rtkbs5sve6c3jac9c8hh9m2i58gvrq7.apps.googleusercontent.com,315895045315-e90fn22s1q3dghmc6u7neqae3668lqnc.apps.googleusercontent.com
JWT_SECRET=your-32-plus-char-secret

Ensure `~/docker-compose.yml` passes `GOOGLE_CLIENT_IDS` and `JWT_SECRET` into the `bscroller` service (see `docker-compose.snippet.yml`). Do **not** set `ENVIRONMENT=production` until `SMTP_HOST` is configured — the API refuses to start otherwise.
```

Run migrations after first deploy:

```bash
docker exec bscroller alembic upgrade head
```

---

## 2b. Build on VM (when local Docker Desktop is unavailable)

```bash
# From dev machine — pack and upload server source
tar -cf bscroller-server.tar -C scroller/server .
scp bscroller-server.tar opc@192.9.142.147:~/
ssh opc@192.9.142.147
mkdir -p ~/bscroller-build && tar -xf ~/bscroller-server.tar -C ~/bscroller-build
cd ~/bscroller-build && docker build -t movinin/apps:bscroller_backend .
cd ~ && docker compose up -d bscroller
docker exec bscroller alembic upgrade head
```

---

## 3. Output folder (images only)

```bash
mkdir -p /home/opc/data/bscroller/output
```

Sync from dev machine (example — ~2 GB):

```bash
rsync -avz pipeline/output/ opc@192.9.142.147:/home/opc/data/bscroller/output/
```

---

## 4. TLS certs on VM

```bash
# After placing files in ~/certs/
chmod 644 ~/certs/bscroller_cert.pem
chmod 600 ~/certs/bscroller_key.pem
```

---

## 5. Nginx vhost

Copy [`nginx/bscroller.conf`](nginx/bscroller.conf) to `~/nginx/conf/bscroller.conf`.

**Important:** Reload nginx only **after** the `bscroller` container is running (otherwise upstream resolution fails):

```bash
docker compose up -d bscroller
docker exec nginx-proxy nginx -t
docker exec nginx-proxy nginx -s reload
```

---

## 6. Docker Compose service

Append the block from [`docker-compose.snippet.yml`](docker-compose.snippet.yml) to `~/docker-compose.yml`, then:

```bash
cd ~
docker compose pull bscroller   # skip if built locally on VM
docker compose up -d bscroller
docker exec bscroller alembic upgrade head
docker logs -f bscroller
```

---

## 7. Smoke tests

```bash
curl -sf https://bscroller.navedu.uk/health
curl -sf "https://bscroller.navedu.uk/reels?limit=1"
curl -sf https://bscroller.navedu.uk/bible/versions
curl -sf "https://bscroller.navedu.uk/bible/verse?book=John&chapter=3&start_verse=16&end_verse=16&version_id=niv"
# Browser UI (Flutter web index)
curl -sf https://bscroller.navedu.uk/ | head
```

In a browser: open `https://bscroller.navedu.uk/`, scroll, reload — should resume via `bscroller_last_reel_id` cookie.

Optional full seed (entire manifest):

```bash
docker exec bscroller python -m src.seed_cli --limit 0 --force
```

---

## 8. Flutter release client

```bash
cd scroller/client
flutter build apk --release --dart-define=API_BASE_URL=https://bscroller.navedu.uk
```

---

## Manual checklist (your step)

1. Obtain `BIBLE_BRAIN_API_KEY` at https://4.dbt.io/api_key/request
2. Add `BSCROLLER_DATABASE_URL`, `BIBLE_BRAIN_API_KEY`, `MEDIA_BASE_URL` to `~/env`
3. Create Postgres DB `bscroller` (or run `~/vm-setup-postgres.sh`)
4. Build/push ARM64 image (`§1` or `§2b`)
5. Rsync `pipeline/output/` → `/home/opc/data/bscroller/output/`
6. `docker compose up -d bscroller` then `alembic upgrade head`
7. `docker exec nginx-proxy nginx -s reload` (after container exists)
8. Run smoke tests (`§7`)
9. Build Flutter release with production API URL (`§8`)

---

## Local development (not VM)

```bash
cd scroller
docker compose -f docker-compose.dev.yml up -d --build
```

See [../README.md](../README.md) for Flutter and bare-metal dev.

---

## Rollback

```bash
docker compose stop bscroller
# Remove bscroller service block from ~/docker-compose.yml
rm ~/nginx/conf/bscroller.conf
docker exec nginx-proxy nginx -s reload
```

Other services (`prequests-backend`, `cevents-backend`, etc.) are unaffected.
