"""HTTP-level checks for Flutter entry-file cache headers when static web exists."""

from src.web_app import resolve_web_root


def test_serves_main_dart_js_with_no_cache_when_web_bundle_present(client) -> None:
    web_root = resolve_web_root()
    if web_root is None or not (web_root / "main.dart.js").is_file():
        return

    response = client.get("/main.dart.js")

    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-cache, must-revalidate"


def test_serves_index_html_with_no_cache_when_web_bundle_present(client) -> None:
    web_root = resolve_web_root()
    if web_root is None or not (web_root / "index.html").is_file():
        return

    response = client.get("/")

    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-cache, must-revalidate"
