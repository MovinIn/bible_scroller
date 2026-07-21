from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import httpx

from src.book_ids import IQ_BOOK_IDS, dbp_book_id
from src.config import settings
from src.services.local_bible_text import (
    extract_chapter_audio_url,
    extract_verse_range_text,
    load_chapter_payload,
)

# Versions confirmed readable by the production free key (NIV not permitted).
DEFAULT_VERSIONS: list[dict[str, str]] = [
    {"version_id": "esv", "name": "English Standard Version"},
    {"version_id": "kjv", "name": "King James Version"},
    {"version_id": "web", "name": "World English Bible"},
    {"version_id": "nkjv", "name": "New King James Version"},
    {"version_id": "nasb", "name": "New American Standard Bible"},
    {"version_id": "nlt", "name": "New Living Translation"},
    {"version_id": "nlh", "name": "New Living Translation (her.BIBLE)"},
    {"version_id": "asv", "name": "American Standard Version"},
    {"version_id": "evd", "name": "English Version for the Deaf"},
    {"version_id": "rev", "name": "Revised Version 1885"},
    {"version_id": "nlv", "name": "New Life Version"},
]

VERSION_TO_BIBLE: dict[str, str] = {
    "esv": "ENGESV",
    "kjv": "ENGKJV",
    "web": "ENGWEB",
    "nkjv": "ENGNKJV",
    "nasb": "ENGNAS",
    "nlt": "ENGNLT",
    "nlh": "ENGNLH",
    "asv": "ENGASV",
    "evd": "ENGEVD",
    "rev": "ENGREV",
    "nlv": "ENGNLV",
    # Kept for callers that still request niv; may 403 depending on key rights.
    "niv": "ENGNIV",
}

DEFAULT_FILESETS: dict[str, dict[str, str]] = {
    "esv": {"text": "ENGESVN_ET", "audio": "ENGESVN2DA"},
    "kjv": {"text": "ENGKJVN_ET", "audio": "ENGKJVN2DA"},
    "web": {"text": "ENGWEBN_ET", "audio": "ENGWEBN2DA"},
    "nkjv": {"text": "ENGNKJN_ET", "audio": "ENGNKJN1DA"},
    "nasb": {"text": "ENGNASN_ET", "audio": ""},
    "nlt": {"text": "ENGNLTN_ET", "audio": "ENGNLTN2DA"},
    "nlh": {"text": "ENGNLHN_ET", "audio": "ENGNLHN1DA"},
    "asv": {"text": "ENGASV", "audio": ""},
    "evd": {"text": "ENGEVD", "audio": ""},
    "rev": {"text": "ENGREVN_ET", "audio": ""},
    "nlv": {"text": "ENGNLV", "audio": "ENGNLVN2DA"},
    "niv": {"text": "ENGNIV", "audio": "ENGNIVN2DA"},
}

# ENGKJVN2DA / ENGKJVO2SA — testament letter + quality digit + DA (download) or SA (stream).
_AUDIO_FILESET_MARK = re.compile(r"([NO])(\d)([DS]A)\b", re.IGNORECASE)


