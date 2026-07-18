import json
from pathlib import Path

from src.models import Reel
from src.seed import _dev_manifest_candidates, load_manifest_groups, resolve_manifest_path, seed_reels


def test_seeds_limited_groups_when_limit_is_set(db_session, tmp_path) -> None:
    manifest = {
        "groups": [
            {
                "reference": f"John 1:{index}",
                "book": "John",
                "chapter": 1,
                "start_verse": index,
                "end_verse": index,
                "slug": f"John_1_{index}-{index}",
            }
            for index in range(1, 6)
        ]
    }
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    count = seed_reels(db_session, limit=2, manifest_path=manifest_path, skip_if_populated=False)

    assert count == 2
    assert db_session.query(Reel).count() == 2


def test_seeds_all_groups_when_limit_is_zero(db_session, tmp_path) -> None:
    manifest = {
        "groups": [
            {
                "reference": "John 3:16",
                "book": "John",
                "chapter": 3,
                "start_verse": 16,
                "end_verse": 16,
                "slug": "John_3_16-16",
            },
            {
                "reference": "John 3:17",
                "book": "John",
                "chapter": 3,
                "start_verse": 17,
                "end_verse": 17,
                "slug": "John_3_17-17",
            },
        ]
    }
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    count = seed_reels(db_session, limit=0, manifest_path=manifest_path, skip_if_populated=False)

    assert count == 2


def test_skips_seed_when_reels_already_exist(db_session, tmp_path) -> None:
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(
        json.dumps(
            {
                "groups": [
                    {
                        "reference": "John 3:16",
                        "book": "John",
                        "chapter": 3,
                        "start_verse": 16,
                        "end_verse": 16,
                        "slug": "John_3_16-16",
                    }
                ]
            }
        ),
        encoding="utf-8",
    )
    seed_reels(db_session, limit=1, manifest_path=manifest_path, skip_if_populated=False)

    count = seed_reels(db_session, limit=1, manifest_path=manifest_path, skip_if_populated=True)

    assert count == 0


def test_tops_up_missing_groups_when_seed_limit_increases(db_session, tmp_path) -> None:
    manifest = {
        "groups": [
            {
                "reference": f"John 1:{index}",
                "book": "John",
                "chapter": 1,
                "start_verse": index,
                "end_verse": index,
                "slug": f"John_1_{index}-{index}",
            }
            for index in range(1, 5)
        ]
    }
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    first = seed_reels(db_session, limit=2, manifest_path=manifest_path, skip_if_populated=False)
    assert first == 2
    assert db_session.query(Reel).count() == 2

    added = seed_reels(db_session, limit=0, manifest_path=manifest_path, skip_if_populated=True)

    assert added == 2
    assert db_session.query(Reel).count() == 4


def test_loads_manifest_groups_from_file(tmp_path) -> None:
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(
        json.dumps({"groups": [{"slug": "John_1_1-1", "reference": "John 1:1"}]}),
        encoding="utf-8",
    )

    groups = load_manifest_groups(manifest_path)

    assert groups[0]["slug"] == "John_1_1-1"


def test_defaults_to_full_groups_manifest_before_john_sample() -> None:
    candidates = _dev_manifest_candidates()
    if not candidates:
        return
    assert candidates[0].name == "manifest.json"
    assert "groups" in str(candidates[0])


def test_resolve_manifest_path_prefers_bundled_manifest(tmp_path, monkeypatch) -> None:
    from src import seed as seed_module

    bundled = tmp_path / "data" / "manifest.json"
    bundled.parent.mkdir(parents=True)
    bundled.write_text(json.dumps({"groups": []}), encoding="utf-8")
    monkeypatch.setattr(seed_module, "BUNDLED_MANIFEST", bundled)

    assert resolve_manifest_path() == bundled
