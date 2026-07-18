from __future__ import annotations

from pathlib import Path
from typing import Any

import httpx

from src.book_ids import dbp_book_id
from src.config import settings
from src.services.local_bible_text import (
    extract_chapter_audio_url,
    extract_verse_range_text,
    load_chapter_payload,
)

DEFAULT_VERSIONS: list[dict[str, str]] = [
    {"version_id": "niv", "name": "New International Version"},
]

VERSION_TO_BIBLE: dict[str, str] = {
    "niv": "ENGNIV",
}

NIV_TEXT_FILESET = "ENGNIV"
NIV_AUDIO_FILESET = "ENGNIVN2DA"


class BibleBrainClient:
    API_VERSION = 4

    def __init__(self, *, api_key: str | None = None, client: httpx.Client | None = None) -> None:
        self._api_key = api_key if api_key is not None else settings.bible_brain_api_key
        self._client = client
        self._owns_client = client is None
        self._fileset_cache: dict[str, dict[str, str]] = {}

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
        for version_id in VERSION_TO_BIBLE:
            self.resolve_filesets(version_id)

    def get_versions(self) -> list[dict[str, str]]:
        return list(DEFAULT_VERSIONS)

    def resolve_filesets(self, version_id: str) -> dict[str, str]:
        normalized = version_id.lower()
        if normalized in self._fileset_cache:
            return self._fileset_cache[normalized]

        bible_id = VERSION_TO_BIBLE.get(normalized, NIV_TEXT_FILESET)
        if not self._api_key:
            filesets = {"text": NIV_TEXT_FILESET, "audio": NIV_AUDIO_FILESET}
            self._fileset_cache[normalized] = filesets
            return filesets

        response = self._get_client().get(
            f"/bibles/{bible_id}",
            params=self._params({"verify_segmentation": "true"}),
        )
        response.raise_for_status()
        payload = response.json()
        bible_items = payload.get("data", [])
        filesets_raw = bible_items[0].get("filesets", {}) if bible_items else {}
        all_filesets = _flatten_filesets(filesets_raw)

        text_id: str | None = None
        audio_id: str | None = None
        chapter_audio_id: str | None = None

        for fileset in all_filesets:
            fileset_id = str(fileset.get("id") or "")
            fileset_type = str(fileset.get("type") or "")
            segmentation = fileset.get("segmentation_type")

            if fileset_type == "text_plain" or fileset_id == bible_id:
                text_id = text_id or fileset_id
            if fileset_type.startswith("audio"):
                if segmentation == "chapter":
                    chapter_audio_id = fileset_id
                elif audio_id is None:
                    audio_id = fileset_id

        resolved = {
            "text": text_id or NIV_TEXT_FILESET,
            "audio": chapter_audio_id or audio_id or NIV_AUDIO_FILESET,
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
        response = self._get_client().get(
            f"/bibles/filesets/{filesets['text']}/{book_id}/{chapter}",
            params=self._params({"verse_start": start_verse, "verse_end": end_verse}),
        )
        response.raise_for_status()
        return _extract_verse_text(response.json())

    def get_chapter_audio_url(self, *, book: str, chapter: int, version_id: str) -> str:
        book_id = dbp_book_id(book)
        if not self._api_key:
            local = self._local_audio_url(book_id=book_id, chapter=chapter)
            if local is not None:
                return local
            # Free helloao chapter audio — no Bible Brain key required.
            return f"https://audio.bible.helloao.org/api/BSB/{book_id}/{chapter}/audio/david.mp3"

        filesets = self.resolve_filesets(version_id)
        response = self._get_client().get(
            f"/bibles/filesets/{filesets['audio']}/{book_id}/{chapter}",
            params=self._params(),
        )
        response.raise_for_status()
        return _extract_audio_url(response.json())

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
