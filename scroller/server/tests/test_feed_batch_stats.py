from src.models import Reel


def test_returns_batched_like_and_comment_counts_for_feed_page(
    client, db_session, verified_auth_headers, sample_reel
) -> None:
    second = Reel(
        reference="John 1:2",
        book="John",
        chapter=1,
        start_verse=2,
        end_verse=2,
        slug="John_1_2-2",
        image_url="https://example.com/john_2.png",
        iq_book_id="43",
    )
    db_session.add(second)
    db_session.commit()
    db_session.refresh(second)

    client.post(f"/reels/{sample_reel.id}/like", headers=verified_auth_headers)
    client.post(
        f"/reels/{sample_reel.id}/comments",
        headers=verified_auth_headers,
        json={"body": "Amen"},
    )

    response = client.get("/reels?limit=5", headers=verified_auth_headers)

    assert response.status_code == 200
    by_id = {item["id"]: item for item in response.json()["items"]}
    assert by_id[sample_reel.id]["like_count"] == 1
    assert by_id[sample_reel.id]["comment_count"] == 1
    assert by_id[sample_reel.id]["liked_by_me"] is True
    assert by_id[second.id]["like_count"] == 0
    assert by_id[second.id]["comment_count"] == 0
    assert by_id[second.id]["liked_by_me"] is False
