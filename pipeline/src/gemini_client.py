from __future__ import annotations

import os
from pathlib import Path

from google import genai

from src.config import DEFAULT_META_PROMPT, get_gemini_model
from src.retry import call_with_retries


def assemble_prompt(
    meta_prompt_path: Path,
    verse_text: str,
    extra_guidance: str,
    theme_guidance: str = "",
) -> str:
    template = meta_prompt_path.read_text(encoding="utf-8")
    guidance = extra_guidance.strip() or "(none)"
    theme = theme_guidance.strip() or "(none)"
    return (
        template.replace("{verse_text}", verse_text)
        .replace("{extra_guidance}", guidance)
        .replace("{theme_guidance}", theme)
    )


def generate_flux_prompt(
    verse_text: str,
    extra_guidance: str = "",
    meta_prompt_path: Path = DEFAULT_META_PROMPT,
    theme_guidance: str = "",
    api_key: str | None = None,
) -> str:
    prompt = assemble_prompt(
        meta_prompt_path,
        verse_text,
        extra_guidance,
        theme_guidance=theme_guidance,
    )
    return generate_gemini_text(prompt, api_key=api_key)


def generate_gemini_text(
    prompt: str,
    *,
    api_key: str | None = None,
) -> str:
    key = api_key or os.environ.get("GEMINI_API_KEY")
    if not key:
        raise ValueError("GEMINI_API_KEY is not set")

    client = genai.Client(api_key=key)
    response = call_with_retries(
        lambda: client.models.generate_content(
            model=get_gemini_model(),
            contents=prompt,
        ),
        description="Gemini text generation",
    )

    text = response.text
    if not text:
        raise RuntimeError("Gemini returned an empty response")
    return text.strip()
