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


def test_resolves_esv_filesets_when_bible_data_is_object_not_list() -> None:
    """DBP v4 returns data as an object for /bibles/{id}; list indexing KeyErrors."""

    def handler(request: httpx.Request) -> httpx.Response:
        if _path_matches(request, "/bibles/ENGESV"):
            return httpx.Response(
                200,
                json={
                    "data": {
                        "abbr": "ENGESV",
                        "filesets": {
                            "dbp-prod": [
                                # Distinct from DEFAULT_FILESETS so parse bugs cannot pass via fallback.
                                {"id": "ENGESV_FROM_API", "type": "text_plain"},
                                {
                                    "id": "ENGESV_AUDIO_FROM_API",
                                    "type": "audio_drama",
                                    "segmentation_type": "chapter",
                                },
                            ],
                            "dbp-vid": [
                                {"id": "ENGESVP2DV", "type": "video_stream"},
                            ],
                        },
                    }
                },
            )
        raise AssertionError(f"Unexpected request: {request.method} {request.url}")

    client = BibleBrainClient(api_key="test-key", client=_mock_client(handler))
    filesets = client.resolve_filesets("esv")

    assert filesets["text"] == "ENGESV_FROM_API"
    assert filesets["audio"] == "ENGESV_AUDIO_FROM_API"


def test_uses_nt_text_fileset_when_john_is_requested() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if _path_matches(request, "/bibles/ENGESV"):
            return httpx.Response(
                200,
                json={
                    "data": {
                        "filesets": {
                            "dbp-prod": [
                                {"id": "ENGESVO_ET", "type": "text_plain"},
                                {"id": "ENGESVN_ET", "type": "text_plain"},
                                {"id": "ENGESVN2DA", "type": "audio_drama"},
                            ]
                        }
                    }
                },
            )
        if _path_matches(request, "/bibles/filesets/ENGESVN_ET/JHN/3"):
            return httpx.Response(
                200,
                json={"data": [{"verse_text": "For God so loved the world"}]},
            )
        if "ENGESVO_ET" in request.url.path:
            raise AssertionError("OT fileset must not be used for John")
        raise AssertionError(f"Unexpected request: {request.method} {request.url}")

    client = BibleBrainClient(api_key="test-key", client=_mock_client(handler))
    text = client.get_verse_text(
        book="John",
        chapter=3,
        start_verse=16,
        end_verse=16,
        version_id="esv",
    )

    assert text == "For God so loved the world"


def test_returns_esv_verse_text_when_bible_data_is_object() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if _path_matches(request, "/bibles/ENGESV"):
            return httpx.Response(
                200,
                json={
                    "data": {
                        "filesets": {
                            "dbp-prod": [
                                {"id": "ENGESVN_ET", "type": "text_plain"},
                                {"id": "ENGESVN2DA", "type": "audio_drama"},
                            ]
                        }
                    }
                },
            )
        if _path_matches(request, "/bibles/filesets/ENGESVN_ET/JHN/3"):
            return httpx.Response(
                200,
                json={"data": [{"verse_text": "For God so loved the world"}]},
            )
        raise AssertionError(f"Unexpected request: {request.method} {request.url}")

    client = BibleBrainClient(api_key="test-key", client=_mock_client(handler))
    text = client.get_verse_text(
        book="John",
        chapter=3,
        start_verse=16,
        end_verse=16,
        version_id="esv",
    )

    assert text == "For God so loved the world"


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


def test_prefers_nt_download_audio_over_ot_stream_when_john_is_requested() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if _path_matches(request, "/bibles/ENGKJV"):
            return httpx.Response(
                200,
                json={
                    "data": {
                        "filesets": {
                            "dbp-prod": [
                                {"id": "ENGKJVO2SA", "type": "audio_drama_stream"},
                                {"id": "ENGKJVN2DA", "type": "audio_drama"},
                                {"id": "ENGKJVN_ET", "type": "text_plain"},
                            ]
                        }
                    }
                },
            )
        if _path_matches(request, "/bibles/filesets/ENGKJVN2DA/JHN/3"):
            return httpx.Response(
                200,
                json={"data": [{"path": "https://cdn.example.com/kjv-john-3.mp3"}]},
            )
        if "ENGKJVO2SA" in request.url.path:
            raise AssertionError("OT stream fileset must not be used for John")
        raise AssertionError(f"Unexpected request: {request.method} {request.url}")

    client = BibleBrainClient(api_key="test-key", client=_mock_client(handler))
    url = client.get_chapter_audio_url(book="John", chapter=3, version_id="kjv")

    assert url == "https://cdn.example.com/kjv-john-3.mp3"


