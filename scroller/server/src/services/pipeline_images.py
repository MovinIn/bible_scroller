from __future__ import annotations

from collections.abc import Callable
from pathlib import Path


def find_pipeline_image(slug: str, search_roots: list[Path]) -> Path | None:
    pattern = f"{slug}_*.png"
    for root in search_roots:
        if not root.exists():
            continue
        matches = sorted(root.rglob(pattern))
        if matches:
            return matches[-1]
    return None


def resolve_pipeline_image_url(
    slug: str,
    *,
    search_roots: list[Path],
    mount_root: Path,
    media_base: str = "/media/pipeline",
    placeholder_builder: Callable[[str], str] | None = None,
) -> str:
    image_path = find_pipeline_image(slug, search_roots)
    if image_path is None:
        if placeholder_builder is not None:
            return placeholder_builder(slug)
        return f"https://picsum.photos/seed/{slug}/832/1216"

    relative = image_path.relative_to(mount_root)
    return f"{media_base.rstrip('/')}/{relative.as_posix()}"
