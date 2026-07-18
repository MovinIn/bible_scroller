import json
from pathlib import Path
from unittest.mock import MagicMock

import pytest

import generate_batch
from generate_batch import (
    BatchFailure,
    BatchResult,
    EntryOutcome,
    _aggregate_outcomes,
    run_batch,
    select_entries,
    write_failures,
)
from src.generate import GenerationResult
from src.reference import VerseReference


def test_select_entries_respects_limit_after_skipping_existing(tmp_path):
    output_dir = tmp_path / "output"
    output_dir.mkdir()
    (output_dir / "John_3_16-16_existing.png").write_bytes(b"png")

    entries = [
        {"id": 1, "reference": "John 3:16", "book": "John", "slug": "John_3_16-16"},
        {"id": 2, "reference": "John 3:17", "book": "John", "slug": "John_3_17-17"},
        {"id": 3, "reference": "John 3:18", "book": "John", "slug": "John_3_18-18"},
    ]

    selected = select_entries(
        entries,
        book_filter=None,
        from_id=None,
        to_id=None,
        limit=1,
        output_dir=output_dir,
        force=False,
    )

    assert [entry["id"] for entry in selected] == [2]


def test_run_batch_uses_per_entry_theme_when_themes_file_exists(tmp_path, monkeypatch):
    registry_path = _write_registry(tmp_path)
    themes_path = tmp_path / "themes.json"
    themes_path.write_text(
        json.dumps(
            {
                "John": {
                    "3": {
                        "theme_id": "wisdom_lyrical",
                        "style": "clipart",
                        "rationale": "test",
                    }
                }
            }
        ),
        encoding="utf-8",
    )
    entries = [
        {
            "id": 1,
            "reference": "John 3:16",
            "book": "John",
            "chapter": 3,
            "start_verse": 16,
            "end_verse": 16,
        },
    ]
    bible = MagicMock()
    captured: dict = {}

    def generate_side_effect(reference, **kwargs):
        captured["meta_prompt_path"] = kwargs["meta_prompt_path"]
        captured["theme_guidance"] = kwargs["theme_guidance"]
        return GenerationResult(
            reference=reference,
            verse_text="16 text",
            flux_prompt="prompt",
            output_path=tmp_path / "saved.png",
            bible_ms=1.0,
            gemini_ms=2.0,
            flux_ms=3.0,
        )

    monkeypatch.setattr("generate_batch.generate_for_reference", generate_side_effect)
    monkeypatch.setattr(generate_batch, "THEME_REGISTRY", registry_path)
    monkeypatch.setattr(generate_batch, "THEME_OVERRIDES", tmp_path / "missing.json")
    monkeypatch.setattr(generate_batch, "PROMPTS_DIR", tmp_path)

    run_batch(entries, bible=bible, themes_path=themes_path, output_dir=tmp_path)

    assert captured["meta_prompt_path"].name == "meta_prompt_clipart.txt"
    assert captured["theme_guidance"] == "Wisdom mood guidance."


def _write_registry(tmp_path: Path) -> Path:
    registry_path = tmp_path / "theme_registry.json"
    registry_path.write_text(
        json.dumps(
            {
                "themes": {
                    "gospel_light": {
                        "description": "warm gospel",
                        "default_style": "realistic",
                        "mood_file": "themes/gospel_light.txt",
                    },
                    "wisdom_lyrical": {
                        "description": "reflective psalms",
                        "default_style": "clipart",
                        "mood_file": "themes/wisdom_lyrical.txt",
                    },
                },
                "styles": {
                    "realistic": "meta_prompt_realistic.txt",
                    "clipart": "meta_prompt_clipart.txt",
                },
                "default_theme_id": "gospel_light",
            }
        ),
        encoding="utf-8",
    )
    (tmp_path / "themes").mkdir()
    (tmp_path / "themes" / "gospel_light.txt").write_text("Gospel mood guidance.", encoding="utf-8")
    (tmp_path / "themes" / "wisdom_lyrical.txt").write_text(
        "Wisdom mood guidance.", encoding="utf-8"
    )
    (tmp_path / "meta_prompt_realistic.txt").write_text("Realistic shell", encoding="utf-8")
    (tmp_path / "meta_prompt_clipart.txt").write_text("Clipart shell", encoding="utf-8")
    return registry_path


