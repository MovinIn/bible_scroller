#!/usr/bin/env python3
"""Generate FLUX images for verse groups listed in a manifest."""

from __future__ import annotations

import argparse
import json
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from src.runtime import ensure_pipeline_python

ensure_pipeline_python()

from dotenv import load_dotenv

from src.bible_client import BibleClient
from src.cli_args import add_extra_argument, join_cli_words
from src.config import (
    CHAPTER_CACHE_DIR,
    DEFAULT_FAILURES,
    DEFAULT_MANIFEST,
    DEFAULT_META_PROMPT,
    DEFAULT_STOP_POINT,
    DEFAULT_THEMES,
    OUTPUT_DIR,
    PROMPTS_DIR,
    THEME_OVERRIDES,
    THEME_REGISTRY,
)
from src.generate import GenerationResult, generate_for_reference
from src.progress import clear_stop_point, read_stop_point, write_stop_point
from src.reference import VerseReference
from src.theme_resolver import resolve_generation_theme
from src.retry import is_transient_error


@dataclass(frozen=True)
class BatchFailure:
    group_id: int
    reference: str
    error: str


@dataclass(frozen=True)
class EntryOutcome:
    group_id: int
    reference: str
    kind: Literal["success", "failure", "skipped"]
    result: GenerationResult | None = None
    error: str | None = None
    transient: bool = False


@dataclass(frozen=True)
class BatchResult:
    generated: int
    failures: list[BatchFailure]
    stopped: BatchFailure | None = None


def _matches_filters(
    entry: dict,
    *,
    book_filter: str | None,
    from_id: int | None,
    to_id: int | None,
) -> bool:
    group_id = int(entry["id"])
    if from_id is not None and group_id < from_id:
        return False
    if to_id is not None and group_id > to_id:
        return False
    if book_filter is not None and entry["book"].casefold() != book_filter.casefold():
        return False
    return True


def _entry_to_reference(entry: dict) -> VerseReference:
    return VerseReference(
        book=entry["book"],
        chapter=int(entry["chapter"]),
        start_verse=int(entry["start_verse"]),
        end_verse=int(entry["end_verse"]),
    )


def _existing_output_slugs(output_dir: Path) -> set[str]:
    if not output_dir.exists():
        return set()
    slugs: set[str] = set()
    for path in output_dir.glob("*.png"):
        stem = path.stem
        if "_" in stem:
            slugs.add(stem.rsplit("_", 1)[0])
    return slugs


def select_entries(
    entries: list[dict],
    *,
    book_filter: str | None,
    from_id: int | None,
    to_id: int | None,
    limit: int | None,
    output_dir: Path,
    force: bool,
) -> list[dict]:
    existing_slugs = set() if force else _existing_output_slugs(output_dir)
    selected: list[dict] = []
    for entry in entries:
        if not _matches_filters(
            entry,
            book_filter=book_filter,
            from_id=from_id,
            to_id=to_id,
        ):
            continue
        if not force and entry["slug"] in existing_slugs:
            print(f"Skipping {entry['reference']} (output exists)")
            continue
        selected.append(entry)
        if limit is not None and len(selected) >= limit:
            break
    return selected


def _process_one_entry(
    entry: dict,
    *,
    bible: BibleClient,
    extra_guidance: str,
    meta_prompt_path: Path,
    themes_path: Path | None,
    output_dir: Path,
    cache_dir: Path | None,
    use_cache: bool,
    stop_event: threading.Event | None = None,
) -> EntryOutcome:
    group_id = int(entry["id"])
    reference_label = entry["reference"]

    if stop_event is not None and stop_event.is_set():
        return EntryOutcome(
            group_id=group_id,
            reference=reference_label,
            kind="skipped",
        )

    reference = _entry_to_reference(entry)
    print(f"Generating {reference_label}...")
    try:
        entry_meta_prompt, theme_guidance, resolved = resolve_generation_theme(
            entry["book"],
            int(entry["chapter"]),
            themes_path=themes_path,
            fallback_meta_prompt=meta_prompt_path,
            registry_path=THEME_REGISTRY,
            overrides_path=THEME_OVERRIDES,
            prompts_dir=PROMPTS_DIR,
        )
        if resolved is not None:
            print(
                f"  Theme: {resolved.assignment.theme_id} "
                f"({resolved.assignment.style}, {resolved.source})"
            )
        result = generate_for_reference(
            reference,
            bible=bible,
            extra_guidance=extra_guidance,
            meta_prompt_path=entry_meta_prompt,
            theme_guidance=theme_guidance,
            output_dir=output_dir,
            cache_dir=cache_dir,
            use_cache=use_cache,
        )
    except Exception as exc:
        transient = is_transient_error(exc)
        if transient and stop_event is not None:
            stop_event.set()
        print(f"  Failed: {exc}")
        return EntryOutcome(
            group_id=group_id,
            reference=reference_label,
            kind="failure",
            error=str(exc),
            transient=transient,
        )

    _print_generation_result(result)
    return EntryOutcome(
        group_id=group_id,
        reference=reference_label,
        kind="success",
        result=result,
    )


