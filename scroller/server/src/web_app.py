from __future__ import annotations

from pathlib import Path

_SERVER_ROOT = Path(__file__).resolve().parent.parent

_API_PREFIXES = (
    "/reels",
    "/comments",
    "/bible",
    "/users",
    "/auth",
    "/health",
    "/media",
    "/docs",
    "/openapi.json",
    "/redoc",
    "/assets",
    "/canvaskit",
    "/icons",
    "/favicon.ico",
    "/manifest.json",
    "/flutter_bootstrap.js",
    "/flutter.js",
    "/flutter_service_worker.js",
    "/main.dart.js",
    "/version.json",
)


def resolve_web_root() -> Path | None:
    candidate = _SERVER_ROOT / "static" / "web"
    if candidate.is_dir() and (candidate / "index.html").is_file():
        return candidate
    return None


def web_index_path() -> Path | None:
    root = resolve_web_root()
    if root is None:
        return None
    return root / "index.html"


def is_spa_fallback_path(path: str) -> bool:
    if path == "/":
        return True
    normalized = path if path.startswith("/") else f"/{path}"
    for prefix in _API_PREFIXES:
        if normalized == prefix or normalized.startswith(f"{prefix}/"):
            return False
    # Flutter hashed assets live under /assets/… already excluded; block dotted static files
    last_segment = normalized.rsplit("/", 1)[-1]
    if "." in last_segment:
        return False
    return True