def test_run_batch_records_failure_when_theme_resolution_raises(tmp_path, monkeypatch):
    registry_path = _write_registry(tmp_path)
    themes_path = tmp_path / "themes.json"
    themes_path.write_text(
        json.dumps(
            {
                "John": {
                    "3": {"theme_id": "no_such_theme", "style": "realistic"},
                }
            }
        ),
        encoding="utf-8",
    )
    entries = [
        {
            "id": 1,
            "reference": "John 3:16",
            "book": "John",
            "chapter": 3,
            "start_verse": 16,
            "end_verse": 16,
        },
    ]
    bible = MagicMock()

    monkeypatch.setattr(generate_batch, "THEME_REGISTRY", registry_path)
    monkeypatch.setattr(generate_batch, "THEME_OVERRIDES", tmp_path / "missing.json")
    monkeypatch.setattr(generate_batch, "PROMPTS_DIR", tmp_path)

    result = run_batch(entries, bible=bible, themes_path=themes_path, output_dir=tmp_path)

    assert result.generated == 0
    assert len(result.failures) == 1
    assert "no_such_theme" in result.failures[0].error
    assert result.stopped is None


def test_run_batch_continues_after_failure_and_records_error(tmp_path, monkeypatch):
    entries = [
        {"id": 1, "reference": "John 3:16", "book": "John", "chapter": 3, "start_verse": 16, "end_verse": 16},
        {"id": 2, "reference": "John 3:17", "book": "John", "chapter": 3, "start_verse": 17, "end_verse": 17},
    ]
    bible = MagicMock()

    def generate_side_effect(reference, **kwargs):
        if reference.start_verse == 16:
            raise RuntimeError("gemini failed")
        return GenerationResult(
            reference=reference,
            verse_text="17 text",
            flux_prompt="prompt",
            output_path=tmp_path / "saved.png",
            bible_ms=1.0,
            gemini_ms=2.0,
            flux_ms=3.0,
        )

    monkeypatch.setattr("generate_batch.generate_for_reference", generate_side_effect)
    result = run_batch(entries, bible=bible, output_dir=tmp_path)

    assert result.generated == 1
    assert len(result.failures) == 1
    assert result.failures[0].group_id == 1
    assert result.failures[0].error == "gemini failed"


class FakeServerError(Exception):
    def __init__(self, code: int):
        super().__init__(f"{code} UNAVAILABLE")
        self.code = code


def _batch_entries(count: int) -> list[dict]:
    return [
        {
            "id": index,
            "reference": f"John 3:{15 + index}",
            "book": "John",
            "chapter": 3,
            "start_verse": 15 + index,
            "end_verse": 15 + index,
        }
        for index in range(1, count + 1)
    ]


def _success_result(reference: VerseReference, output_dir: Path) -> GenerationResult:
    return GenerationResult(
        reference=reference,
        verse_text=f"{reference.start_verse} text",
        flux_prompt="prompt",
        output_path=output_dir / "saved.png",
        bible_ms=1.0,
        gemini_ms=2.0,
        flux_ms=3.0,
    )


def test_run_batch_stops_without_trying_later_entries_when_error_is_transient(
    tmp_path, monkeypatch
):
    entries = [
        {"id": 1, "reference": "John 3:16", "book": "John", "chapter": 3, "start_verse": 16, "end_verse": 16},
        {"id": 2, "reference": "John 3:17", "book": "John", "chapter": 3, "start_verse": 17, "end_verse": 17},
    ]
    bible = MagicMock()
    calls = {"count": 0}

    def generate_side_effect(reference, **kwargs):
        calls["count"] += 1
        raise FakeServerError(503)

    monkeypatch.setattr("generate_batch.generate_for_reference", generate_side_effect)
    result = run_batch(entries, bible=bible, output_dir=tmp_path)

    assert calls["count"] == 1
    assert result.generated == 0
    assert result.stopped is not None
    assert result.stopped.group_id == 1
    assert result.stopped.reference == "John 3:16"
    assert "503" in result.stopped.error


