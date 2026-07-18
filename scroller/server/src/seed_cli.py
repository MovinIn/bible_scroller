"""Seed reels from a pipeline manifest.

Examples:
  python -m src.seed_cli
  python -m src.seed_cli --manifest ../../pipeline/output/groups/manifest.json --limit 0
  python -m src.seed_cli --force
"""

from __future__ import annotations

import argparse
from pathlib import Path

from src.database import SessionLocal, init_db
from src.seed import FULL_MANIFEST, seed_reels


def main() -> None:
    parser = argparse.ArgumentParser(description="Seed Bible Scroller reels from manifest")
    parser.add_argument(
        "--manifest",
        type=Path,
        default=FULL_MANIFEST,
        help="Path to pipeline manifest JSON",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=20,
        help="Max groups to seed (0 = entire manifest)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Clear existing reels before seeding",
    )
    args = parser.parse_args()

    init_db()
    db = SessionLocal()
    try:
        if args.force:
            from src.models import Comment, CommentLike, Reel, ReelLike

            db.query(CommentLike).delete()
            db.query(Comment).delete()
            db.query(ReelLike).delete()
            db.query(Reel).delete()
            db.commit()

        count = seed_reels(
            db,
            limit=args.limit,
            manifest_path=args.manifest,
            skip_if_populated=not args.force,
        )
        print(f"Seeded {count} reels from {args.manifest}")
    finally:
        db.close()


if __name__ == "__main__":
    main()
