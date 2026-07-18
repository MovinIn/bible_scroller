"""Delete reels by slug (and cascade likes/comments)."""

from __future__ import annotations

import argparse

from src.database import SessionLocal
from src.models import Reel


def main() -> None:
    parser = argparse.ArgumentParser(description="Delete reels by slug")
    parser.add_argument("slugs", nargs="+", help="Reel slugs to delete")
    args = parser.parse_args()

    db = SessionLocal()
    try:
        deleted = (
            db.query(Reel)
            .filter(Reel.slug.in_(args.slugs))
            .delete(synchronize_session=False)
        )
        db.commit()
        print(f"deleted {deleted} reels: {', '.join(args.slugs)}")
        first = db.query(Reel).order_by(Reel.id.asc()).first()
        if first is not None:
            print(f"first reel now: {first.reference} (id={first.id})")
    finally:
        db.close()


if __name__ == "__main__":
    main()
