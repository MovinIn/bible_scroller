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
