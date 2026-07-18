from __future__ import annotations

import importlib.util
import os
import sys
from pathlib import Path

PIPELINE_ROOT = Path(__file__).resolve().parent.parent

REQUIRED_PACKAGES: tuple[tuple[str, str], ...] = (
    ("fal_client", "fal-client"),
    ("google.genai", "google-genai"),
    ("httpx", "httpx"),
    ("dotenv", "python-dotenv"),
)


def _missing_packages() -> list[str]:
    missing: list[str] = []
    for import_name, pip_name in REQUIRED_PACKAGES:
        if importlib.util.find_spec(import_name) is None:
            missing.append(pip_name)
    return missing


def _venv_python() -> Path | None:
    if os.name == "nt":
        candidate = PIPELINE_ROOT / ".venv" / "Scripts" / "python.exe"
    else:
        candidate = PIPELINE_ROOT / ".venv" / "bin" / "python"
    return candidate if candidate.is_file() else None


def ensure_pipeline_python() -> None:
    """Re-exec with the pipeline venv when deps are missing but .venv exists."""
    missing = _missing_packages()
    if not missing:
        return

    venv_python = _venv_python()
    if venv_python is not None and Path(sys.executable).resolve() != venv_python.resolve():
        os.execv(str(venv_python), [str(venv_python), *sys.argv])

    packages = ", ".join(missing)
    raise SystemExit(
        "Missing Python packages: "
        f"{packages}\n\n"
        "From the pipeline/ directory, create or activate the venv and install deps:\n"
        "  python -m venv .venv\n"
        "  .venv\\Scripts\\activate          # Windows\n"
        "  # source .venv/bin/activate       # macOS / Linux\n"
        "  pip install -r requirements.txt\n"
        "  python generate_one.py \"John 3:16-20\""
    )