class BibleBrainClient:
    API_VERSION = 4

    def __init__(self, *, api_key: str | None = None, client: httpx.Client | None = None) -> None:
        self._api_key = api_key if api_key is not None else settings.bible_brain_api_key
        self._client = client
        self._owns_client = client is None
        self._fileset_cache: dict[str, dict[str, Any]] = {}

    def _params(self, extra: dict[str, Any] | None = None) -> dict[str, Any]:
        params: dict[str, Any] = {"v": self.API_VERSION}
        if self._api_key:
            params["key"] = self._api_key
        if extra:
            params.update(extra)
        return params

    def _get_client(self) -> httpx.Client:
        if self._client is None:
            self._client = httpx.Client(base_url=settings.bible_brain_base_url, timeout=30.0)
        return self._client

    def close(self) -> None:
        if self._owns_client and self._client is not None:
            self._client.close()

    def __enter__(self) -> BibleBrainClient:
        return self

    def __exit__(self, *args: object) -> None:
        self.close()

    def warm_cache(self) -> None:
        for version in DEFAULT_VERSIONS:
            self.resolve_filesets(version["version_id"])

    def get_versions(self) -> list[dict[str, str]]:
        return list(DEFAULT_VERSIONS)

    def resolve_filesets(self, version_id: str) -> dict[str, Any]:
        normalized = version_id.lower()
        if normalized in self._fileset_cache:
            return self._fileset_cache[normalized]

        defaults = DEFAULT_FILESETS.get(normalized, DEFAULT_FILESETS["esv"])
        bible_id = VERSION_TO_BIBLE.get(normalized, VERSION_TO_BIBLE["esv"])
        if not self._api_key:
            default_audio = str(defaults.get("audio") or "").strip()
            resolved = {
                **defaults,
                "text_ids": [defaults["text"]],
                "audio_candidates": (
                    [{"id": default_audio, "type": "audio", "segmentation": "chapter"}]
                    if default_audio
                    else []
                ),
            }
            self._fileset_cache[normalized] = resolved
            return resolved

        response = self._get_client().get(
            f"/bibles/{bible_id}",
            params=self._params({"verify_segmentation": "true"}),
        )
        response.raise_for_status()
        payload = response.json()
        bible = _coerce_bible_record(payload.get("data"))
        filesets_raw = bible.get("filesets", {}) if bible else {}
        all_filesets = _flatten_filesets(filesets_raw)

        text_ids: list[str] = []
        audio_candidates: list[dict[str, Any]] = []

        for fileset in all_filesets:
            fileset_id = str(fileset.get("id") or "")
            fileset_type = str(fileset.get("type") or "")
            segmentation = fileset.get("segmentation_type")

            # Prefer plain text (not usx/json). Skip opus-suffixed audio ids.
            if fileset_type == "text_plain" and fileset_id:
                text_ids.append(fileset_id)
            if fileset_type.startswith("audio") and fileset_id and "-opus" not in fileset_id.lower():
                audio_candidates.append(
                    {
                        "id": fileset_id,
                        "type": fileset_type,
                        "segmentation": segmentation,
                    }
                )

        ranked_default = _rank_audio_candidates(audio_candidates, prefer_nt=True)
        default_audio = str(defaults.get("audio") or "").strip()
        resolved = {
            "text": text_ids[0] if text_ids else defaults["text"],
            "text_ids": text_ids or [defaults["text"]],
            "audio": ranked_default[0] if ranked_default else default_audio,
            "audio_candidates": audio_candidates
            or (
                [{"id": default_audio, "type": "audio", "segmentation": "chapter"}]
                if default_audio
                else []
            ),
        }
        self._fileset_cache[normalized] = resolved
        return resolved

    def get_verse_text(
        self,
        *,
        book: str,
        chapter: int,
        start_verse: int,
        end_verse: int,
        version_id: str,
    ) -> str:
        if not self._api_key:
            local = self._local_verse_text(
                book=book,
                chapter=chapter,
                start_verse=start_verse,
                end_verse=end_verse,
            )
            if local is not None:
                return local
            return f"[{book} {chapter}:{start_verse} placeholder — set BIBLE_BRAIN_API_KEY]"

        filesets = self.resolve_filesets(version_id)
        book_id = dbp_book_id(book)
        text_fileset = _text_fileset_for_book(filesets, book)
        response = self._get_client().get(
            f"/bibles/filesets/{text_fileset}/{book_id}/{chapter}",
            params=self._params({"verse_start": start_verse, "verse_end": end_verse}),
        )
        response.raise_for_status()
        return _extract_verse_text(response.json())

    def get_chapter_audio_url(self, *, book: str, chapter: int, version_id: str) -> str:
        book_id = dbp_book_id(book)
        helloao = f"https://audio.bible.helloao.org/api/BSB/{book_id}/{chapter}/audio/david.mp3"
        if not self._api_key:
            local = self._local_audio_url(book_id=book_id, chapter=chapter)
            if local is not None:
                return local
            # Free helloao chapter audio — no Bible Brain key required.
            return helloao

        filesets = self.resolve_filesets(version_id)
        candidates = filesets.get("audio_candidates")
        if not isinstance(candidates, list):
            candidates = []
        ranked = _rank_audio_candidates(
            [item for item in candidates if isinstance(item, dict)],
            prefer_nt=_is_new_testament_book(book),
        )
        fallback = str(filesets.get("audio") or "").strip()
        if not ranked and fallback:
            ranked = [fallback]
        if not ranked:
            return helloao

        for audio_fileset in ranked:
            try:
                response = self._get_client().get(
                    f"/bibles/filesets/{audio_fileset}/{book_id}/{chapter}",
                    params=self._params(),
                )
                response.raise_for_status()
                url = _extract_audio_url(response.json())
            except (httpx.HTTPError, ValueError, KeyError):
                continue
            if _is_direct_audio_url(url):
                return url
        return helloao

    def _chapter_cache_root(self) -> Path | None:
        configured = settings.chapter_cache_root.strip()
        if configured:
            return Path(configured)
        # Dev default: repo pipeline/data/chapters next to scroller/
        file_path = Path(__file__).resolve()
        if len(file_path.parents) > 4:
            candidate = file_path.parents[4] / "pipeline" / "data" / "chapters"
            if candidate.is_dir():
                return candidate
        return None

    def _local_verse_text(
        self,
        *,
        book: str,
        chapter: int,
        start_verse: int,
        end_verse: int,
    ) -> str | None:
        root = self._chapter_cache_root()
        if root is None:
            return None
        payload = load_chapter_payload(root, book_id=dbp_book_id(book), chapter=chapter)
        if payload is None:
            return None
        try:
            return extract_verse_range_text(
                payload,
                start_verse=start_verse,
                end_verse=end_verse,
            )
        except ValueError:
            return None

    def _local_audio_url(self, *, book_id: str, chapter: int) -> str | None:
        root = self._chapter_cache_root()
        if root is None:
            return None
        payload = load_chapter_payload(root, book_id=book_id, chapter=chapter)
        if payload is None:
            return None
        return extract_chapter_audio_url(payload)


