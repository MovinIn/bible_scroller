from src.models import Reel, User
from src.services import auth as auth_service


def _add_reel(db_session, *, book: str, chapter: int, verse: int, iq_book_id: str) -> Reel:
    reel = Reel(
        reference=f"{book} {chapter}:{verse}",
        book=book,
        chapter=chapter,
        start_verse=verse,
        end_verse=verse,
        slug=f"{book}_{chapter}_{verse}-{verse}",
        image_url=f"https://example.com/{book}_{chapter}_{verse}.png",
        iq_book_id=iq_book_id,
    )
    db_session.add(reel)
    db_session.commit()
    db_session.refresh(reel)
    return reel


def test_starts_feed_at_first_reel_of_book_when_book_query_is_set(client, db_session) -> None:
    _add_reel(db_session, book="Genesis", chapter=1, verse=1, iq_book_id="01")
    john_first = _add_reel(db_session, book="John", chapter=1, verse=1, iq_book_id="43")
    _add_reel(db_session, book="John", chapter=3, verse=16, iq_book_id="43")
    _add_reel(db_session, book="Acts", chapter=1, verse=1, iq_book_id="44")

    response = client.get("/reels?limit=10&book=John")

    assert response.status_code == 200
    payload = response.json()
    assert payload["items"][0]["id"] == john_first.id
    assert payload["items"][0]["book"] == "John"
    assert [item["book"] for item in payload["items"]] == ["John", "John", "Acts"]


def test_returns_empty_items_when_book_has_no_reels(client, db_session) -> None:
    _add_reel(db_session, book="John", chapter=1, verse=1, iq_book_id="43")

    response = client.get("/reels?limit=10&book=Romans")

    assert response.status_code == 200
    assert response.json() == {"items": [], "next_cursor": None, "prev_cursor": None}


def test_returns_books_with_reels_in_biblical_order_when_books_listed(client, db_session) -> None:
    _add_reel(db_session, book="John", chapter=1, verse=1, iq_book_id="43")
    _add_reel(db_session, book="Genesis", chapter=1, verse=1, iq_book_id="01")
    _add_reel(db_session, book="Acts", chapter=1, verse=1, iq_book_id="44")
    _add_reel(db_session, book="John", chapter=3, verse=16, iq_book_id="43")

    response = client.get("/reels/books")

    assert response.status_code == 200
    assert response.json() == ["Genesis", "John", "Acts"]


def test_starts_feed_at_from_id_when_resume_query_is_set(seeded_client) -> None:
    all_items = seeded_client.get("/reels?limit=5").json()["items"]
    assert len(all_items) >= 3
    resume_id = all_items[2]["id"]

    response = seeded_client.get(f"/reels?limit=5&from_id={resume_id}")

    assert response.status_code == 200
    payload = response.json()
    assert payload["items"][0]["id"] == resume_id
    assert all(item["id"] >= resume_id for item in payload["items"])


def test_returns_first_reel_when_from_id_is_below_existing_ids(seeded_client) -> None:
    first_id = seeded_client.get("/reels?limit=1").json()["items"][0]["id"]

    response = seeded_client.get("/reels?limit=2&from_id=1")

    assert response.status_code == 200
    assert response.json()["items"][0]["id"] == first_id


def test_returns_feed_when_no_auth_header(seeded_client) -> None:
    response = seeded_client.get("/reels?limit=2")

    assert response.status_code == 200
    payload = response.json()
    assert len(payload["items"]) == 2
    assert payload["items"][0]["liked_by_me"] is False


def test_returns_comments_when_no_auth_header(sample_reel, client, verified_auth_headers) -> None:
    client.post(
        f"/reels/{sample_reel.id}/comments",
        headers=verified_auth_headers,
        json={"body": "Public comment"},
    )

    response = client.get(f"/reels/{sample_reel.id}/comments")

    assert response.status_code == 200
    assert response.json()[0]["body"] == "Public comment"
    assert response.json()[0]["liked_by_me"] is False


def test_returns_401_when_like_without_auth(sample_reel, client) -> None:
    response = client.post(f"/reels/{sample_reel.id}/like")

    assert response.status_code == 401


def test_returns_401_when_comment_without_auth(sample_reel, client) -> None:
    response = client.post(
        f"/reels/{sample_reel.id}/comments",
        json={"body": "Nope"},
    )

    assert response.status_code == 401