def test_run_batch_processes_all_entries_when_workers_gt_1(tmp_path, monkeypatch):
    entries = _batch_entries(4)
    bible = MagicMock()
    processed_ids: list[int] = []

    def generate_side_effect(reference, **kwargs):
        processed_ids.append(reference.start_verse - 15)
        return _success_result(reference, tmp_path)

    monkeypatch.setattr("generate_batch.generate_for_reference", generate_side_effect)
    result = run_batch(entries, bible=bible, output_dir=tmp_path, workers=4)

    assert result.generated == 4
    assert sorted(processed_ids) == [1, 2, 3, 4]
    assert result.failures == []
    assert result.stopped is None


def test_run_batch_isolates_per_entry_failures_when_workers_gt_1(tmp_path, monkeypatch):
    entries = _batch_entries(3)
    bible = MagicMock()

    def generate_side_effect(reference, **kwargs):
        if reference.start_verse == 17:
            raise RuntimeError("gemini failed")
        return _success_result(reference, tmp_path)

    monkeypatch.setattr("generate_batch.generate_for_reference", generate_side_effect)
    result = run_batch(entries, bible=bible, output_dir=tmp_path, workers=3)

    assert result.generated == 2
    assert len(result.failures) == 1
    assert result.failures[0].group_id == 2
    assert result.failures[0].error == "gemini failed"
    assert result.stopped is None


def test_run_batch_sets_stop_to_transient_failure_not_permanent_failure_when_workers_gt_1(
    tmp_path, monkeypatch
):
    entries = _batch_entries(3)
    bible = MagicMock()

    def generate_side_effect(reference, **kwargs):
        if reference.start_verse == 16:
            raise RuntimeError("gemini failed")
        if reference.start_verse == 17:
            raise FakeServerError(503)
        return _success_result(reference, tmp_path)

    monkeypatch.setattr("generate_batch.generate_for_reference", generate_side_effect)
    result = run_batch(entries, bible=bible, output_dir=tmp_path, workers=3)

    assert result.stopped is not None
    assert result.stopped.group_id == 2
    assert result.stopped.reference == "John 3:17"
    assert "503" in result.stopped.error
    assert len(result.failures) == 2


def test_aggregate_outcomes_skips_permanent_failures_when_picking_stop_id():
    entries = _batch_entries(3)
    outcomes = [
        EntryOutcome(
            group_id=1,
            reference="John 3:16",
            kind="failure",
            error="gemini failed",
            transient=False,
        ),
        EntryOutcome(
            group_id=2,
            reference="John 3:17",
            kind="failure",
            error="503 UNAVAILABLE",
            transient=True,
        ),
        EntryOutcome(group_id=3, reference="John 3:18", kind="skipped"),
    ]

    result = _aggregate_outcomes(entries, outcomes)

    assert result.stopped is not None
    assert result.stopped.group_id == 2
    assert "503" in result.stopped.error


def test_aggregate_outcomes_uses_transient_failure_at_stop_id_when_present():
    entries = _batch_entries(3)
    outcomes = [
        EntryOutcome(
            group_id=1,
            reference="John 3:16",
            kind="failure",
            error="503 UNAVAILABLE",
            transient=True,
        ),
        EntryOutcome(group_id=2, reference="John 3:17", kind="skipped"),
        EntryOutcome(group_id=3, reference="John 3:18", kind="skipped"),
    ]

    result = _aggregate_outcomes(entries, outcomes)

    assert result.stopped is not None
    assert result.stopped.group_id == 1
    assert result.stopped.error == "503 UNAVAILABLE"


