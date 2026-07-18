from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from src.models import ReelLike, User


def test_returns_verification_required_without_token_when_user_registers(client, capture_mailer) -> None:
    response = client.post(
        "/auth/register",
        json={"email": "reader@example.com", "password": "password123"},
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["status"] == "verification_required"
    assert payload["email"] == "reader@example.com"
    assert "access_token" not in payload


def test_emails_six_digit_code_when_user_registers(client, capture_mailer) -> None:
    client.post(
        "/auth/register",
        json={"email": "codes@example.com", "password": "password123"},
    )

    code = capture_mailer.last_code_for("codes@example.com")
    assert code is not None
    assert re.fullmatch(r"\d{6}", code)


def test_returns_verification_required_when_verified_email_reregisters(
    client, capture_mailer
) -> None:
    email = "dup@example.com"
    client.post("/auth/register", json={"email": email, "password": "password123"})
    code = capture_mailer.last_code_for(email)
    client.post("/auth/verify-email", json={"email": email, "code": code})
    before_count = len(capture_mailer.sent)

    response = client.post(
        "/auth/register",
        json={"email": email, "password": "different-password"},
    )

    assert response.status_code == 201
    assert response.json()["status"] == "verification_required"
    assert len(capture_mailer.sent) == before_count
    login = client.post("/auth/login", json={"email": email, "password": "password123"})
    assert login.status_code == 200


def test_overwrites_unverified_squat_when_email_reregisters(client, capture_mailer) -> None:
    email = "squat@example.com"
    client.post("/auth/register", json={"email": email, "password": "attacker-pass"})
    attacker_code = capture_mailer.last_code_for(email)

    response = client.post(
        "/auth/register",
        json={"email": email, "password": "owner-password"},
    )
    assert response.status_code == 201
    owner_code = capture_mailer.last_code_for(email)
    assert owner_code != attacker_code

    assert client.post("/auth/verify-email", json={"email": email, "code": attacker_code}).status_code == 400
    ok = client.post("/auth/verify-email", json={"email": email, "code": owner_code})
    assert ok.status_code == 200
    assert client.post("/auth/login", json={"email": email, "password": "owner-password"}).status_code == 200
    assert client.post("/auth/login", json={"email": email, "password": "attacker-pass"}).status_code == 401


def test_rejects_login_with_email_not_verified_when_unverified(client, capture_mailer) -> None:
    client.post(
        "/auth/register",
        json={"email": "pending@example.com", "password": "password123"},
    )

    response = client.post(
        "/auth/login",
        json={"email": "pending@example.com", "password": "password123"},
    )

    assert response.status_code == 403
    assert response.json()["detail"] == "email_not_verified"


def test_returns_access_token_when_login_after_email_verified(client, capture_mailer) -> None:
    email = "ready@example.com"
    password = "password123"
    client.post("/auth/register", json={"email": email, "password": password})
    code = capture_mailer.last_code_for(email)
    client.post("/auth/verify-email", json={"email": email, "code": code})

    response = client.post("/auth/login", json={"email": email, "password": password})

    assert response.status_code == 200
    payload = response.json()
    assert payload["access_token"]
    assert payload["token_type"] == "bearer"
    assert payload["user"]["email"] == email


def test_returns_access_token_when_six_digit_code_is_valid(client, capture_mailer, sample_reel) -> None:
    email = "verify@example.com"
    client.post("/auth/register", json={"email": email, "password": "password123"})
    code = capture_mailer.last_code_for(email)

    response = client.post("/auth/verify-email", json={"email": email, "code": code})

    assert response.status_code == 200
    payload = response.json()
    assert payload["access_token"]
    headers = {"Authorization": f"Bearer {payload['access_token']}"}

    like = client.post(f"/reels/{sample_reel.id}/like", headers=headers)
    assert like.status_code == 200
    assert like.json() == {"liked": True, "like_count": 1}


def test_returns_400_when_verification_code_is_wrong(client, capture_mailer) -> None:
    email = "wrong@example.com"
    client.post("/auth/register", json={"email": email, "password": "password123"})

    response = client.post("/auth/verify-email", json={"email": email, "code": "000000"})

    assert response.status_code == 400


def test_returns_400_when_verification_code_is_not_six_digits(client, capture_mailer) -> None:
    email = "short@example.com"
    client.post("/auth/register", json={"email": email, "password": "password123"})

    response = client.post("/auth/verify-email", json={"email": email, "code": "12345"})

    assert response.status_code == 400


def test_returns_400_when_verification_code_is_expired(client, capture_mailer, db_session) -> None:
    email = "expired@example.com"
    client.post("/auth/register", json={"email": email, "password": "password123"})
    code = capture_mailer.last_code_for(email)

    user = db_session.query(User).filter(User.email == email).one()
    user.email_verification_expires_at = datetime.now(timezone.utc) - timedelta(minutes=1)
    db_session.commit()

    response = client.post("/auth/verify-email", json={"email": email, "code": code})

    assert response.status_code == 400


def test_invalidates_old_code_when_verification_is_resent(client, capture_mailer) -> None:
    email = "resend@example.com"
    client.post("/auth/register", json={"email": email, "password": "password123"})
    old_code = capture_mailer.last_code_for(email)

    resend = client.post("/auth/resend-verification", json={"email": email})
    assert resend.status_code == 200

    new_code = capture_mailer.last_code_for(email)
    assert new_code is not None
    assert re.fullmatch(r"\d{6}", new_code)
    assert new_code != old_code

    assert client.post("/auth/verify-email", json={"email": email, "code": old_code}).status_code == 400

    ok = client.post("/auth/verify-email", json={"email": email, "code": new_code})
    assert ok.status_code == 200
    assert ok.json()["access_token"]


def test_returns_access_token_when_google_id_token_is_valid(client) -> None:
    with patch(
        "src.services.auth.verify_google_id_token",
        return_value={
            "sub": "google-sub-123",
            "email": "google.user@example.com",
            "email_verified": True,
            "name": "Google User",
            "picture": "https://example.com/a.png",
        },
    ):
        response = client.post("/auth/google", json={"id_token": "fake-google-token"})

    assert response.status_code == 200
    payload = response.json()
    assert payload["access_token"]
    assert payload["user"]["email"] == "google.user@example.com"
    assert payload["user"]["email_verified"] is True


def test_rejects_google_sign_in_when_id_token_is_invalid(client) -> None:
    with patch(
        "src.services.auth.verify_google_id_token",
        side_effect=ValueError("invalid token"),
    ):
        response = client.post("/auth/google", json={"id_token": "bad-token"})

    assert response.status_code == 401


def test_rejects_google_sign_in_when_email_not_verified_claim(client) -> None:
    with patch(
        "src.services.auth.verify_google_id_token",
        return_value={
            "sub": "google-sub-unverified",
            "email": "unverified.google@example.com",
            "email_verified": False,
        },
    ):
        response = client.post("/auth/google", json={"id_token": "fake-google-token"})

    assert response.status_code == 401


def test_clears_attacker_password_when_google_takes_over_unverified_squat(
    client, capture_mailer, db_session
) -> None:
    email = "victim@example.com"
    client.post("/auth/register", json={"email": email, "password": "attacker-pass"})

    with patch(
        "src.services.auth.verify_google_id_token",
        return_value={
            "sub": "google-victim-sub",
            "email": email,
            "email_verified": True,
            "name": "Victim",
        },
    ):
        response = client.post("/auth/google", json={"id_token": "fake-google-token"})

    assert response.status_code == 200
    assert client.post("/auth/login", json={"email": email, "password": "attacker-pass"}).status_code == 401
    user = db_session.query(User).filter(User.email == email).one()
    assert user.password_hash is None
    assert user.google_sub == "google-victim-sub"


def test_keeps_password_when_google_links_verified_email_account(client, capture_mailer) -> None:
    email = "both@example.com"
    client.post("/auth/register", json={"email": email, "password": "password123"})
    code = capture_mailer.last_code_for(email)
    client.post("/auth/verify-email", json={"email": email, "code": code})

    with patch(
        "src.services.auth.verify_google_id_token",
        return_value={
            "sub": "google-both-sub",
            "email": email,
            "email_verified": True,
            "name": "Both Methods",
        },
    ):
        assert client.post("/auth/google", json={"id_token": "fake"}).status_code == 200

    assert client.post("/auth/login", json={"email": email, "password": "password123"}).status_code == 200


def test_returns_429_when_verify_rate_limit_exceeded(client, capture_mailer) -> None:
    email = "ratelimit@example.com"
    client.post("/auth/register", json={"email": email, "password": "password123"})
    for _ in range(10):
        client.post("/auth/verify-email", json={"email": email, "code": "000000"})

    response = client.post("/auth/verify-email", json={"email": email, "code": "000000"})
    assert response.status_code == 429


def test_avoids_device_id_collision_when_second_account_registers(
    client, capture_mailer, db_session
) -> None:
    device_id = "shared-device"
    client.post(
        "/auth/register",
        headers={"X-Device-Id": device_id},
        json={"email": "first@example.com", "password": "password123"},
    )
    code = capture_mailer.last_code_for("first@example.com")
    client.post("/auth/verify-email", json={"email": "first@example.com", "code": code})

    response = client.post(
        "/auth/register",
        headers={"X-Device-Id": device_id},
        json={"email": "second@example.com", "password": "password123"},
    )
    assert response.status_code == 201
    second = db_session.query(User).filter(User.email == "second@example.com").one()
    assert second.device_id is None



def test_preserves_likes_when_anonymous_device_is_linked_on_login(
    client, capture_mailer, sample_reel, db_session
) -> None:
    device_id = "link-device-001"
    anon = User(device_id=device_id, display_name="Reader-0001", email_verified=False)
    db_session.add(anon)
    db_session.commit()
    db_session.refresh(anon)
    db_session.add(ReelLike(user_id=anon.id, reel_id=sample_reel.id))
    db_session.commit()

    email = "linked@example.com"
    client.post(
        "/auth/register",
        headers={"X-Device-Id": device_id},
        json={"email": email, "password": "password123", "display_name": "Linked"},
    )
    code = capture_mailer.last_code_for(email)
    verify = client.post("/auth/verify-email", json={"email": email, "code": code})
    token = verify.json()["access_token"]

    feed = client.get("/reels", headers={"Authorization": f"Bearer {token}"}).json()
    reel = next(item for item in feed["items"] if item["id"] == sample_reel.id)
    assert reel["liked_by_me"] is True
    assert reel["like_count"] == 1
