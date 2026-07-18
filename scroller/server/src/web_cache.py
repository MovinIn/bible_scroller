from __future__ import annotations

from starlette.responses import Response
from starlette.staticfiles import StaticFiles as StarletteStaticFiles

_IMMUTABLE_CACHE = "public, max-age=31536000, immutable"
_ENTRY_CACHE = "no-cache, must-revalidate"
# Pipeline reel images change in place at the same URL; keep a short TTL.
_PIPELINE_MEDIA_CACHE = "public, max-age=604800"

_ENTRY_FILES = frozenset(
    {
        "index.html",
        "flutter_bootstrap.js",
        "main.dart.js",
        "main.dart.wasm",
        "main.bookflow.js",
        "flutter_service_worker.js",
        "version.json",
        "manifest.json",
    }
)


def pipeline_media_cache_control() -> str:
    return _PIPELINE_MEDIA_CACHE


class CachedStaticFiles(StarletteStaticFiles):
    def __init__(self, *args, cache_control: str = _IMMUTABLE_CACHE, **kwargs) -> None:
        self._cache_control = cache_control
        super().__init__(*args, **kwargs)

    async def get_response(self, path: str, scope):
        response = await super().get_response(path, scope)
        if isinstance(response, Response):
            response.headers["Cache-Control"] = self._cache_control
        return response


def web_cache_headers(relative_path: str) -> dict[str, str]:
    normalized = relative_path.replace("\\", "/").lstrip("/")
    if normalized.startswith(("canvaskit/", "assets/", "icons/")):
        return {"Cache-Control": _IMMUTABLE_CACHE}
    filename = normalized.rsplit("/", 1)[-1]
    if filename in _ENTRY_FILES or normalized.endswith(".html"):
        return {"Cache-Control": _ENTRY_CACHE}
    if filename.endswith((".wasm", ".js", ".symbols", ".otf", ".ttf", ".frag", ".png", ".json")):
        return {"Cache-Control": _IMMUTABLE_CACHE}
    return {"Cache-Control": _ENTRY_CACHE}
