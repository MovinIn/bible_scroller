import json
from pathlib import Path
from unittest.mock import MagicMock

import httpx
import pytest

from src.bible_client import (
    BookInfo,
    BibleClient,
    chapter_cache_path,
    list_verse_numbers,
)
from src.manifest import build_manifest, format_reference, group_to_manifest_entry, write_manifest_atomic
from src.reference import VerseReference


SAMPLE_BOOKS_PAYLOAD = {
    "translation": {"id": "BSB"},
    "totalNumberOfVerses": 31086,
    "books": [
        {
            "id": "JHN",
            "name": "John",
            "commonName": "John",
            "order": 43,
            "numberOfChapters": 21,
        },
        {
            "id": "GEN",
            "name": "Genesis",
            "commonName": "Genesis",
            "order": 1,
            "numberOfChapters": 50,
        },
        {
            "id": "SNG",
            "name": "Song of Solomon",
            "commonName": "Song of Songs",
            "order": 22,
            "numberOfChapters": 8,
        },
    ],
}

SAMPLE_CHAPTER = {
    "chapter": {
        "content": [
            {"type": "verse", "number": 1, "content": ["First verse."]},
            {"type": "verse", "number": 2, "content": ["Second verse."]},
        ]
    }
}


def test_list_verse_numbers_returns_ordered_verse_numbers():
    numbers = list_verse_numbers(SAMPLE_CHAPTER)
    assert numbers == [1, 2]


def test_chapter_cache_path_uses_book_id_and_chapter_number(tmp_path):
    path = chapter_cache_path(tmp_path, "JHN", 3)
    assert path == tmp_path / "JHN" / "3.json"


def test_list_books_returns_sorted_book_info():
    client = BibleClient(client=MagicMock())
    client._books_payload = SAMPLE_BOOKS_PAYLOAD["books"]

    books = client.list_books()
    assert books == [
        BookInfo(name="Genesis", common_name="Genesis", id="GEN", number_of_chapters=50, order=1),
        BookInfo(
            name="Song of Solomon",
            common_name="Song of Songs",
            id="SNG",
            number_of_chapters=8,
            order=22,
        ),
        BookInfo(name="John", common_name="John", id="JHN", number_of_chapters=21, order=43),
    ]


def test_fetch_chapter_cached_reads_from_disk_when_cache_exists(tmp_path):
    http_client = MagicMock()
    client = BibleClient(client=http_client)
    cache_path = chapter_cache_path(tmp_path, "JHN", 3)
    cache_path.parent.mkdir(parents=True)
    cache_path.write_text(json.dumps(SAMPLE_CHAPTER), encoding="utf-8")

    payload = client.fetch_chapter_cached("JHN", 3, cache_dir=tmp_path, use_cache=True)

    assert payload == SAMPLE_CHAPTER
    http_client.get.assert_not_called()


def test_fetch_chapter_cached_returns_fetched_payload_when_cache_write_raises_oserror(
    tmp_path, monkeypatch
):
    http_client = MagicMock()
    response = MagicMock()
    response.status_code = 200
    response.json.return_value = SAMPLE_CHAPTER
    http_client.get.return_value = response
    client = BibleClient(client=http_client)

    def raise_permission_error(src, dst):
        raise PermissionError("file in use")

    monkeypatch.setattr("src.bible_client.os.replace", raise_permission_error)

    payload = client.fetch_chapter_cached("JHN", 3, cache_dir=tmp_path, use_cache=True)

    assert payload == SAMPLE_CHAPTER


def test_fetch_chapter_cached_writes_fresh_payload_to_disk(tmp_path):
    http_client = MagicMock()
    response = MagicMock()
    response.status_code = 200
    response.json.return_value = SAMPLE_CHAPTER
    http_client.get.return_value = response
    client = BibleClient(client=http_client)

    payload = client.fetch_chapter_cached("JHN", 3, cache_dir=tmp_path, use_cache=True)

    assert payload == SAMPLE_CHAPTER
    cache_path = chapter_cache_path(tmp_path, "JHN", 3)
    assert json.loads(cache_path.read_text(encoding="utf-8")) == SAMPLE_CHAPTER


