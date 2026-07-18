from __future__ import annotations

from src.services.bible_brain_client import BibleBrainClient

_client: BibleBrainClient | None = None


def get_bible_client() -> BibleBrainClient:
    global _client
    if _client is None:
        _client = BibleBrainClient()
    return _client


def close_bible_client() -> None:
    global _client
    if _client is not None:
        _client.close()
        _client = None


def warm_bible_client_cache() -> None:
    try:
        get_bible_client().warm_cache()
    except Exception:
        pass


def reset_bible_client_for_tests() -> None:
    close_bible_client()
