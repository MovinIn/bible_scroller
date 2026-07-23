# Deploy reference (bscroller VM)

Canonical long-form docs: [`scroller/deploy/DEPLOY.md`](../../../scroller/deploy/DEPLOY.md).

## Targets

| Item | Value |
|------|--------|
| Host | `opc@192.9.142.147` |
| App URL | `https://bscroller.navedu.uk/` |
| Image | `movinin/apps:bscroller_backend` |
| Platform | `linux/arm64` |
| Compose service | `bscroller` |
| Health | `https://bscroller.navedu.uk/health` |

## 1. Flutter web → server static

From repo root (PowerShell):

```powershell
cd scroller/client
flutter build web --release --no-tree-shake-icons --dart-define=API_BASE_URL=
Remove-Item -Recurse -Force ..\server\static\web -ErrorAction SilentlyContinue
Copy-Item -Recurse build\web ..\server\static\web
cd ../..
```

Default renderer: **CanvasKit**. Only add `--wasm` if the user explicitly requests it.

## 2. Build and push image (local Docker)

Requires Docker Desktop / buildx with ARM64 support:

```powershell
docker buildx build --platform linux/arm64 `
  -t movinin/apps:bscroller_backend `
  --push ./scroller/server
```

## 2b. Fallback — build on VM

When local Docker is unavailable (after `static/web` is synced into `scroller/server`):

```powershell
tar -cf bscroller-server.tar -C scroller/server .
scp bscroller-server.tar opc@192.9.142.147:~/
```

On the VM:

```bash
mkdir -p ~/bscroller-build && tar -xf ~/bscroller-server.tar -C ~/bscroller-build
cd ~/bscroller-build && docker build -t movinin/apps:bscroller_backend .
cd ~ && docker compose up -d bscroller
docker exec bscroller alembic upgrade head
```

## 3. Roll out (image already on Docker Hub)

```bash
ssh opc@192.9.142.147
cd ~
docker compose pull bscroller
docker compose up -d bscroller
docker exec bscroller alembic upgrade head
docker logs --tail 80 bscroller
```

Reload nginx only if vhost changed (normal app deploys usually skip):

```bash
docker exec nginx-proxy nginx -t && docker exec nginx-proxy nginx -s reload
```

## 4. Smoke tests

```bash
curl -sf https://bscroller.navedu.uk/health
curl -sf "https://bscroller.navedu.uk/reels?limit=1"
curl -sf https://bscroller.navedu.uk/bible/versions
curl -sf https://bscroller.navedu.uk/ | head
```

Expect: health `{"status":"ok"}`, reels JSON with items, HTML index for Flutter web.

## 5. Cloudflare edge cache (after web static is live)

CanvasKit `.wasm` is edge-cached (~31 days). After shipping a new Flutter web bundle, purge so visitors are not stuck on stale renderer files. Full detail: [`DEPLOY.md` §1b](../../../scroller/deploy/DEPLOY.md).

**Required** when the web bundle changed this deploy. `CLOUDFLARE_API_TOKEN` must already be in the **local shell env** (Zone Cache Purge). Never ask the user to paste the token into chat. If the token is missing → **fail the deploy** unless the user opted out with `skip-cdn` / `no-cdn` / `cdn:false`.

```powershell
# Token already set out-of-band (do not paste into chat):
# $env:CLOUDFLARE_API_TOKEN = '...'
if ([string]::IsNullOrWhiteSpace($env:CLOUDFLARE_API_TOKEN)) {
  throw 'CLOUDFLARE_API_TOKEN missing after web deploy — set it locally or pass skip-cdn'
}
powershell -File scroller/deploy/purge-cloudflare-flutter-static.ps1
powershell -File scroller/deploy/verify-cloudflare-cache.ps1
```

Expect verify: wasm follow-up `CF-Cache-Status: HIT`; `main.dart.js` not year-long immutable.

One-time (if wasm is `DYNAMIC`): run `apply-cloudflare-cache-rules.ps1` per §1b, then verify.

## Security

- Do not print or commit contents of `~/.env`, certs, or SSH private keys.
- Do not set `ENVIRONMENT=production` without SMTP configured (API refuses to start).