def test_aggregate_outcomes_uses_synthetic_stop_when_resume_id_has_only_skipped_outcomes():
    entries = _batch_entries(3)
    outcomes = [
        EntryOutcome(
            group_id=1,
            reference="John 3:16",
            kind="success",
            result=_success_result(
                VerseReference(book="John", chapter=3, start_verse=16, end_verse=16),
                Path("unused"),
            ),
        ),
        EntryOutcome(group_id=2, reference="John 3:17", kind="skipped"),
        EntryOutcome(group_id=3, reference="John 3:18", kind="skipped"),
    ]

    result = _aggregate_outcomes(entries, outcomes)

    assert result.stopped is not None
    assert result.stopped.group_id == 2
    assert result.stopped.error == "stopped after transient API error"


def test_run_batch_returns_partial_result_when_keyboard_interrupt_occurs(tmp_path, monkeypatch):
    entries = _batch_entries(2)
    bible = MagicMock()
    submitted_futures: list[MagicMock] = []
    success_outcome = EntryOutcome(
        group_id=1,
        reference="John 3:16",
        kind="success",
        result=_success_result(
            VerseReference(book="John", chapter=3, start_verse=16, end_verse=16),
            tmp_path,
        ),
    )

    class FakeExecutor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def submit(self, *args, **kwargs):
            future = MagicMock()
            submitted_futures.append(future)
            return future

        def shutdown(self, wait=True, cancel_futures=False):
            pass

    def fake_as_completed(futures):
        futures[0].result.return_value = success_outcome
        yield futures[0]
        raise KeyboardInterrupt()

    monkeypatch.setattr(
        "generate_batch.ThreadPoolExecutor",
        lambda max_workers: FakeExecutor(),
    )
    monkeypatch.setattr("generate_batch.as_completed", fake_as_completed)

    result = run_batch(entries, bible=bible, output_dir=tmp_path, workers=2)

    assert result.generated == 1
    assert result.stopped is not None
    assert result.stopped.group_id == 2
    assert result.stopped.error == "interrupted by user"


def test_run_batch_cancels_futures_when_keyboard_interrupt_occurs(tmp_path, monkeypatch):
    entries = _batch_entries(2)
    bible = MagicMock()
    submitted_futures: list[MagicMock] = []

    class FakeExecutor:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def submit(self, *args, **kwargs):
            future = MagicMock()
            submitted_futures.append(future)
            return future

        def shutdown(self, wait=True, cancel_futures=False):
            pass

    def fake_as_completed(futures):
        yield futures[0]
        raise KeyboardInterrupt()

    monkeypatch.setattr(
        "generate_batch.ThreadPoolExecutor",
        lambda max_workers: FakeExecutor(),
    )
    monkeypatch.setattr("generate_batch.as_completed", fake_as_completed)

    run_batch(entries, bible=bible, output_dir=tmp_path, workers=2)

    assert submitted_futures
    for future in submitted_futures:
        future.cancel.assert_called_once()


def test_run_batch_sets_stop_to_lowest_unfinished_id_when_transient_with_workers_gt_1(
    tmp_path, monkeypatch
):
    entries = _batch_entries(3)
    bible = MagicMock()

    def generate_side_effect(reference, **kwargs):
        if reference.start_verse == 16:
            raise FakeServerError(503)
        return _success_result(reference, tmp_path)

    monkeypatch.setattr("generate_batch.generate_for_reference", generate_side_effect)
    result = run_batch(entries, bible=bible, output_dir=tmp_path, workers=3)

    assert result.stopped is not None
    assert result.stopped.group_id == 1
    assert result.stopped.reference == "John 3:16"
    assert "503" in result.stopped.error
    assert result.generated <= 2


