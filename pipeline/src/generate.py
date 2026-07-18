from __future__ import annotations

import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from src.bible_client import BibleClient
from src.config import DEFAULT_META_PROMPT, OUTPUT_DIR
from src.flux_client import generate_image
from src.gemini_client import generate_flux_prompt
from src.reference import VerseReference


@dataclass(frozen=True)
class GenerationResult:
    reference: VerseReference
    verse_text: str
    flux_prompt: str
    output_path: Path
    bible_ms: float
    gemini_ms: float
    flux_ms: float


def generate_for_reference(
    reference: VerseReference,
    *,
    bible: BibleClient,
    extra_guidance: str = "",
    meta_prompt_path: Path = DEFAULT_META_PROMPT,
    theme_guidance: str = "",
    output_dir: Path = OUTPUT_DIR,
    cache_dir: Path | None = None,
    use_cache: bool = True,
    timestamp: str | None = None,
) -> GenerationResult:
    if timestamp is None:
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output_path = output_dir / f"{reference.slug()}_{timestamp}.png"

    t0 = time.perf_counter()
    verse_text = bible.fetch_verse_text(
        reference,
        cache_dir=cache_dir,
        use_cache=use_cache,
    )
    bible_ms = (time.perf_counter() - t0) * 1000

    t1 = time.perf_counter()
    flux_prompt = generate_flux_prompt(
        verse_text=verse_text,
        extra_guidance=extra_guidance,
        meta_prompt_path=meta_prompt_path,
        theme_guidance=theme_guidance,
    )
    gemini_ms = (time.perf_counter() - t1) * 1000

    t2 = time.perf_counter()
    saved_path = generate_image(flux_prompt, output_path)
    flux_ms = (time.perf_counter() - t2) * 1000

    return GenerationResult(
        reference=reference,
        verse_text=verse_text,
        flux_prompt=flux_prompt,
        output_path=saved_path,
        bible_ms=bible_ms,
        gemini_ms=gemini_ms,
        flux_ms=flux_ms,
    )
