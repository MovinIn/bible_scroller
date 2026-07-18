from src.web_app import resolve_web_root


def test_returns_ok_status_when_health_is_checked(client) -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_returns_flutter_index_when_web_bundle_is_present(client) -> None:
    if resolve_web_root() is None:
        # Bundle is built locally into static/web; skip when absent (e.g. CI without Flutter).
        return

    response = client.get("/")

    assert response.status_code == 200
    assert "text/html" in response.headers.get("content-type", "")
    assert b"<html" in response.content.lower() or b"flutter" in response.content.lower()


def test_keeps_reels_json_when_web_bundle_is_present(client) -> None:
    response = client.get("/reels?limit=1")

    assert response.status_code == 200
    assert "items" in response.json()