def test_run_batch_reports_no_stop_point_when_all_entries_succeed(tmp_path, monkeypatch):
    entries = [
        {"id": 1, "reference": "John 3:16", "book": "John", "chapter": 3, "start_verse": 16, "end_verse": 16},
    ]
    bible = MagicMock()

    def generate_side_effect(reference, **kwargs):
        return GenerationResult(
            reference=reference,
            verse_text="16 text",
            flux_prompt="prompt",
            output_path=tmp_path / "saved.png",
            bible_ms=1.0,
            gemini_ms=2.0,
            flux_ms=3.0,
        )

    monkeypatch.setattr("generate_batch.generate_for_reference", generate_side_effect)
    result = run_batch(entries, bible=bible, output_dir=tmp_path)

    assert result.generated == 1
    assert result.stopped is None


def test_write_failures_writes_json(tmp_path):
    from generate_batch import BatchFailure

    failures_path = tmp_path / "failures.json"
    write_failures(
        failures_path,
        [BatchFailure(group_id=7, reference="John 3:16", error="boom")],
    )

    payload = json.loads(failures_path.read_text(encoding="utf-8"))
    assert payload["failures"] == [
        {"id": 7, "reference": "John 3:16", "error": "boom"},
    ]


def _sample_manifest(tmp_path: Path) -> Path:
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(
        json.dumps(
            {
                "groups": [
                    {
                        "id": 1,
                        "reference": "John 3:16",
                        "book": "John",
                        "chapter": 3,
                        "start_verse": 16,
                        "end_verse": 16,
                        "slug": "John_3_16-16",
                    },
                    {
                        "id": 2,
                        "reference": "John 3:17",
                        "book": "John",
                        "chapter": 3,
                        "start_verse": 17,
                        "end_verse": 17,
                        "slug": "John_3_17-17",
                    },
                    {
                        "id": 3,
                        "reference": "John 3:18",
                        "book": "John",
                        "chapter": 3,
                        "start_verse": 18,
                        "end_verse": 18,
                        "slug": "John_3_18-18",
                    },
                ]
            }
        ),
        encoding="utf-8",
    )
    return manifest_path


def test_main_passes_workers_to_run_batch(tmp_path, monkeypatch):
    manifest_path = _sample_manifest(tmp_path)
    output_dir = tmp_path / "output"
    output_dir.mkdir()

    monkeypatch.setattr(generate_batch, "DEFAULT_STOP_POINT", tmp_path / "stop_point.json")
    monkeypatch.setattr(generate_batch, "BibleClient", MagicMock)
    captured: dict = {}

    def fake_run_batch(entries, **kwargs):
        captured["workers"] = kwargs.get("workers")
        return BatchResult(generated=0, failures=[])

    monkeypatch.setattr(generate_batch, "run_batch", fake_run_batch)

    generate_batch.main(
        [
            "--manifest",
            str(manifest_path),
            "--output-dir",
            str(output_dir),
            "--workers",
            "4",
        ]
    )

    assert captured["workers"] == 4


def test_main_errors_when_workers_lt_1(tmp_path, monkeypatch):
    manifest_path = _sample_manifest(tmp_path)
    output_dir = tmp_path / "output"
    output_dir.mkdir()

    with pytest.raises(SystemExit) as exc_info:
        generate_batch.main(
            [
                "--manifest",
                str(manifest_path),
                "--output-dir",
                str(output_dir),
                "--workers",
                "0",
            ]
        )

    assert exc_info.value.code != 0


def test_main_starts_at_stop_point_group_id_when_no_from_id(tmp_path, monkeypatch, capsys):
    manifest_path = _sample_manifest(tmp_path)
    stop_path = tmp_path / "stop_point.json"
    output_dir = tmp_path / "output"
    output_dir.mkdir()
    stop_path.write_text(
        json.dumps({"group_id": 2, "reference": "John 3:17", "error": "503 UNAVAILABLE"}),
        encoding="utf-8",
    )

    monkeypatch.setattr(generate_batch, "DEFAULT_STOP_POINT", stop_path)
    monkeypatch.setattr(generate_batch, "BibleClient", MagicMock)
    captured: dict = {}

    def fake_run_batch(entries, **kwargs):
        captured["entry_ids"] = [entry["id"] for entry in entries]
        return BatchResult(generated=2, failures=[])

    monkeypatch.setattr(generate_batch, "run_batch", fake_run_batch)

    exit_code = generate_batch.main(
        ["--manifest", str(manifest_path), "--output-dir", str(output_dir)]
    )

    assert exit_code == 0
    assert captured["entry_ids"] == [2, 3]
    assert "Resuming from group 2 (John 3:17)" in capsys.readouterr().out


