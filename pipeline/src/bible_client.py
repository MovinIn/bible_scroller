from __future__ import annotations

import json
import os
import re
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx

from src.config import (
    BIBLE_API_BASE,
    BIBLE_TRANSLATION,
    CHAPTER_FETCH_DELAY_SECONDS,
    HTTP_MAX_RETRIES,
    HTTP_RETRY_BACKOFF_SECONDS,
    HTTP_RETRYABLE_STATUS_CODES,
)
from src.reference import VerseReference

_HTML_TAG_PATTERN = re.compile(r"<[^>]+>")


_VERSE_NUMBER_SPAN_PATTERN = re.compile(
    r'<span[^>]*class="v"[^>]*>.*?</span>',
    flags=re.IGNORECASE,
)

# Common reference shorthands → API book names
_BOOK_ALIASES: dict[str, str] = {
    "psalm": "Psalms",
}


def strip_html(text: str) -> str:
    without_verse_numbers = _VERSE_NUMBER_SPAN_PATTERN.sub("", text)
    return _HTML_TAG_PATTERN.sub("", without_verse_numbers).strip()


def _flatten_verse_content(content: list[Any]) -> str:
    parts: list[str] = [item for item in content if isinstance(item, str)]
    if not parts:
        return ""

    result = parts[0]
    for part in parts[1:]:
        if (
            result
            and part
            and not result[-1].isspace()
            and part[0] not in ".,;:!?'\"-) "
            and result[-1].isalnum()
            and part[0].isalnum()
        ):
            result += " "
        result += part
    return result.strip()


def extract_verse_text(chapter_payload: dict[str, Any], start_verse: int, end_verse: int) -> str:
    content = chapter_payload.get("chapter", {}).get("content", [])
    verses: dict[int, str] = {}

    for block in content:
        if block.get("type") != "verse":
            continue
        number = block.get("number")
        if number is None:
            continue
        verses[int(number)] = _flatten_verse_content(block.get("content", []))

    lines: list[str] = []
    for verse_number in range(start_verse, end_verse + 1):
        text = verses.get(verse_number)
        if text is None:
            continue
        lines.append(f"{verse_number} {text}")

    if not lines:
        raise ValueError(f"No verses found in range {start_verse}-{end_verse}")

    return "\n".join(lines)


def extract_chapter_text(chapter_payload: dict[str, Any]) -> str:
    # Verse numbers can be non-contiguous (BSB omits some verses), so join
    # whatever verses exist instead of assuming an unbroken min..max range.
    content = chapter_payload.get("chapter", {}).get("content", [])
    lines: list[str] = []
    for block in content:
        if block.get("type") != "verse":
            continue
        number = block.get("number")
        if number is None:
            continue
        lines.append(f"{int(number)} {_flatten_verse_content(block.get('content', []))}")
    return "\n".join(lines)


def list_verse_numbers(chapter_payload: dict[str, Any]) -> list[int]:
    content = chapter_payload.get("chapter", {}).get("content", [])
    numbers: list[int] = []
    for block in content:
        if block.get("type") != "verse":
            continue
        number = block.get("number")
        if number is not None:
            numbers.append(int(number))
    return numbers


def chapter_cache_path(cache_dir: Path, book_id: str, chapter: int) -> Path:
    return cache_dir / book_id / f"{chapter}.json"


@dataclass(frozen=True)
class BookInfo:
    name: str
    common_name: str
    id: str
    number_of_chapters: int
    order: int


