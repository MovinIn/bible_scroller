from pathlib import Path

from src.services.pipeline_images import find_pipeline_image, resolve_pipeline_image_url


def test_returns_newest_match_when_multiple_slug_images_exist(tmp_path) -> None:
    images_dir = tmp_path / "test" / "images"
    images_dir.mkdir(parents=True)
    (images_dir / "John_3_16-16_20260710T012000Z.png").write_bytes(b"a")
    newest = images_dir / "John_3_16-16_20260710T012044Z.png"
    newest.write_bytes(b"b")

    found = find_pipeline_image("John_3_16-16", [tmp_path])

    assert found == newest


def test_returns_media_url_when_slug_image_exists(tmp_path) -> None:
    images_dir = tmp_path / "test" / "images"
    images_dir.mkdir(parents=True)
    (images_dir / "John_3_16-16_20260710T012044Z.png").write_bytes(b"png")

    url = resolve_pipeline_image_url(
        "John_3_16-16",
        search_roots=[images_dir],
        mount_root=tmp_path,
        media_base="/media/pipeline",
    )

    assert url == "/media/pipeline/test/images/John_3_16-16_20260710T012044Z.png"


def test_returns_placeholder_when_slug_image_is_missing(tmp_path) -> None:
    url = resolve_pipeline_image_url(
        "Missing_1_1-1",
        search_roots=[tmp_path],
        mount_root=tmp_path,
        placeholder_builder=lambda slug: f"placeholder:{slug}",
    )

    assert url == "placeholder:Missing_1_1-1"
