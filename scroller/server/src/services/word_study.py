from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from src.book_ids import dbp_book_id
from src.config import settings

_SERVER_ROOT = Path(__file__).resolve().parents[2]
_DEFAULT_WORD_STUDY_ROOT = _SERVER_ROOT / "data" / "word_study"


def load_strongs_lexicon(path: Path) -> dict[str, dict[str, str]]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    return {
        str(key): {
            "lemma": str(entry.get("lemma") or ""),
            "definition": str(entry.get("definition") or ""),
        }
        for key, entry in raw.items()
    }


class WordStudyService:
    def __init__(self, root: Path | None = None) -> None:
        self.root = Path(root) if root is not None else _default_root()
        self._lexicon: dict[str, dict[str, str]] | None = None
        self._chapter_cache: dict[tuple[str, int], dict[str, Any]] = {}

    def get_word_study(
        self,
        *,
        book: str,
        chapter: int,
        start_verse: int,
        end_verse: int,
    ) -> dict[str, Any]:
        if end_verse < start_verse:
            raise ValueError("end_verse must be >= start_verse")

        chapter_data = self._load_chapter(book, chapter)
        eng = chapter_data.get("eng") or {}
        original = chapter_data.get("heb") or chapter_data.get("grk") or {}
        original_by_strongs = _index_original_by_strongs(original)

        verses_out: list[dict[str, Any]] = []
        for verse in range(start_verse, end_verse + 1):
            tokens = eng.get(str(verse)) or eng.get(verse) or []
            groups = []
            for token in tokens:
                group = self._token_to_group(token, original_by_strongs.get(str(verse), {}))
                if group is not None:
                    groups.append(group)
            verses_out.append({"verse": verse, "groups": groups})

        reference = (
            f"{book} {chapter}:{start_verse}"
            if start_verse == end_verse
            else f"{book} {chapter}:{start_verse}-{end_verse}"
        )
        return {
            "reference": reference,
            "version_id": "bsb",
            "verses": verses_out,
        }

    def _token_to_group(
        self,
        token: list[Any],
        original_for_verse: dict[str, str],
    ) -> dict[str, str] | None:
        if not token:
            return None
        phrase = str(token[0] or "")
        strongs = token[1] if len(token) > 1 else None
        if strongs is None:
            return None
        strongs_id = str(strongs)
        meta = token[2] if len(token) > 2 and isinstance(token[2], dict) else {}
        if meta.get("elided") and not phrase.strip():
            return None
        if not phrase.strip():
            return None

        lexicon_entry = self._get_lexicon().get(strongs_id, {})
        lemma = original_for_verse.get(strongs_id) or lexicon_entry.get("lemma") or ""
        definition = lexicon_entry.get("definition") or ""
        return {
            "phrase": phrase,
            "strongs": strongs_id,
            "lemma": lemma,
            "definition": definition,
        }

    def _load_chapter(self, book: str, chapter: int) -> dict[str, Any]:
        key = (book, chapter)
        if key in self._chapter_cache:
            return self._chapter_cache[key]

        book_code = dbp_book_id(book)
        path = self.root / "display" / book_code / f"{book_code}{chapter}.json"
        if not path.is_file():
            raise FileNotFoundError(f"Word study data missing for {book} {chapter}: {path}")
        data = json.loads(path.read_text(encoding="utf-8"))
        self._chapter_cache[key] = data
        return data

    def _get_lexicon(self) -> dict[str, dict[str, str]]:
        if self._lexicon is None:
            path = self.root / "lexicon" / "strongs.json"
            if not path.is_file():
                self._lexicon = {}
            else:
                self._lexicon = load_strongs_lexicon(path)
        return self._lexicon


def _index_original_by_strongs(original: dict[str, Any]) -> dict[str, dict[str, str]]:
    indexed: dict[str, dict[str, str]] = {}
    for verse_key, tokens in original.items():
        by_strongs: dict[str, str] = {}
        for token in tokens or []:
            if not token or len(token) < 2 or token[1] is None:
                continue
            lemma = str(token[0] or "").strip()
            strongs_id = str(token[1])
            if lemma and strongs_id not in by_strongs:
                by_strongs[strongs_id] = lemma
        indexed[str(verse_key)] = by_strongs
    return indexed


def _default_root() -> Path:
    configured = (settings.word_study_root or "").strip()
    if configured:
        return Path(configured)
    return _DEFAULT_WORD_STUDY_ROOT


@lru_cache(maxsize=1)
def get_word_study_service() -> WordStudyService:
    return WordStudyService()
