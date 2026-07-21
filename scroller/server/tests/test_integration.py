def test_returns_bible_versions_when_versions_endpoint_is_called(client) -> None:
    response = client.get("/bible/versions")

    assert response.status_code == 200
    versions = response.json()
    assert len(versions) >= 1
    assert versions[0]["version_id"] == "esv"


def test_returns_verse_text_when_bible_verse_is_requested(client) -> None:
    response = client.get(
        "/bible/verse",
        params={
            "book": "John",
            "chapter": 3,
            "start_verse": 16,
            "end_verse": 16,
            "version_id": "esv",
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["reference"] == "John 3:16"
    # Without a Bible Brain key, local chapter cache (BSB) or placeholder is used.
    assert payload["text"]
    assert "For God so loved" in payload["text"] or "John 3:16" in payload["text"]


def test_returns_verse_timings_on_audio_endpoint_when_client_provides_them(
    client, monkeypatch
) -> None:
    class _FakeBible:
        def get_chapter_audio_with_verse_timings(self, **kwargs):
            assert kwargs["start_verse"] == 16
            assert kwargs["end_verse"] == 17
            return {
                "audio_url": "https://cdn.example.com/jhn-3.mp3",
                "fileset_id": "ENGESVN2DA",
                "verses": [
                    {"verse": 16, "start_ms": 45200, "end_ms": 52100},
                    {"verse": 17, "start_ms": 52100, "end_ms": 59800},
                ],
            }

    monkeypatch.setattr(
        "src.routes.reels.get_bible_client",
        lambda: _FakeBible(),
    )

    response = client.get(
        "/bible/audio",
        params={
            "book": "John",
            "chapter": 3,
            "start_verse": 16,
            "end_verse": 17,
            "version_id": "esv",
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["reference"] == "John 3:16-17"
    assert payload["audio_url"] == "https://cdn.example.com/jhn-3.mp3"
    assert payload["start_verse"] == 16
    assert payload["end_verse"] == 17
    assert payload["verses"] == [
        {"verse": 16, "start_ms": 45200, "end_ms": 52100},
        {"verse": 17, "start_ms": 52100, "end_ms": 59800},
    ]


def test_clears_audio_url_on_audio_endpoint_when_timings_are_empty(
    client, monkeypatch
) -> None:
    class _FakeBible:
        def get_chapter_audio_with_verse_timings(self, **kwargs):
            return {
                "audio_url": "https://cdn.example.com/jhn-3.mp3",
                "fileset_id": "ENGESVN2DA",
                "verses": [],
            }

    monkeypatch.setattr(
        "src.routes.reels.get_bible_client",
        lambda: _FakeBible(),
    )

    response = client.get(
        "/bible/audio",
        params={
            "book": "John",
            "chapter": 3,
            "start_verse": 16,
            "end_verse": 16,
            "version_id": "esv",
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["audio_url"] == ""
    assert payload["verses"] == []


def test_returns_feed_and_comments_when_social_flow_is_exercised(
    seeded_client, verified_auth_headers
) -> None:
    feed = seeded_client.get("/reels?limit=1")
    assert feed.status_code == 200
    reel_id = feed.json()["items"][0]["id"]

    comment = seeded_client.post(
        f"/reels/{reel_id}/comments",
        headers=verified_auth_headers,
        json={"body": "Loop integration test"},
    )
    assert comment.status_code == 201

    listed = seeded_client.get(f"/reels/{reel_id}/comments")
    assert listed.status_code == 200
    assert listed.json()[0]["body"] == "Loop integration test"
