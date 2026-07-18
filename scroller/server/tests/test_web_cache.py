from src.web_cache import pipeline_media_cache_control, web_cache_headers


def test_marks_canvaskit_assets_as_immutable() -> None:
    headers = web_cache_headers("canvaskit/canvaskit.wasm")

    assert headers["Cache-Control"] == "public, max-age=31536000, immutable"


def test_marks_entry_html_as_no_cache() -> None:
    headers = web_cache_headers("index.html")

    assert headers["Cache-Control"] == "no-cache, must-revalidate"


def test_marks_flutter_bootstrap_as_no_cache() -> None:
    headers = web_cache_headers("flutter_bootstrap.js")

    assert headers["Cache-Control"] == "no-cache, must-revalidate"


def test_marks_main_dart_js_as_no_cache() -> None:
    headers = web_cache_headers("main.dart.js")

    assert headers["Cache-Control"] == "no-cache, must-revalidate"


def test_marks_main_dart_wasm_as_no_cache() -> None:
    headers = web_cache_headers("main.dart.wasm")

    assert headers["Cache-Control"] == "no-cache, must-revalidate"


def test_uses_week_long_ttl_for_pipeline_media() -> None:
    assert pipeline_media_cache_control() == "public, max-age=604800"
