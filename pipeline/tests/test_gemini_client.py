from pathlib import Path
from types import SimpleNamespace

import pytest

from src.gemini_client import assemble_prompt, generate_flux_prompt, generate_gemini_text


class FakeServerError(Exception):
    def __init__(self, code: int):
        super().__init__(f"{code} UNAVAILABLE")
        self.code = code


def test_uses_gemini_model_from_env_when_generate_gemini_text_is_called(monkeypatch):
    captured: dict = {}

    def fake_generate_content(**kwargs):
        captured["model"] = kwargs["model"]
        return SimpleNamespace(text="prompt text")

    fake_client = SimpleNamespace(
        models=SimpleNamespace(generate_content=fake_generate_content)
    )
    monkeypatch.setattr("src.gemini_client.genai.Client", lambda api_key: fake_client)
    monkeypatch.setenv("GEMINI_MODEL", "gemini-2.5-flash")

    result = generate_gemini_text("write a prompt", api_key="test-key")

    assert result == "prompt text"
    assert captured["model"] == "gemini-2.5-flash"


def test_injects_verse_text_and_extra_guidance_when_meta_prompt_has_placeholders(tmp_path: Path):
    meta_path = tmp_path / "meta_prompt.txt"
    meta_path.write_text(
        "Style guide.\n\nTheme:\n{theme_guidance}\n\nVerses:\n{verse_text}\n\nExtra:\n{extra_guidance}\n\nWrite one FLUX prompt.",
        encoding="utf-8",
    )

    result = assemble_prompt(
        meta_prompt_path=meta_path,
        verse_text="16 For God so loved the world,",
        extra_guidance="dawn light, hopeful mood",
        theme_guidance="Gospel mood.",
    )

    assert "16 For God so loved the world," in result
    assert "dawn light, hopeful mood" in result
    assert "Gospel mood." in result
    assert "{verse_text}" not in result
    assert "{extra_guidance}" not in result
    assert "{theme_guidance}" not in result


def test_uses_none_placeholder_when_theme_guidance_is_empty(tmp_path: Path):
    meta_path = tmp_path / "meta_prompt.txt"
    meta_path.write_text("Theme:\n{theme_guidance}", encoding="utf-8")

    result = assemble_prompt(
        meta_prompt_path=meta_path,
        verse_text="1 In the beginning",
        extra_guidance="",
        theme_guidance="",
    )

    assert "(none)" in result


def test_uses_none_placeholder_when_extra_guidance_is_empty(tmp_path: Path):
    meta_path = tmp_path / "meta_prompt.txt"
    meta_path.write_text("Verses:\n{verse_text}\nExtra:\n{extra_guidance}", encoding="utf-8")

    result = assemble_prompt(
        meta_prompt_path=meta_path,
        verse_text="1 In the beginning",
        extra_guidance="",
    )

    assert "1 In the beginning" in result
    assert "(none)" in result


def test_assemble_prompt_tolerates_braces_in_verse_text(tmp_path: Path):
    meta_path = tmp_path / "meta_prompt.txt"
    meta_path.write_text("Verses:\n{verse_text}\nExtra:\n{extra_guidance}", encoding="utf-8")

    result = assemble_prompt(
        meta_prompt_path=meta_path,
        verse_text="16 He said {peace} to them",
        extra_guidance="calm scene",
    )

    assert "16 He said {peace} to them" in result
    assert "calm scene" in result


def _meta_prompt(tmp_path: Path) -> Path:
    meta_path = tmp_path / "meta_prompt.txt"
    meta_path.write_text("Verses:\n{verse_text}\nExtra:\n{extra_guidance}", encoding="utf-8")
    return meta_path


def test_generate_flux_prompt_returns_text_after_retry_when_gemini_returns_503_once(
    tmp_path, monkeypatch
):
    sleeps: list[float] = []
    monkeypatch.setattr("src.retry.time.sleep", sleeps.append)

    calls = {"count": 0}

    def fake_generate_content(**kwargs):
        calls["count"] += 1
        if calls["count"] == 1:
            raise FakeServerError(503)
        return SimpleNamespace(text="a serene landscape prompt")

    fake_client = SimpleNamespace(
        models=SimpleNamespace(generate_content=fake_generate_content)
    )
    monkeypatch.setattr("src.gemini_client.genai.Client", lambda api_key: fake_client)

    result = generate_flux_prompt(
        verse_text="16 For God so loved the world,",
        meta_prompt_path=_meta_prompt(tmp_path),
        api_key="test-key",
    )

    assert result == "a serene landscape prompt"
    assert calls["count"] == 2
    assert sleeps == [15]


def test_generate_flux_prompt_raises_after_four_attempts_when_gemini_always_returns_503(
    tmp_path, monkeypatch
):
    sleeps: list[float] = []
    monkeypatch.setattr("src.retry.time.sleep", sleeps.append)

    calls = {"count": 0}

    def fake_generate_content(**kwargs):
        calls["count"] += 1
        raise FakeServerError(503)

    fake_client = SimpleNamespace(
        models=SimpleNamespace(generate_content=fake_generate_content)
    )
    monkeypatch.setattr("src.gemini_client.genai.Client", lambda api_key: fake_client)

    with pytest.raises(FakeServerError):
        generate_flux_prompt(
            verse_text="16 For God so loved the world,",
            meta_prompt_path=_meta_prompt(tmp_path),
            api_key="test-key",
        )

    assert calls["count"] == 4
    assert sleeps == [15, 15, 15]
