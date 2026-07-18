from pathlib import Path

from src.web_app import is_spa_fallback_path, resolve_web_root, web_index_path


def test_returns_false_when_path_is_api_prefix() -> None:
    for path in (
        "/reels",
        "/reels/1/comments",
        "/comments/1/like",
        "/bible/versions",
        "/users/me",
        "/auth/google",
        "/health",
        "/media/pipeline/foo.png",
        "/docs",
        "/openapi.json",
        "/assets/AssetManifest.json",
    ):
        assert is_spa_fallback_path(path) is False


def test_returns_true_when_path_is_app_route() -> None:
    assert is_spa_fallback_path("/") is True
    assert is_spa_fallback_path("/feed") is True
    assert is_spa_fallback_path("/some/deep/link") is True


def test_returns_web_root_when_static_web_exists(tmp_path: Path, monkeypatch) -> None:
    web_dir = tmp_path / "static" / "web"
    web_dir.mkdir(parents=True)
    (web_dir / "index.html").write_text("<html></html>", encoding="utf-8")
    monkeypatch.setattr("src.web_app._SERVER_ROOT", tmp_path)

    assert resolve_web_root() == web_dir
    assert web_index_path() == web_dir / "index.html"


def test_returns_none_when_web_bundle_is_missing(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr("src.web_app._SERVER_ROOT", tmp_path)

    assert resolve_web_root() is None
    assert web_index_path() is None
