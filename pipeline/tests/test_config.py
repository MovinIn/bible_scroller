from dotenv import load_dotenv

from src.config import get_gemini_model


def test_get_gemini_model_reads_gemini_model_from_dotenv_file(tmp_path, monkeypatch):
    env_path = tmp_path / ".env"
    env_path.write_text("GEMINI_MODEL=gemini-2.5-flash\n", encoding="utf-8")
    monkeypatch.delenv("GEMINI_MODEL", raising=False)

    load_dotenv(env_path, override=True)

    assert get_gemini_model() == "gemini-2.5-flash"
