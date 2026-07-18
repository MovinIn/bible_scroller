"""Refresh stored reel image URLs after pipeline images are synced."""

from __future__ import annotations

from src.database import SessionLocal
from src.models import Reel
from src.services.reel_images import reel_image_url


def main() -> None:
    db = SessionLocal()
    try:
        updated = 0
        for reel in db.query(Reel).yield_per(500):
            url = reel_image_url(reel.slug)
            if reel.image_url != url:
                reel.image_url = url
                updated += 1
        db.commit()
        sample = db.query(Reel).filter(Reel.book == "Genesis").first()
        print(f"updated {updated} image urls")
        if sample is not None:
            print(f"sample {sample.reference}: {sample.image_url}")
    finally:
        db.close()


if __name__ == "__main__":
    main()