def test_fetch_chapter_cached_recovers_from_corrupt_cache(tmp_path):
    http_client = MagicMock()
    response = MagicMock()
    response.status_code = 200
    response.json.return_value = SAMPLE_CHAPTER
    http_client.get.return_value = response
    client = BibleClient(client=http_client)

    cache_path = chapter_cache_path(tmp_path, "JHN", 3)
    cache_path.parent.mkdir(parents=True)
    cache_path.write_text("{not valid json", encoding="utf-8")

    payload = client.fetch_chapter_cached("JHN", 3, cache_dir=tmp_path, use_cache=True)

    assert payload == SAMPLE_CHAPTER
    assert json.loads(cache_path.read_text(encoding="utf-8")) == SAMPLE_CHAPTER
    http_client.get.assert_called_once()


def test_fetch_verse_text_uses_cache_without_http(tmp_path):
    http_client = MagicMock()
    client = BibleClient(client=http_client)
    client._book_id_cache = {"john": "JHN"}

    cache_path = chapter_cache_path(tmp_path, "JHN", 3)
    cache_path.parent.mkdir(parents=True)
    cache_path.write_text(
        json.dumps(
            {
                "chapter": {
                    "content": [
                        {"type": "verse", "number": 16, "content": ["For God so loved the world,"]},
                    ]
                }
            }
        ),
        encoding="utf-8",
    )

    reference = VerseReference(book="John", chapter=3, start_verse=16, end_verse=16)
    text = client.fetch_verse_text(reference, cache_dir=tmp_path, use_cache=True)

    assert text == "16 For God so loved the world,"
    http_client.get.assert_not_called()


def test_get_with_retry_succeeds_after_transient_429():
    http_client = MagicMock()
    bad_response = MagicMock()
    bad_response.status_code = 429
    good_response = MagicMock()
    good_response.status_code = 200
    good_response.json.return_value = SAMPLE_CHAPTER
    http_client.get.side_effect = [bad_response, good_response]

    client = BibleClient(client=http_client)
    payload = client.fetch_chapter("JHN", 3)

    assert payload == SAMPLE_CHAPTER
    assert http_client.get.call_count == 2


def test_get_with_retry_raises_after_persistent_500():
    http_client = MagicMock()
    bad_response = MagicMock()
    bad_response.status_code = 500
    bad_response.raise_for_status.side_effect = httpx.HTTPStatusError(
        "Server error",
        request=MagicMock(),
        response=bad_response,
    )
    http_client.get.return_value = bad_response

    client = BibleClient(client=http_client)
    with pytest.raises(httpx.HTTPStatusError):
        client.fetch_chapter("JHN", 3)

    assert http_client.get.call_count == 3


def test_format_reference_uses_dash_for_ranges():
    ref = VerseReference(book="John", chapter=3, start_verse=16, end_verse=20)
    assert format_reference(ref) == "John 3:16-20"


def test_format_reference_omits_dash_for_single_verse():
    ref = VerseReference(book="John", chapter=3, start_verse=16, end_verse=16)
    assert format_reference(ref) == "John 3:16"


def test_build_manifest_includes_group_stats():
    groups = [
        VerseReference(book="John", chapter=3, start_verse=1, end_verse=4),
        VerseReference(book="John", chapter=3, start_verse=5, end_verse=8),
    ]
    manifest = build_manifest(
        groups,
        min_size=4,
        max_size=5,
        books_processed=1,
        canonical_verse_total=31086,
    )

    assert manifest["translation"] == "BSB"
    assert manifest["grouping"] == {
        "min_size": 4,
        "max_size": 5,
        "strategy": "structure_aware",
    }
    assert manifest["stats"] == {
        "total_groups": 2,
        "total_verses": 8,
        "books": 1,
        "canonical_verse_total": 31086,
        "verse_count_delta": -31078,
    }
    assert manifest["groups"][0] == group_to_manifest_entry(1, groups[0])