class BibleClient:
    def __init__(self, client: httpx.Client | None = None) -> None:
        self._client = client or httpx.Client(timeout=30.0)
        self._owns_client = client is None
        self._book_id_cache: dict[str, str] | None = None
        self._books_payload: list[dict[str, Any]] | None = None
        self._translation_meta: dict[str, Any] | None = None

    def close(self) -> None:
        if self._owns_client:
            self._client.close()

    def _get_with_retry(self, url: str) -> httpx.Response:
        response: httpx.Response | None = None
        for attempt in range(HTTP_MAX_RETRIES):
            response = self._client.get(url)
            if response.status_code not in HTTP_RETRYABLE_STATUS_CODES:
                response.raise_for_status()
                return response
            if attempt < HTTP_MAX_RETRIES - 1:
                time.sleep(HTTP_RETRY_BACKOFF_SECONDS * (2**attempt))
        assert response is not None
        response.raise_for_status()
        return response

    def _load_books_payload(self) -> list[dict[str, Any]]:
        if self._books_payload is not None:
            return self._books_payload

        url = f"{BIBLE_API_BASE}/{BIBLE_TRANSLATION}/books.json"
        response = self._get_with_retry(url)
        payload = response.json()
        self._translation_meta = {
            key: value
            for key, value in payload.items()
            if key != "books"
        }
        self._books_payload = payload.get("books", [])
        return self._books_payload

    def translation_meta(self) -> dict[str, Any]:
        self._load_books_payload()
        return dict(self._translation_meta or {})

    def _load_book_ids(self) -> dict[str, str]:
        if self._book_id_cache is not None:
            return self._book_id_cache

        mapping: dict[str, str] = {}
        for book in self._load_books_payload():
            name = book.get("name", "")
            common_name = book.get("commonName", "")
            book_id = book.get("id", "")
            if name:
                mapping[name.casefold()] = book_id
            if common_name and common_name.casefold() != name.casefold():
                mapping[common_name.casefold()] = book_id

        self._book_id_cache = mapping
        return mapping

    def list_books(self) -> list[BookInfo]:
        books: list[BookInfo] = []
        for book in self._load_books_payload():
            name = book.get("name") or book.get("commonName", "")
            common_name = book.get("commonName") or name
            books.append(
                BookInfo(
                    name=name,
                    common_name=common_name,
                    id=book.get("id", ""),
                    number_of_chapters=int(book.get("numberOfChapters", 0)),
                    order=int(book.get("order", 0)),
                )
            )
        books.sort(key=lambda item: item.order)
        return books

    def resolve_book_id(self, book_name: str) -> str:
        mapping = self._load_book_ids()
        folded = book_name.casefold()
        canonical = _BOOK_ALIASES.get(folded, book_name)
        book_id = mapping.get(canonical.casefold())
        if book_id is None:
            raise ValueError(f"Unknown book: {book_name!r}")
        return book_id

    def fetch_chapter(self, book_id: str, chapter: int) -> dict[str, Any]:
        url = f"{BIBLE_API_BASE}/{BIBLE_TRANSLATION}/{book_id}/{chapter}.json"
        response = self._get_with_retry(url)
        return response.json()

    def fetch_chapter_cached(
        self,
        book_id: str,
        chapter: int,
        *,
        cache_dir: Path | None = None,
        use_cache: bool = True,
    ) -> dict[str, Any]:
        if cache_dir is not None and use_cache:
            path = chapter_cache_path(cache_dir, book_id, chapter)
            if path.exists():
                try:
                    return json.loads(path.read_text(encoding="utf-8"))
                except (json.JSONDecodeError, OSError):
                    pass

        payload = self.fetch_chapter(book_id, chapter)
        if CHAPTER_FETCH_DELAY_SECONDS > 0:
            time.sleep(CHAPTER_FETCH_DELAY_SECONDS)

        if cache_dir is not None and use_cache:
            path = chapter_cache_path(cache_dir, book_id, chapter)
            path.parent.mkdir(parents=True, exist_ok=True)
            payload_text = json.dumps(payload)
            temp_path: Path | None = None
            try:
                with tempfile.NamedTemporaryFile(
                    mode="w",
                    encoding="utf-8",
                    dir=path.parent,
                    delete=False,
                ) as temp_file:
                    temp_file.write(payload_text)
                    temp_path = Path(temp_file.name)
                os.replace(temp_path, path)
            except OSError:
                if temp_path is not None:
                    try:
                        temp_path.unlink(missing_ok=True)
                    except OSError:
                        pass

        return payload

    def fetch_verse_text(
        self,
        reference: VerseReference,
        *,
        cache_dir: Path | None = None,
        use_cache: bool = True,
    ) -> str:
        book_id = self.resolve_book_id(reference.book)
        if cache_dir is not None and use_cache:
            chapter_payload = self.fetch_chapter_cached(
                book_id,
                reference.chapter,
                cache_dir=cache_dir,
                use_cache=True,
            )
        else:
            chapter_payload = self.fetch_chapter(book_id, reference.chapter)
        return extract_verse_text(
            chapter_payload,
            start_verse=reference.start_verse,
            end_verse=reference.end_verse,
        )