def _coerce_bible_record(data: Any) -> dict[str, Any] | None:
    """DBP v4 /bibles/{id} returns data as an object; older mocks used a one-item list."""
    if isinstance(data, dict):
        return data
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict):
                return item
    return None


def _is_new_testament_book(book: str) -> bool:
    iq = IQ_BOOK_IDS.get(book.strip())
    return iq is not None and int(iq) >= 40


def _text_fileset_for_book(filesets: dict[str, Any], book: str) -> str:
    """Pick NT (*N_ET) vs OT (*O_ET) plain-text filesets when both exist."""
    text_ids = filesets.get("text_ids")
    ids = [str(item) for item in text_ids] if isinstance(text_ids, list) else []
    if not ids:
        return str(filesets.get("text") or DEFAULT_FILESETS["esv"]["text"])

    want_nt = _is_new_testament_book(book)
    preferred_suffix = "N_ET" if want_nt else "O_ET"
    for fileset_id in ids:
        if fileset_id.upper().endswith(preferred_suffix):
            return fileset_id
    # Fall back to any plain-text fileset (some bibles ship one combined set).
    return ids[0]


def _audio_testament_and_kind(fileset_id: str) -> tuple[str | None, str | None]:
    match = _AUDIO_FILESET_MARK.search(fileset_id)
    if match is None:
        return None, None
    return match.group(1).upper(), match.group(3).upper()


def _rank_audio_candidates(
    candidates: list[dict[str, Any]],
    *,
    prefer_nt: bool,
) -> list[str]:
    """Prefer matching testament + downloadable mp3 (DA) over OT/stream (SA)."""
    want = "N" if prefer_nt else "O"

    def sort_key(item: dict[str, Any]) -> tuple[int, int, int, str]:
        fileset_id = str(item.get("id") or "")
        fileset_type = str(item.get("type") or "").lower()
        testament, kind = _audio_testament_and_kind(fileset_id)
        if testament == want:
            wrong_testament = 0
        elif testament is None:
            wrong_testament = 1
        else:
            wrong_testament = 2
        is_stream = 1 if ("stream" in fileset_type or kind == "SA") else 0
        chapter_seg = 0 if item.get("segmentation") == "chapter" else 1
        return (wrong_testament, is_stream, chapter_seg, fileset_id)

    seen: set[str] = set()
    ranked: list[str] = []
    for item in sorted(candidates, key=sort_key):
        fileset_id = str(item.get("id") or "").strip()
        if not fileset_id or fileset_id in seen:
            continue
        seen.add(fileset_id)
        ranked.append(fileset_id)
    return ranked


def _is_direct_audio_url(url: str) -> bool:
    trimmed = url.strip()
    if not trimmed.startswith("http"):
        return False
    lower = trimmed.lower()
    if ".m3u8" in lower:
        return False
    return True


def _flatten_filesets(raw: Any) -> list[dict[str, Any]]:
    if isinstance(raw, list):
        return [item for item in raw if isinstance(item, dict)]
    if isinstance(raw, dict):
        flattened: list[dict[str, Any]] = []
        for value in raw.values():
            flattened.extend(_flatten_filesets(value))
        return flattened
    return []


def _extract_verse_text(payload: Any) -> str:
    if isinstance(payload, dict):
        data = payload.get("data")
        if isinstance(data, list):
            verses = [str(item.get("verse_text", "")).strip() for item in data if item.get("verse_text")]
            return " ".join(verses)
    return str(payload)


def _extract_audio_url(payload: Any) -> str:
    if isinstance(payload, str) and payload.startswith("http"):
        return payload
    if isinstance(payload, dict):
        data = payload.get("data")
        if isinstance(data, list):
            for item in data:
                path = item.get("path")
                if isinstance(path, str) and path.startswith("http"):
                    return path
        for key in ("path", "url", "audio_url", "audioUrl"):
            value = payload.get(key)
            if isinstance(value, str) and value.startswith("http"):
                return value
    raise ValueError("Audio URL not found in Bible Brain response")
