"""Pipeline configuration constants."""

import os
from pathlib import Path

from dotenv import load_dotenv

PIPELINE_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(PIPELINE_ROOT / ".env")

PROMPTS_DIR = PIPELINE_ROOT / "prompts"
OUTPUT_DIR = PIPELINE_ROOT / "output"
GROUPS_DIR = OUTPUT_DIR / "groups"
DEFAULT_MANIFEST = GROUPS_DIR / "manifest.json"
CHAPTER_CACHE_DIR = PIPELINE_ROOT / "data" / "chapters"
DEFAULT_META_PROMPT = PROMPTS_DIR / "meta_prompt_realistic.txt"
THEME_REGISTRY = PROMPTS_DIR / "theme_registry.json"
THEME_OVERRIDES = PROMPTS_DIR / "theme_overrides.json"
DEFAULT_THEMES = GROUPS_DIR / "themes.json"

BIBLE_API_BASE = "https://bible.helloao.org/api"
BIBLE_TRANSLATION = "BSB"

DEFAULT_MIN_GROUP_SIZE = 4
DEFAULT_MAX_GROUP_SIZE = 5
CHAPTER_FETCH_DELAY_SECONDS = 0.1
HTTP_MAX_RETRIES = 3
HTTP_RETRY_BACKOFF_SECONDS = 0.5
HTTP_RETRYABLE_STATUS_CODES = frozenset({429, 500, 502, 503, 504})

DEFAULT_FAILURES = GROUPS_DIR / "failures.json"
DEFAULT_STOP_POINT = GROUPS_DIR / "stop_point.json"

GENERATION_MAX_RETRIES = 3
GENERATION_RETRY_DELAY_SECONDS = 15

DEFAULT_GEMINI_MODEL = "gemini-flash-lite-latest"


def get_gemini_model() -> str:
    return os.environ.get("GEMINI_MODEL", DEFAULT_GEMINI_MODEL)


FLUX_MODEL = "fal-ai/flux/schnell"
FLUX_IMAGE_WIDTH = 832
FLUX_IMAGE_HEIGHT = 1216
