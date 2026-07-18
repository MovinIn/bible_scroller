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
flutter build web --release --dart-define=API_BASE_URL=
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

## Security

- Do not print or commit contents of `~/env`, certs, or SSH private keys.
- Do not set `ENVIRONMENT=production` without SMTP configured (API refuses to start).
