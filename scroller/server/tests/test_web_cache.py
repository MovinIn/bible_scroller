import pytest

from src.web_cache import CachedStaticFiles, pipeline_media_cache_control, web_cache_headers


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


def test_marks_font_manifest_as_no_cache() -> None:
    headers = web_cache_headers("assets/FontManifest.json")

    assert headers["Cache-Control"] == "no-cache, must-revalidate"


def test_marks_asset_manifest_as_no_cache() -> None:
    headers = web_cache_headers("assets/AssetManifest.bin.json")

    assert headers["Cache-Control"] == "no-cache, must-revalidate"


def test_marks_material_icons_font_as_no_cache() -> None:
    """Tree-shaken MaterialIcons keeps a stable URL; immutable cache blanks new icons."""
    headers = web_cache_headers("assets/fonts/MaterialIcons-Regular.otf")

    assert headers["Cache-Control"] == "no-cache, must-revalidate"


def test_keeps_hashed_package_assets_immutable() -> None:
    headers = web_cache_headers("assets/packages/cupertino_icons/assets/CupertinoIcons.ttf")

    assert headers["Cache-Control"] == "public, max-age=31536000, immutable"


@pytest.mark.asyncio
async def test_cached_static_files_revalidates_material_icons(tmp_path) -> None:
    fonts = tmp_path / "fonts"
    fonts.mkdir()
    font_file = fonts / "MaterialIcons-Regular.otf"
    font_file.write_bytes(b"otf")

    static = CachedStaticFiles(directory=tmp_path, mount_prefix="assets")
    response = await static.get_response(
        "fonts/MaterialIcons-Regular.otf",
        {"type": "http", "method": "GET", "headers": []},
    )

    assert response.status_code == 200
    assert response.headers["Cache-Control"] == "no-cache, must-revalidate"
