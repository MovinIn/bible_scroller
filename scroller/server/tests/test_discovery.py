from __future__ import annotations

from src.models import Reel, ReelLike, User
from src.services.reels import POPULAR_PROBABILITY, get_discovery_feed


def _add_reel(
    db_session,
    *,
    book: str,
    chapter: int,
    verse: int,
    iq_book_id: str,
) -> Reel:
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


def _like(db_session, reel: Reel, user: User) -> None:
    db_session.add(ReelLike(reel_id=reel.id, user_id=user.id))
    db_session.commit()


def _user(db_session, email: str = "fan@example.com") -> User:
    user = User(
        email=email,
        password_hash="x",
        display_name="Fan",
        email_verified=True,
    )
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)
    return user


class _ScriptedRng:
    """Deterministic RNG for discovery sampling tests."""

    def __init__(self, floats: list[float], choice_picks: list[object] | None = None):
        self._floats = list(floats)
        self._choice_picks = list(choice_picks or [])

    def random(self) -> float:
        return self._floats.pop(0)

    def choices(self, population, weights=None, k=1):
        if self._choice_picks:
            pick = self._choice_picks.pop(0)
            return [pick]
        return [population[0]]

    def choice(self, seq):
        if self._choice_picks:
            return self._choice_picks.pop(0)
        return seq[0]


def test_returns_no_duplicate_ids_when_discovery_batch_requested(client, db_session) -> None:
    for i in range(1, 6):
        _add_reel(db_session, book="John", chapter=1, verse=i, iq_book_id="43")

    response = client.get("/reels/discovery?limit=5")

    assert response.status_code == 200
    ids = [item["id"] for item in response.json()["items"]]
    assert len(ids) == 5
    assert len(set(ids)) == 5


def test_omits_excluded_reel_ids_when_exclude_query_is_set(client, db_session) -> None:
    a = _add_reel(db_session, book="John", chapter=1, verse=1, iq_book_id="43")
    b = _add_reel(db_session, book="John", chapter=1, verse=2, iq_book_id="43")
    c = _add_reel(db_session, book="John", chapter=1, verse=3, iq_book_id="43")

    response = client.get(f"/reels/discovery?limit=10&exclude={a.id},{b.id}")

    assert response.status_code == 200
    ids = [item["id"] for item in response.json()["items"]]
    assert ids == [c.id]


def test_returns_batch_from_all_reels_when_no_likes_exist(client, db_session) -> None:
    reels = [
        _add_reel(db_session, book="John", chapter=1, verse=i, iq_book_id="43")
        for i in range(1, 4)
    ]

    response = client.get("/reels/discovery?limit=3")

    assert response.status_code == 200
    payload = response.json()
    assert sorted(item["id"] for item in payload["items"]) == sorted(r.id for r in reels)
    assert payload["prev_cursor"] is None


def test_sets_prev_cursor_null_for_discovery_feed(client, db_session) -> None:
    _add_reel(db_session, book="John", chapter=1, verse=1, iq_book_id="43")

    response = client.get("/reels/discovery?limit=1")

    assert response.status_code == 200
    assert response.json()["prev_cursor"] is None


def test_sets_next_cursor_when_more_reels_remain_outside_batch(client, db_session) -> None:
    for i in range(1, 5):
        _add_reel(db_session, book="John", chapter=1, verse=i, iq_book_id="43")

    response = client.get("/reels/discovery?limit=2")

    assert response.status_code == 200
    payload = response.json()
    assert len(payload["items"]) == 2
    assert payload["next_cursor"] is not None


def test_clears_next_cursor_when_all_remaining_reels_are_returned(client, db_session) -> None:
    for i in range(1, 3):
        _add_reel(db_session, book="John", chapter=1, verse=i, iq_book_id="43")

    response = client.get("/reels/discovery?limit=10")

    assert response.status_code == 200
    payload = response.json()
    assert len(payload["items"]) == 2
    assert payload["next_cursor"] is None


def test_selects_popular_reel_when_rng_draws_below_popular_threshold(db_session) -> None:
    popular = _add_reel(db_session, book="John", chapter=3, verse=16, iq_book_id="43")
    other = _add_reel(db_session, book="John", chapter=1, verse=1, iq_book_id="43")
    user = _user(db_session)
    _like(db_session, popular, user)

    assert POPULAR_PROBABILITY == 0.75
    rng = _ScriptedRng(floats=[0.0], choice_picks=[popular.id])

    feed = get_discovery_feed(db_session, None, limit=1, exclude_ids=[], rng=rng)

    assert [item.id for item in feed.items] == [popular.id]
    assert other.id not in {item.id for item in feed.items}


def test_selects_non_popular_reel_when_rng_draws_at_or_above_popular_threshold(
    db_session,
) -> None:
    popular = _add_reel(db_session, book="John", chapter=3, verse=16, iq_book_id="43")
    other = _add_reel(db_session, book="John", chapter=1, verse=1, iq_book_id="43")
    user = _user(db_session)
    _like(db_session, popular, user)

    rng = _ScriptedRng(floats=[0.75], choice_picks=[other.id])

    feed = get_discovery_feed(db_session, None, limit=1, exclude_ids=[], rng=rng)

    assert [item.id for item in feed.items] == [other.id]


def test_weights_popular_pick_by_like_count_when_sampling_popular_pool(db_session) -> None:
    low = _add_reel(db_session, book="John", chapter=1, verse=1, iq_book_id="43")
    high = _add_reel(db_session, book="John", chapter=3, verse=16, iq_book_id="43")
    user_a = _user(db_session, email="a@example.com")
    user_b = _user(db_session, email="b@example.com")
    user_c = _user(db_session, email="c@example.com")
    _like(db_session, low, user_a)
    _like(db_session, high, user_a)
    _like(db_session, high, user_b)
    _like(db_session, high, user_c)

    recorded: list[tuple[list[int], list[int] | None]] = []

    class _CaptureRng:
        def random(self) -> float:
            return 0.0

        def choices(self, population, weights=None, k=1):
            recorded.append((list(population), list(weights) if weights else None))
            return [high.id]

        def choice(self, seq):
            return seq[0]

    get_discovery_feed(db_session, None, limit=1, exclude_ids=[], rng=_CaptureRng())

    assert recorded == [([low.id, high.id], [1, 3])] or recorded == [
        ([high.id, low.id], [3, 1])
    ]