def test_write_manifest_atomic_writes_complete_json(tmp_path):
    manifest = build_manifest(
        [VerseReference(book="John", chapter=3, start_verse=1, end_verse=2)],
        min_size=4,
        max_size=5,
        books_processed=1,
    )
    output_path = tmp_path / "groups" / "manifest.json"

    write_manifest_atomic(output_path, manifest)

    assert json.loads(output_path.read_text(encoding="utf-8")) == manifest
    assert not output_path.with_suffix(".json.tmp").exists()


def test_group_bible_collect_groups_uses_book_filter(tmp_path):
    from group_bible import collect_groups
    from src.verse_grouper import GroupingConfig

    bible = MagicMock()
    bible.list_books.return_value = [
        BookInfo(name="John", common_name="John", id="JHN", number_of_chapters=1, order=43),
        BookInfo(name="Genesis", common_name="Genesis", id="GEN", number_of_chapters=1, order=1),
    ]
    bible.fetch_chapter_cached.return_value = {
        "chapter": {
            "content": [
                {"type": "verse", "number": 1, "content": ["A"]},
                {"type": "verse", "number": 2, "content": ["B"]},
                {"type": "verse", "number": 3, "content": ["C"]},
                {"type": "verse", "number": 4, "content": ["D"]},
                {"type": "line_break"},
                {"type": "verse", "number": 5, "content": ["E"]},
            ]
        }
    }

    groups, books_processed = collect_groups(
        bible,
        book_filter="John",
        cache_dir=tmp_path,
        use_cache=True,
        config=GroupingConfig(min_group_size=4, max_group_size=5),
    )

    assert books_processed == 1
    assert len(groups) == 2
    assert groups[0].start_verse == 1
    assert groups[0].end_verse == 4
    assert groups[1].start_verse == 5
    assert groups[1].end_verse == 5
    bible.fetch_chapter_cached.assert_called_once()


def test_group_bible_collect_groups_matches_common_name(tmp_path):
    from group_bible import collect_groups
    from src.verse_grouper import GroupingConfig

    bible = MagicMock()
    bible.list_books.return_value = [
        BookInfo(
            name="Song of Solomon",
            common_name="Song of Songs",
            id="SNG",
            number_of_chapters=1,
            order=22,
        ),
    ]
    bible.fetch_chapter_cached.return_value = {
        "chapter": {
            "content": [{"type": "verse", "number": 1, "content": ["A"]}],
        }
    }

    groups, books_processed = collect_groups(
        bible,
        book_filter="Song of Songs",
        cache_dir=tmp_path,
        use_cache=True,
        config=GroupingConfig(min_group_size=4, max_group_size=5),
    )

    assert books_processed == 1
    assert len(groups) == 1
    assert groups[0].book == "Song of Solomon"


def test_collect_groups_writes_partial_manifest_after_first_book(tmp_path):
    from group_bible import collect_groups
    from src.verse_grouper import GroupingConfig

    output_path = tmp_path / "manifest.json"
    chapter_payload = {
        "chapter": {
            "content": [{"type": "verse", "number": 1, "content": ["A"]}],
        }
    }

    bible = MagicMock()
    bible.list_books.return_value = [
        BookInfo(name="Genesis", common_name="Genesis", id="GEN", number_of_chapters=1, order=1),
        BookInfo(name="John", common_name="John", id="JHN", number_of_chapters=1, order=43),
    ]

    def fetch_side_effect(book_id, chapter, **kwargs):
        if book_id == "JHN":
            raise RuntimeError("network failed on second book")
        return chapter_payload

    bible.fetch_chapter_cached.side_effect = fetch_side_effect

    with pytest.raises(RuntimeError, match="network failed"):
        collect_groups(
            bible,
            book_filter=None,
            cache_dir=tmp_path,
            use_cache=True,
            config=GroupingConfig(min_group_size=4, max_group_size=5),
            output_path=output_path,
        )

    manifest = json.loads(output_path.read_text(encoding="utf-8"))
    assert manifest["stats"]["books"] == 1
    assert manifest["stats"]["total_groups"] == 1
    assert manifest["groups"][0]["book"] == "Genesis"
