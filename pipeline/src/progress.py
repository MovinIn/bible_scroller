"""Persist where a generation run stopped so it can be resumed later."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path


def read_stop_point(path: Path) -> dict | None:
    """Return parsed stop-point JSON, or None if the file is missing or invalid."""
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None


def clear_stop_point(path: Path) -> None:
    """Delete the stop-point file if it exists."""
    try:
        path.unlink(missing_ok=True)
    except OSError:
        pass


def write_stop_point(
    path: Path,
    *,
    reference: str,
    error: str,
    group_id: int | None = None,
    resume_hint: str | None = None,
) -> None:
    payload: dict = {
        "stopped_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "reference": reference,
        "error": error,
    }
    if group_id is not None:
        payload["group_id"] = group_id
    if resume_hint is not None:
        payload["resume_hint"] = resume_hint
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
