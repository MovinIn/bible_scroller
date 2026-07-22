from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, Response

from src.config import settings, validate_runtime_settings
from src.database import SessionLocal, init_db
from src.routes.auth import router as auth_router
from src.routes.reels import bible_router, comments_router, router as reels_router
from src.routes.users import router as users_router
from src.seed import seed_reels
from src.services.bible_brain_service import close_bible_client, warm_bible_client_cache
from src.services.mailer import build_mailer, set_mailer
from src.services.reel_images import pipeline_mount_root
from src.web_app import is_spa_fallback_path, resolve_web_root, web_index_path
from src.services.local_bible_text import clear_chapter_payload_cache
from src.web_cache import CachedStaticFiles, pipeline_media_cache_control, web_cache_headers


@asynccontextmanager
async def lifespan(_: FastAPI):
    validate_runtime_settings()
    # Tests inject CaptureMailer via set_mailer before the client starts.
    if settings.environment.lower() != "test":
        set_mailer(build_mailer())
    init_db()
    db = SessionLocal()
    try:
        seed_reels(db)
    finally:
        db.close()
    # Chapter JSON LRU is process-local; clear at startup so redeploys see new files.
    clear_chapter_payload_cache()
    warm_bible_client_cache()
    yield
    close_bible_client()


app = FastAPI(
    title="Bible Scroller API",
    description="Backend for the Bible Scroller app",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(reels_router)
app.include_router(comments_router)
app.include_router(bible_router)
app.include_router(users_router)

mount_root = pipeline_mount_root()
if mount_root.exists():
    app.mount(
        "/media/pipeline",
        CachedStaticFiles(
            directory=mount_root,
            cache_control=pipeline_media_cache_control(),
        ),
        name="pipeline-media",
    )


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


def _register_web_app() -> None:
    web_root = resolve_web_root()
    if web_root is None:
        return

    # Flutter web static assets (mounted before SPA catch-all).
    for mount_name in ("assets", "canvaskit", "icons"):
        asset_dir = web_root / mount_name
        if asset_dir.is_dir():
            app.mount(
                f"/{mount_name}",
                CachedStaticFiles(directory=asset_dir, mount_prefix=mount_name),
                name=f"web-{mount_name}",
            )

    @app.get("/", response_model=None)
    def web_index() -> Response:
        index = web_index_path()
        assert index is not None
        return FileResponse(index, headers=web_cache_headers("index.html"))

    @app.get("/{full_path:path}", response_model=None)
    def spa_fallback(full_path: str, request: Request) -> Response:
        candidate = web_root / full_path
        if candidate.is_file():
            return FileResponse(candidate, headers=web_cache_headers(full_path))
        if is_spa_fallback_path(request.url.path):
            index = web_index_path()
            assert index is not None
            return FileResponse(index, headers=web_cache_headers("index.html"))
        return HTMLResponse(status_code=404, content="Not Found")


_register_web_app()
