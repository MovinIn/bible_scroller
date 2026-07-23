# Web static bundle

Flutter web build output is copied here as `web/` and served by FastAPI at `/`.

## Build and sync

From the repo (PowerShell):

```powershell
cd scroller/client
flutter build web --release --no-tree-shake-icons --dart-define=API_BASE_URL=
Remove-Item -Recurse -Force ..\server\static\web -ErrorAction SilentlyContinue
Copy-Item -Recurse build\web ..\server\static\web
```

Empty `API_BASE_URL` makes the browser use the page origin (same host as the API).

Then rebuild the backend image so `static/web` is included.