def _aggregate_outcomes(
    entries: list[dict],
    outcomes: list[EntryOutcome],
) -> BatchResult:
    completed_ids = {outcome.group_id for outcome in outcomes if outcome.kind == "success"}
    failures = [
        BatchFailure(
            group_id=outcome.group_id,
            reference=outcome.reference,
            error=outcome.error or "",
        )
        for outcome in outcomes
        if outcome.kind == "failure"
    ]
    generated = len(completed_ids)

    stopped: BatchFailure | None = None
    has_transient = any(outcome.transient for outcome in outcomes if outcome.kind == "failure")
    has_skipped = any(outcome.kind == "skipped" for outcome in outcomes)
    if has_transient or has_skipped:
        permanent_failure_ids = {
            outcome.group_id
            for outcome in outcomes
            if outcome.kind == "failure" and not outcome.transient
        }
        resume_candidates = [
            int(entry["id"])
            for entry in entries
            if int(entry["id"]) not in completed_ids
            and int(entry["id"]) not in permanent_failure_ids
        ]
        if resume_candidates:
            stop_id = min(resume_candidates)
            stop_entry = next(entry for entry in entries if int(entry["id"]) == stop_id)
            stop_failure = next(
                (
                    BatchFailure(
                        group_id=outcome.group_id,
                        reference=outcome.reference,
                        error=outcome.error or "",
                    )
                    for outcome in outcomes
                    if outcome.group_id == stop_id and outcome.kind == "failure"
                ),
                None,
            )
            if stop_failure is not None:
                stopped = stop_failure
            else:
                stopped = BatchFailure(
                    group_id=stop_id,
                    reference=stop_entry["reference"],
                    error="stopped after transient API error",
                )

    return BatchResult(generated=generated, failures=failures, stopped=stopped)


def run_batch(
    entries: list[dict],
    *,
    bible: BibleClient,
    extra_guidance: str = "",
    meta_prompt_path: Path = DEFAULT_META_PROMPT,
    themes_path: Path | None = DEFAULT_THEMES,
    output_dir: Path = OUTPUT_DIR,
    cache_dir: Path | None = None,
    use_cache: bool = True,
    workers: int = 1,
) -> BatchResult:
    if workers <= 1:
        return _run_batch_sequential(
            entries,
            bible=bible,
            extra_guidance=extra_guidance,
            meta_prompt_path=meta_prompt_path,
            themes_path=themes_path,
            output_dir=output_dir,
            cache_dir=cache_dir,
            use_cache=use_cache,
        )

    stop_event = threading.Event()
    outcomes: list[EntryOutcome] = []
    interrupted = False

    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = [
            executor.submit(
                _process_one_entry,
                entry,
                bible=bible,
                extra_guidance=extra_guidance,
                meta_prompt_path=meta_prompt_path,
                themes_path=themes_path,
                output_dir=output_dir,
                cache_dir=cache_dir,
                use_cache=use_cache,
                stop_event=stop_event,
            )
            for entry in entries
        ]
        try:
            for future in as_completed(futures):
                outcomes.append(future.result())
        except KeyboardInterrupt:
            interrupted = True
            stop_event.set()
            for future in futures:
                future.cancel()
        finally:
            if interrupted:
                executor.shutdown(wait=False, cancel_futures=True)

    result = _aggregate_outcomes(entries, outcomes)
    if interrupted and result.stopped is None:
        completed_ids = {
            outcome.group_id for outcome in outcomes if outcome.kind == "success"
        }
        resume_candidates = [
            int(entry["id"])
            for entry in entries
            if int(entry["id"]) not in completed_ids
        ]
        if resume_candidates:
            stop_id = min(resume_candidates)
            stop_entry = next(entry for entry in entries if int(entry["id"]) == stop_id)
            result = BatchResult(
                generated=result.generated,
                failures=result.failures,
                stopped=BatchFailure(
                    group_id=stop_id,
                    reference=stop_entry["reference"],
                    error="interrupted by user",
                ),
            )

    return result


def _run_batch_sequential(
    entries: list[dict],
    *,
    bible: BibleClient,
    extra_guidance: str,
    meta_prompt_path: Path,
    themes_path: Path | None,
    output_dir: Path,
    cache_dir: Path | None,
    use_cache: bool,
) -> BatchResult:
    outcomes: list[EntryOutcome] = []
    for entry in entries:
        outcome = _process_one_entry(
            entry,
            bible=bible,
            extra_guidance=extra_guidance,
            meta_prompt_path=meta_prompt_path,
            themes_path=themes_path,
            output_dir=output_dir,
            cache_dir=cache_dir,
            use_cache=use_cache,
        )
        outcomes.append(outcome)
        if outcome.transient:
            break

    return _aggregate_outcomes(entries, outcomes)


