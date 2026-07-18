import json
from pathlib import Path
from unittest.mock import MagicMock

import generate_one
from src.generate import GenerationResult
from src.reference import VerseReference


class FakeServerError(Exception):
    def __init__(self, code: int):
        super().__init__(f"{code} UNAVAILABLE")
        self.code = code


def test_main_returns_1_and_writes_stop_point_when_generation_fails_transiently(
    tmp_path, monkeypatch, capsys
):
    stop_path = tmp_path / "stop_point.json"
    monkeypatch.setattr("generate_one.DEFAULT_STOP_POINT", stop_path)
    monkeypatch.setattr("generate_one.BibleClient", MagicMock)

    def raise_transient(reference, **kwargs):
        raise FakeServerError(503)

    monkeypatch.setattr("generate_one.generate_for_reference", raise_transient)

    exit_code = generate_one.main(["John", "3:16-20"])

    assert exit_code == 1
    payload = json.loads(stop_path.read_text(encoding="utf-8"))
    assert payload["reference"] == "John 3:16-20"
    assert "503" in payload["error"]
    out = capsys.readouterr().out
    assert "John 3:16-20" in out
    assert str(stop_path) in out


def test_main_deletes_stop_point_when_generation_succeeds(tmp_path, monkeypatch):
    stop_path = tmp_path / "stop_point.json"
    stop_path.write_text(
        json.dumps({"reference": "John 3:16-20", "error": "503 UNAVAILABLE"}),
        encoding="utf-8",
    )
    monkeypatch.setattr("generate_one.DEFAULT_STOP_POINT", stop_path)
    monkeypatch.setattr("generate_one.BibleClient", MagicMock)

    def succeed(reference, **kwargs):
        return GenerationResult(
            reference=reference,
            verse_text="16 text",
            flux_prompt="prompt",
            output_path=tmp_path / "saved.png",
            bible_ms=1.0,
            gemini_ms=2.0,
            flux_ms=3.0,
        )

    monkeypatch.setattr("generate_one.generate_for_reference", succeed)

    exit_code = generate_one.main(["John", "3:16-20"])

    assert exit_code == 0
    assert not stop_path.exists()
