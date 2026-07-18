#!/usr/bin/env python3
"""Generate images for all Bible books into output/prod/<book>, skipping Genesis."""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

PIPELINE_ROOT = Path(__file__).resolve().parent
PROD_DIR = PIPELINE_ROOT / "output" / "prod"
STATE_PATH = PROD_DIR / "batch_state.json"
MANIFEST_PATH = PIPELINE_ROOT / "output" / "groups" / "manifest.json"
STOP_POINT_PATH = PIPELINE_ROOT / "output" / "groups" / "stop_point.json"
PYTHON = PIPELINE_ROOT / ".venv" / "Scripts" / "python.exe"
if not PYTHON.exists():
    PYTHON = Path(sys.executable)


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _load_books() -> list[str]:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    books: list[str] = []
    seen: set[str] = set()
    for group in manifest["groups"]:
        book = group["book"]
        if book not in seen:
            seen.add(book)
            books.append(book)
    return books


def _book_counts() -> dict[str, int]:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    counts: dict[str, int] = {}
    for group in manifest["groups"]:
        book = group["book"]
        counts[book] = counts.get(book, 0) + 1
    return counts


def _load_state() -> dict:
    if STATE_PATH.exists():
        return json.loads(STATE_PATH.read_text(encoding="utf-8"))
    return {}


def _save_state(state: dict) -> None:
    PROD_DIR.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, indent=2), encoding="utf-8")


def _is_retryable(exit_code: int, stop_point: dict | None) -> bool:
    if exit_code == 0:
        return False
    if stop_point is None:
        return False
    error = str(stop_point.get("error", "")).lower()
    markers = (
        "429",
        "503",
        "resource_exhausted",
        "unavailable",
        "temporary",
        "interrupted by user",
        "rate limit",
    )
    return any(marker in error for marker in markers)


def _read_stop_point() -> dict | None:
    if not STOP_POINT_PATH.exists():
        return None
    try:
        return json.loads(STOP_POINT_PATH.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None


def _run_book(book: str) -> int:
    output_dir = PROD_DIR / book
    output_dir.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(PYTHON),
        str(PIPELINE_ROOT / "generate_batch.py"),
        "--book",
        book,
        "--output-dir",
        str(Path("output") / "prod" / book),
        "--workers",
        "3",
    ]
    print(f"\n=== Running: {' '.join(cmd)} ===", flush=True)
    return subprocess.run(cmd, cwd=PIPELINE_ROOT).returncode


def main() -> int:
    books = [book for book in _load_books() if book != "Genesis"]
    counts = _book_counts()
    state = _load_state()
    state.setdefault("started_at", _now())
    state["status"] = "running"
    state["total_books"] = 66
    state["books_to_generate"] = len(books)
    state["total_groups_expected"] = sum(counts.values())
    state["skip_books"] = ["Genesis"]
    state.setdefault("completed_books", [])
    state.setdefault("retries", 0)

    for book in books:
        if book in state["completed_books"]:
            print(f"Skipping {book} (already completed)", flush=True)
            continue

        state["current_book"] = book
        state["current_book_expected"] = counts[book]
        state["updated_at"] = _now()
        _save_state(state)

        while True:
            exit_code = _run_book(book)
            stop_point = _read_stop_point()
            if exit_code == 0:
                break
            if _is_retryable(exit_code, stop_point):
                state["retries"] = int(state.get("retries", 0)) + 1
                state["last_retry_at"] = _now()
                state["last_retry_book"] = book
                state["last_retry_error"] = stop_point.get("error") if stop_point else ""
                _save_state(state)
                print(f"Retrying {book} after transient stop...", flush=True)
                continue
            state["status"] = "failed"
            state["failed_book"] = book
            state["failed_at"] = _now()
            state["last_exit_code"] = exit_code
            state["last_stop_point"] = stop_point
            _save_state(state)
            return exit_code

        state["completed_books"].append(book)
        state["updated_at"] = _now()
        _save_state(state)
        print(f"Completed {book}", flush=True)

    state["status"] = "completed"
    state["finished_at"] = _now()
    state["current_book"] = None
    _save_state(state)
    print("\nAll books generated.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