def test_returns_403_when_like_with_unverified_user_jwt(sample_reel, client, db_session) -> None:
    user = User(
        email="unverified-jwt@example.com",
        password_hash=auth_service.hash_password("password123"),
        display_name="Unverified",
        email_verified=False,
    )
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)
    token = auth_service.create_access_token(user.id)

    response = client.post(
        f"/reels/{sample_reel.id}/like",
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 403


def test_creates_comment_when_verified_user_posts(sample_reel, client, verified_auth_headers) -> None:
    response = client.post(
        f"/reels/{sample_reel.id}/comments",
        headers=verified_auth_headers,
        json={"body": "Amen!"},
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["body"] == "Amen!"
    assert payload["like_count"] == 0
    assert payload["author"]["display_name"] == "Verified"


def test_returns_reply_when_parent_id_is_posted(sample_reel, client, verified_auth_headers) -> None:
    parent = client.post(
        f"/reels/{sample_reel.id}/comments",
        headers=verified_auth_headers,
        json={"body": "Root comment"},
    ).json()

    response = client.post(
        f"/reels/{sample_reel.id}/comments",
        headers=verified_auth_headers,
        json={"body": "Reply comment", "parent_id": parent["id"]},
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["body"] == "Reply comment"
    assert payload["parent_id"] == parent["id"]


def test_returns_400_when_parent_belongs_to_different_reel(
    sample_reel, client, verified_auth_headers, db_session
) -> None:
    other = Reel(
        reference="John 1:1",
        book="John",
        chapter=1,
        start_verse=1,
        end_verse=1,
        slug="John_1_1-other",
        image_url="https://example.com/john.png",
        iq_book_id="43",
    )
    db_session.add(other)
    db_session.commit()
    db_session.refresh(other)

    foreign_parent = client.post(
        f"/reels/{other.id}/comments",
        headers=verified_auth_headers,
        json={"body": "On another reel"},
    ).json()

    response = client.post(
        f"/reels/{sample_reel.id}/comments",
        headers=verified_auth_headers,
        json={"body": "Bad reply", "parent_id": foreign_parent["id"]},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "Invalid parent comment for this reel"


def test_returns_reels_in_manifest_order_when_feed_is_seeded(seeded_client) -> None:
    response = seeded_client.get("/reels?limit=5")

    assert response.status_code == 200
    ids = [item["id"] for item in response.json()["items"]]
    assert ids == sorted(ids)


def test_returns_paginated_reels_when_feed_is_requested(seeded_client) -> None:
    response = seeded_client.get("/reels?limit=2")

    assert response.status_code == 200
    payload = response.json()
    assert len(payload["items"]) == 2
    assert payload["items"][0]["reference"].startswith(payload["items"][0]["book"])
    assert payload["items"][0]["like_count"] == 0
    assert payload["items"][0]["liked_by_me"] is False
    assert payload["next_cursor"] == payload["items"][1]["id"]


def test_increments_like_count_when_reel_is_liked(sample_reel, client, verified_auth_headers) -> None:
    response = client.post(f"/reels/{sample_reel.id}/like", headers=verified_auth_headers)

    assert response.status_code == 200
    assert response.json() == {"liked": True, "like_count": 1}

    feed = client.get("/reels", headers=verified_auth_headers).json()
    reel = next(item for item in feed["items"] if item["id"] == sample_reel.id)
    assert reel["liked_by_me"] is True
    assert reel["like_count"] == 1


def test_decrements_like_count_when_reel_is_unliked(sample_reel, client, verified_auth_headers) -> None:
    client.post(f"/reels/{sample_reel.id}/like", headers=verified_auth_headers)

    response = client.delete(f"/reels/{sample_reel.id}/like", headers=verified_auth_headers)

    assert response.status_code == 200
    assert response.json() == {"liked": False, "like_count": 0}


def test_increments_like_count_when_comment_is_liked(
    sample_reel, client, verified_auth_headers
) -> None:
    comment = client.post(
        f"/reels/{sample_reel.id}/comments",
        headers=verified_auth_headers,
        json={"body": "Beautiful verse"},
    ).json()

    response = client.post(f"/comments/{comment['id']}/like", headers=verified_auth_headers)

    assert response.status_code == 200
    assert response.json() == {"liked": True, "like_count": 1}


def test_returns_prev_cursor_when_earlier_reels_exist(client, db_session) -> None:
    _add_reel(db_session, book="Genesis", chapter=50, verse=26, iq_book_id="01")
    exodus_first = _add_reel(db_session, book="Exodus", chapter=1, verse=1, iq_book_id="02")

    response = client.get(f"/reels?limit=1&book=Exodus")

    assert response.status_code == 200
    payload = response.json()
    assert payload["items"][0]["id"] == exodus_first.id
    assert payload["prev_cursor"] == exodus_first.id


def test_returns_null_prev_cursor_when_feed_starts_at_first_reel(client, db_session) -> None:
    first = _add_reel(db_session, book="Genesis", chapter=1, verse=1, iq_book_id="01")
    _add_reel(db_session, book="Genesis", chapter=1, verse=2, iq_book_id="01")

    response = client.get("/reels?limit=1")

    assert response.status_code == 200
    payload = response.json()
    assert payload["items"][0]["id"] == first.id
    assert payload["prev_cursor"] is None


def test_returns_earlier_reels_when_before_id_is_set(client, db_session) -> None:
    genesis_last = _add_reel(db_session, book="Genesis", chapter=50, verse=26, iq_book_id="01")
    exodus_first = _add_reel(db_session, book="Exodus", chapter=1, verse=1, iq_book_id="02")
    _add_reel(db_session, book="Exodus", chapter=1, verse=2, iq_book_id="02")

    response = client.get(f"/reels?limit=10&before_id={exodus_first.id}")

    assert response.status_code == 200
    payload = response.json()
    assert payload["items"][-1]["id"] == genesis_last.id
    assert payload["items"][-1]["book"] == "Genesis"
    assert payload["next_cursor"] == genesis_last.id
