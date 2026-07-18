from types import SimpleNamespace

from src.flux_client import generate_image


class FakeServerError(Exception):
    def __init__(self, code: int):
        super().__init__(f"{code} UNAVAILABLE")
        self.code = code


class FakeHttpxClient:
    def __init__(self, **kwargs):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def get(self, url):
        return SimpleNamespace(
            content=b"png-bytes",
            raise_for_status=lambda: None,
        )


def test_generate_image_saves_file_after_retry_when_flux_returns_503_once(
    tmp_path, monkeypatch
):
    sleeps: list[float] = []
    monkeypatch.setattr("src.retry.time.sleep", sleeps.append)
    monkeypatch.setattr("src.flux_client.httpx.Client", FakeHttpxClient)

    calls = {"count": 0}

    def fake_subscribe(model, arguments):
        calls["count"] += 1
        if calls["count"] == 1:
            raise FakeServerError(503)
        return {"images": [{"url": "https://example.com/image.png"}]}

    monkeypatch.setattr("src.flux_client.fal_client.subscribe", fake_subscribe)

    output_path = tmp_path / "out" / "image.png"
    saved = generate_image("a prompt", output_path, api_key="test-key")

    assert saved == output_path
    assert output_path.read_bytes() == b"png-bytes"
    assert calls["count"] == 2
    assert sleeps == [15]
