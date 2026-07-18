from __future__ import annotations

from pathlib import Path

from src.config import settings
from src.services.pipeline_images import resolve_pipeline_image_url

REPO_ROOT = Path(__file__).resolve().parents[3] if len(Path(__file__).resolve().parents) > 3 else Path("/")
PIPELINE_OUTPUT = REPO_ROOT / "pipeline" / "output"
DEFAULT_PIPELINE_ROOTS = [
    Path("/output"),
    PIPELINE_OUTPUT / "test" / "images",
    PIPELINE_OUTPUT / "prod",
    PIPELINE_OUTPUT,
]


def pipeline_search_roots() -> list[Path]:
    if settings.pipeline_images_roots.strip():
        return [Path(part.strip()) for part in settings.pipeline_images_roots.split(";") if part.strip()]
    return DEFAULT_PIPELINE_ROOTS


def pipeline_mount_root() -> Path:
    if settings.pipeline_mount_root.strip():
        return Path(settings.pipeline_mount_root)
    return PIPELINE_OUTPUT


def reel_image_url(slug: str) -> str:
    relative = resolve_pipeline_image_url(
        slug,
        search_roots=pipeline_search_roots(),
        mount_root=pipeline_mount_root(),
        media_base="/media/pipeline",
        placeholder_builder=lambda value: f"https://picsum.photos/seed/{value}/832/1216",
    )
    if relative.startswith("http"):
        return relative
    return f"{settings.media_base_url.rstrip('/')}{relative}"