def test_main_ignores_stop_point_when_from_id_is_passed_explicitly(
    tmp_path, monkeypatch, capsys
):
    manifest_path = _sample_manifest(tmp_path)
    stop_path = tmp_path / "stop_point.json"
    output_dir = tmp_path / "output"
    output_dir.mkdir()
    stop_path.write_text(
        json.dumps({"group_id": 2, "reference": "John 3:17", "error": "503 UNAVAILABLE"}),
        encoding="utf-8",
    )

    monkeypatch.setattr(generate_batch, "DEFAULT_STOP_POINT", stop_path)
    monkeypatch.setattr(generate_batch, "BibleClient", MagicMock)
    captured: dict = {}

    def fake_run_batch(entries, **kwargs):
        captured["entry_ids"] = [entry["id"] for entry in entries]
        return BatchResult(generated=1, failures=[])

    monkeypatch.setattr(generate_batch, "run_batch", fake_run_batch)

    generate_batch.main(
        [
            "--manifest",
            str(manifest_path),
            "--output-dir",
            str(output_dir),
            "--from-id",
            "1",
        ]
    )

    assert captured["entry_ids"] == [1, 2, 3]
    assert "Resuming from group" not in capsys.readouterr().out


def test_main_deletes_stop_point_when_run_completes_without_stopping(tmp_path, monkeypatch):
    manifest_path = _sample_manifest(tmp_path)
    stop_path = tmp_path / "stop_point.json"
    output_dir = tmp_path / "output"
    output_dir.mkdir()
    stop_path.write_text(
        json.dumps({"group_id": 2, "reference": "John 3:17", "error": "503 UNAVAILABLE"}),
        encoding="utf-8",
    )

    monkeypatch.setattr(generate_batch, "DEFAULT_STOP_POINT", stop_path)
    monkeypatch.setattr(generate_batch, "BibleClient", MagicMock)
    monkeypatch.setattr(
        generate_batch,
        "run_batch",
        lambda entries, **kwargs: BatchResult(generated=2, failures=[]),
    )

    generate_batch.main(["--manifest", str(manifest_path), "--output-dir", str(output_dir)])

    assert not stop_path.exists()


def test_main_keeps_stop_point_when_run_stops_again(tmp_path, monkeypatch):
    manifest_path = _sample_manifest(tmp_path)
    stop_path = tmp_path / "stop_point.json"
    output_dir = tmp_path / "output"
    output_dir.mkdir()
    stop_path.write_text(
        json.dumps({"group_id": 2, "reference": "John 3:17", "error": "503 UNAVAILABLE"}),
        encoding="utf-8",
    )

    monkeypatch.setattr(generate_batch, "DEFAULT_STOP_POINT", stop_path)
    monkeypatch.setattr(generate_batch, "BibleClient", MagicMock)
    monkeypatch.setattr(
        generate_batch,
        "run_batch",
        lambda entries, **kwargs: BatchResult(
            generated=0,
            failures=[BatchFailure(group_id=2, reference="John 3:17", error="503 UNAVAILABLE")],
            stopped=BatchFailure(group_id=2, reference="John 3:17", error="503 UNAVAILABLE"),
        ),
    )

    generate_batch.main(["--manifest", str(manifest_path), "--output-dir", str(output_dir)])

    assert stop_path.exists()
    payload = json.loads(stop_path.read_text(encoding="utf-8"))
    assert payload["group_id"] == 2
