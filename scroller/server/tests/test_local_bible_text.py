import json
from pathlib import Path

from src.services.local_bible_text import extract_verse_range_text, load_chapter_payload


def test_extracts_verse_range_text_from_helloao_chapter_payload() -> None:
    payload = {
        "chapter": {
            "content": [
                {"type": "verse", "number": 16, "content": ["For God so loved the world"]},
                {"type": "verse", "number": 17, "content": ["that He gave His Son."]},
            ]
        }
    }

    text = extract_verse_range_text(payload, start_verse=16, end_verse=17)

    assert text == "16 For God so loved the world\n17 that He gave His Son."


def test_loads_chapter_payload_from_cache_directory(tmp_path: Path) -> None:
    chapter_path = tmp_path / "JHN" / "3.json"
    chapter_path.parent.mkdir(parents=True)
    chapter_path.write_text(
        json.dumps(
            {
                "chapter": {
                    "content": [
                        {
                            "type": "verse",
                            "number": 16,
                            "content": ["For God so loved the world"],
                        }
                    ]
                }
            }
        ),
        encoding="utf-8",
    )

    payload = load_chapter_payload(tmp_path, book_id="JHN", chapter=3)

    assert payload is not None
    assert extract_verse_range_text(payload, start_verse=16, end_verse=16).endswith(
        "For God so loved the world"
    )


def test_returns_none_when_chapter_cache_file_is_missing(tmp_path: Path) -> None:
    assert load_chapter_payload(tmp_path, book_id="JHN", chapter=3) is None
