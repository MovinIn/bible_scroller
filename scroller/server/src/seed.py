from __future__ import annotations

import json
from pathlib import Path

from sqlalchemy.orm import Session

from src.book_ids import iq_book_id
from src.config import settings
from src.models import Reel
from src.services.reel_images import reel_image_url

# Bundled with the Docker image at build time (see Dockerfile).
BUNDLED_MANIFEST = Path(__file__).resolve().parent.parent / "data" / "manifest.json"
FULL_MANIFEST = BUNDLED_MANIFEST


def _dev_manifest_candidates() -> list[Path]:
    file_path = Path(__file__).resolve()
    if len(file_path.parents) <= 3:
        return []
    root = file_path.parents[3]
    # Prefer the full groups manifest so browsing is not limited to John samples.
    return [
        root / "pipeline" / "output" / "groups" / "manifest.json",
        root / "pipeline" / "output" / "test" / "manifest_john.json",
    ]


def resolve_manifest_path(path: str | Path | None = None) -> Path:
    if path is not None:
        return Path(path)
    if settings.seed_manifest_path.strip():
        return Path(settings.seed_manifest_path)
    if BUNDLED_MANIFEST.exists():
        return BUNDLED_MANIFEST
    for candidate in _dev_manifest_candidates():
        if candidate.exists():
            return candidate
    return Path("__missing__manifest__.json")


def load_manifest_groups(manifest_path: Path) -> list[dict]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    return manifest["groups"]


def seed_reels(
    db: Session,
    *,
    limit: int | None = None,
    manifest_path: Path | None = None,
    skip_if_populated: bool = True,
) -> int:
    effective_limit = settings.seed_limit if limit is None else limit
    path = resolve_manifest_path(manifest_path)

    if path.exists():
        groups = load_manifest_groups(path)
        samples = groups if effective_limit <= 0 else groups[:effective_limit]
    else:
        # No manifest available — do not seed legacy John samples ahead of Genesis.
        samples = []

    existing_slugs = {slug for (slug,) in db.query(Reel.slug).all()}
    if skip_if_populated and existing_slugs and all(entry["slug"] in existing_slugs for entry in samples):
        return 0

    added = 0
    for entry in samples:
        slug = entry["slug"]
        if slug in existing_slugs:
            continue
        db.add(
            Reel(
                reference=entry["reference"],
                book=entry["book"],
                chapter=entry["chapter"],
                start_verse=entry["start_verse"],
                end_verse=entry["end_verse"],
                slug=slug,
                image_url=reel_image_url(slug),
                iq_book_id=iq_book_id(entry["book"]),
            )
        )
        added += 1

    if added:
        db.commit()
    return added