def test_skips_hls_playlist_url_and_uses_mp3_when_both_exist() -> None:
    calls: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if _path_matches(request, "/bibles/ENGWEB"):
            return httpx.Response(
                200,
                json={
                    "data": {
                        "filesets": {
                            "dbp-prod": [
                                {"id": "ENGWEBN2SA", "type": "audio_drama_stream"},
                                {"id": "ENGWEBN2DA", "type": "audio_drama"},
                                {"id": "ENGWEBN_ET", "type": "text_plain"},
                            ]
                        }
                    }
                },
            )
        if "/bibles/filesets/" in request.url.path:
            calls.append(request.url.path)
            if "ENGWEBN2SA" in request.url.path:
                return httpx.Response(
                    200,
                    json={
                        "data": [
                            {
                                "path": "https://4.dbt.io/api/bible/filesets/ENGWEBN2SA/JHN-3-1-/playlist.m3u8"
                            }
                        ]
                    },
                )
            if "ENGWEBN2DA" in request.url.path:
                return httpx.Response(
                    200,
                    json={"data": [{"path": "https://cdn.example.com/web-john-3.mp3"}]},
                )
        raise AssertionError(f"Unexpected request: {request.method} {request.url}")

    client = BibleBrainClient(api_key="test-key", client=_mock_client(handler))
    url = client.get_chapter_audio_url(book="John", chapter=3, version_id="web")

    assert url == "https://cdn.example.com/web-john-3.mp3"
    assert url.endswith(".mp3")


def test_falls_back_to_helloao_when_only_hls_audio_is_available() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if _path_matches(request, "/bibles/ENGWEB"):
            return httpx.Response(
                200,
                json={
                    "data": {
                        "filesets": {
                            "dbp-prod": [
                                {"id": "ENGWEBN2SA", "type": "audio_drama_stream"},
                                {"id": "ENGWEBN_ET", "type": "text_plain"},
                            ]
                        }
                    }
                },
            )
        if _path_matches(request, "/bibles/filesets/ENGWEBN2SA/JHN/3"):
            return httpx.Response(
                200,
                json={
                    "data": [
                        {
                            "path": "https://4.dbt.io/api/bible/filesets/ENGWEBN2SA/JHN-3-1-/playlist.m3u8"
                        }
                    ]
                },
            )
        raise AssertionError(f"Unexpected request: {request.method} {request.url}")

    client = BibleBrainClient(api_key="test-key", client=_mock_client(handler))
    url = client.get_chapter_audio_url(book="John", chapter=3, version_id="web")

    assert url == "https://audio.bible.helloao.org/api/BSB/JHN/3/audio/david.mp3"


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


def test_returns_default_esv_version_when_api_key_is_missing() -> None:
    client = BibleBrainClient(api_key="")

    versions = client.get_versions()

    assert versions[0] == {"version_id": "esv", "name": "English Standard Version"}
    assert {v["version_id"] for v in versions} >= {"esv", "kjv", "web"}


def test_returns_all_key_permitted_english_versions_in_picker() -> None:
    client = BibleBrainClient(api_key="")

    ids = {v["version_id"] for v in client.get_versions()}

    assert ids == {
        "esv",
        "kjv",
        "web",
        "nkjv",
        "nasb",
        "nlt",
        "nlh",
        "asv",
        "evd",
        "rev",
        "nlv",
    }
    assert "niv" not in ids


def test_maps_nkjv_and_nasb_to_bible_brain_abbrs() -> None:
    from src.services.bible_brain_client import VERSION_TO_BIBLE

    assert VERSION_TO_BIBLE["nkjv"] == "ENGNKJV"
    assert VERSION_TO_BIBLE["nasb"] == "ENGNAS"
    assert VERSION_TO_BIBLE["nlt"] == "ENGNLT"
    assert VERSION_TO_BIBLE["nlh"] == "ENGNLH"
    assert VERSION_TO_BIBLE["asv"] == "ENGASV"
    assert VERSION_TO_BIBLE["evd"] == "ENGEVD"
    assert VERSION_TO_BIBLE["rev"] == "ENGREV"
    assert VERSION_TO_BIBLE["nlv"] == "ENGNLV"


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
