from __future__ import annotations

import json

import httpx

from src.book_ids import dbp_book_id
from src.services.bible_brain_client import (
    BibleBrainClient,
    _extract_audio_url,
    _extract_verse_text,
    _flatten_filesets,
)


def _mock_client(handler) -> httpx.Client:
    transport = httpx.MockTransport(handler)
    return httpx.Client(base_url="https://4.dbt.io/api", transport=transport)


def _path_matches(request: httpx.Request, suffix: str) -> bool:
    return request.url.path.endswith(suffix)


def test_returns_jhn_when_book_is_john() -> None:
    assert dbp_book_id("John") == "JHN"


def test_resolves_niv_text_fileset_when_bible_metadata_is_fetched() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if _path_matches(request, "/bibles/ENGNIV"):
            return httpx.Response(
                200,
                json={
                    "data": [
                        {
                            "filesets": {
                                "dbp-prod": [
                                    {"id": "ENGNIV", "type": "text_plain", "segmentation_type": None},
                                    {
                                        "id": "ENGNIVN2DA",
                                        "type": "audio",
                                        "segmentation_type": "chapter",
                                    },
                                ]
                            }
                        }
                    ]
                },
            )
        raise AssertionError(f"Unexpected request: {request.method} {request.url}")

    client = BibleBrainClient(api_key="test-key", client=_mock_client(handler))
    filesets = client.resolve_filesets("niv")

    assert filesets["text"] == "ENGNIV"


def test_returns_verse_range_text_when_john_1_reference_is_requested() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if _path_matches(request, "/bibles/ENGNIV"):
            return httpx.Response(
                200,
                json={
                    "data": [
                        {
                            "filesets": {
                                "dbp-prod": [
                                    {"id": "ENGNIV", "type": "text_plain"},
                                    {"id": "ENGNIVN2DA", "type": "audio", "segmentation_type": "chapter"},
                                ]
                            }
                        }
                    ]
                },
            )
        if _path_matches(request, "/bibles/filesets/ENGNIV/JHN/1"):
            return httpx.Response(
                200,
                json={
                    "data": [
                        {"verse_start": 1, "verse_text": "In the beginning was the Word,"},
                        {"verse_start": 2, "verse_text": "He was with God in the beginning."},
                    ]
                },
            )
        raise AssertionError(f"Unexpected request: {request.method} {request.url}")

    client = BibleBrainClient(api_key="test-key", client=_mock_client(handler))
    text = client.get_verse_text(
        book="John",
        chapter=1,
        start_verse=1,
        end_verse=2,
        version_id="niv",
    )

    assert text == "In the beginning was the Word, He was with God in the beginning."


def test_returns_chapter_audio_url_when_john_3_is_requested() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if _path_matches(request, "/bibles/ENGNIV"):
            return httpx.Response(
                200,
                json={
                    "data": [
                        {
                            "filesets": {
                                "dbp-prod": [
                                    {"id": "ENGNIV", "type": "text_plain"},
                                    {"id": "ENGNIVN2DA", "type": "audio", "segmentation_type": "chapter"},
                                ]
                            }
                        }
                    ]
                },
            )
        if _path_matches(request, "/bibles/filesets/ENGNIVN2DA/JHN/3"):
            return httpx.Response(
                200,
                json={
                    "data": [
                        {"path": "https://cdn.example.com/jhn-3.mp3"},
                    ]
                },
            )
        raise AssertionError(f"Unexpected request: {request.method} {request.url}")

    client = BibleBrainClient(api_key="test-key", client=_mock_client(handler))
    url = client.get_chapter_audio_url(book="John", chapter=3, version_id="niv")

    assert url == "https://cdn.example.com/jhn-3.mp3"


def test_returns_cached_verse_text_when_api_key_is_missing(tmp_path, monkeypatch) -> None:
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
                },
                "thisChapterAudioLinks": {
                    "david": "https://audio.bible.helloao.org/api/BSB/JHN/3/audio/david.mp3",
                },
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(
        "src.services.bible_brain_client.settings.chapter_cache_root",
        str(tmp_path),
    )

    client = BibleBrainClient(api_key="")

    text = client.get_verse_text(
        book="John",
        chapter=3,
        start_verse=16,
        end_verse=16,
        version_id="niv",
    )

    assert "For God so loved the world" in text
    assert "BIBLE_BRAIN_API_KEY" not in text


def test_returns_cached_audio_url_when_api_key_is_missing(tmp_path, monkeypatch) -> None:
    chapter_path = tmp_path / "JHN" / "3.json"
    chapter_path.parent.mkdir(parents=True)
    chapter_path.write_text(
        json.dumps(
            {
                "chapter": {"content": []},
                "thisChapterAudioLinks": {
                    "david": "https://audio.bible.helloao.org/api/BSB/JHN/3/audio/david.mp3",
                },
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(
        "src.services.bible_brain_client.settings.chapter_cache_root",
        str(tmp_path),
    )

    client = BibleBrainClient(api_key="")
    url = client.get_chapter_audio_url(book="John", chapter=3, version_id="niv")

    assert url == "https://audio.bible.helloao.org/api/BSB/JHN/3/audio/david.mp3"


def test_returns_default_niv_version_when_api_key_is_missing() -> None:
    client = BibleBrainClient(api_key="")

    versions = client.get_versions()

    assert versions == [{"version_id": "niv", "name": "New International Version"}]


def test_extracts_verse_text_from_chapter_payload() -> None:
    payload = {
        "data": [
            {"verse_text": "For God so loved the world"},
            {"verse_text": "that he gave his one and only Son."},
        ]
    }

    assert _extract_verse_text(payload) == "For God so loved the world that he gave his one and only Son."


def test_extracts_audio_url_from_chapter_payload() -> None:
    payload = {"data": [{"path": "https://cdn.example.com/audio.mp3"}]}

    assert _extract_audio_url(payload) == "https://cdn.example.com/audio.mp3"


def test_flattens_nested_fileset_groups() -> None:
    raw = {
        "dbp-prod": [{"id": "ENGNIV", "type": "text_plain"}],
        "dbp-vid": [{"id": "ENGNIVN2DA", "type": "audio"}],
    }

    flattened = _flatten_filesets(raw)

    assert [item["id"] for item in flattened] == ["ENGNIV", "ENGNIVN2DA"]