def _print_generation_result(result: GenerationResult) -> None:
    print(f"  Saved: {result.output_path}")
    print(
        f"  Timing: bible={result.bible_ms:.0f}ms "
        f"gemini={result.gemini_ms:.0f}ms flux={result.flux_ms:.0f}ms"
    )


def write_failures(path: Path, failures: list[BatchFailure]) -> None:
    payload = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "failures": [
            {
                "id": failure.group_id,
                "reference": failure.reference,
                "error": failure.error,
            }
            for failure in failures
        ],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    load_dotenv()

    parser = argparse.ArgumentParser(
        description="Generate FLUX images for groups in a manifest JSON file.",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
        help="Path to manifest JSON from group_bible.py",
    )
    parser.add_argument("--book", help='Process only one book, e.g. "John"')
    parser.add_argument("--from-id", type=int, help="Start at this manifest group id (inclusive)")
    parser.add_argument("--to-id", type=int, help="Stop at this manifest group id (inclusive)")
    parser.add_argument(
        "--limit",
        type=int,
        help="Maximum number of new images to generate (skips do not count)",
    )
    add_extra_argument(parser)
    parser.add_argument(
        "--meta-prompt",
        type=Path,
        default=DEFAULT_META_PROMPT,
        help="Fallback meta-prompt when themes.json is missing",
    )
    parser.add_argument(
        "--themes",
        type=Path,
        default=DEFAULT_THEMES,
        help="Per-chapter themes JSON from assign_themes.py (used when file exists)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=OUTPUT_DIR,
        help="Directory for generated images",
    )
    parser.add_argument(
        "--failures",
        type=Path,
        default=DEFAULT_FAILURES,
        help="Path for failures JSON output",
    )
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=CHAPTER_CACHE_DIR,
        help="Directory for cached chapter JSON",
    )
    parser.add_argument(
        "--no-cache",
        action="store_true",
        help="Always fetch chapters from the API (do not read or write cache)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Generate even if an output PNG already exists for the slug",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=1,
        help="Parallel image workers (default: 1 = sequential). Use 8 on paid tier, 3 on free tier.",
    )
    args = parser.parse_args(argv)
    extra_guidance = join_cli_words(args.extra)

    if args.workers < 1:
        parser.error("--workers must be at least 1")

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    entries = manifest.get("groups", [])

    from_id = args.from_id
    stop_point = read_stop_point(DEFAULT_STOP_POINT)
    if from_id is None and stop_point and "group_id" in stop_point:
        from_id = int(stop_point["group_id"])
        print(
            f"Resuming from group {from_id} ({stop_point.get('reference')}) "
            f"per {DEFAULT_STOP_POINT}"
        )

    selected = select_entries(
        entries,
        book_filter=args.book,
        from_id=from_id,
        to_id=args.to_id,
        limit=args.limit,
        output_dir=args.output_dir,
        force=args.force,
    )

    if not selected:
        print("No groups selected for generation.")
        clear_stop_point(DEFAULT_STOP_POINT)
        return 0

    use_cache = not args.no_cache
    cache_dir = None if args.no_cache else args.cache_dir

    bible = BibleClient()
    try:
        result = run_batch(
            selected,
            bible=bible,
            extra_guidance=extra_guidance,
            meta_prompt_path=args.meta_prompt,
            themes_path=args.themes,
            output_dir=args.output_dir,
            cache_dir=cache_dir,
            use_cache=use_cache,
            workers=args.workers,
        )
    finally:
        bible.close()

    if result.failures:
        write_failures(args.failures, result.failures)
        print(f"\nWrote {len(result.failures)} failure(s) to {args.failures}")

    if result.stopped is not None:
        resume_hint = f"python generate_batch.py --from-id {result.stopped.group_id}"
        write_stop_point(
            DEFAULT_STOP_POINT,
            reference=result.stopped.reference,
            error=result.stopped.error,
            group_id=result.stopped.group_id,
            resume_hint=resume_hint,
        )
        print(
            f"\nStopped at group {result.stopped.group_id} "
            f"({result.stopped.reference}) after repeated temporary errors."
        )
        print(f"Stop point saved to {DEFAULT_STOP_POINT}")
        print(f"Resume with: {resume_hint}")
    elif result.stopped is None:
        clear_stop_point(DEFAULT_STOP_POINT)

    print(f"\nGenerated {result.generated} image(s).")
    return 1 if result.failures or result.stopped else 0


if __name__ == "__main__":
    raise SystemExit(main())
