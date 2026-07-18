from __future__ import annotations

import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from src.config import settings
from src.models import User
from src.services.mailer import get_mailer

VERIFICATION_CODE_TTL = timedelta(minutes=15)
DUMMY_PASSWORD_HASH = bcrypt.hashpw(b"dummy-password-check", bcrypt.gensalt()).decode("utf-8")


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))


def hash_verification_code(code: str) -> str:
    return hashlib.sha256(code.encode("utf-8")).hexdigest()


def generate_verification_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def create_access_token(user_id: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.jwt_expire_minutes)
    payload = {"sub": user_id, "exp": expire}
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def decode_access_token(token: str) -> str:
    payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
    sub = payload.get("sub")
    if not sub or not isinstance(sub, str):
        raise jwt.InvalidTokenError("missing subject")
    return sub


def verify_google_id_token(id_token_value: str) -> dict:
    audiences = settings.google_client_id_list
    if not audiences:
        raise ValueError("Google client IDs are not configured")
    request = google_requests.Request()
    last_error: Exception | None = None
    for audience in audiences:
        try:
            return google_id_token.verify_oauth2_token(id_token_value, request, audience)
        except Exception as exc:  # noqa: BLE001 - google lib raises varied errors
            last_error = exc
    raise ValueError(str(last_error) if last_error else "invalid Google token")


def _normalize_email(email: str) -> str:
    return email.strip().lower()


def _default_display_name(email: str, display_name: str | None) -> str:
    if display_name and display_name.strip():
        return display_name.strip()[:64]
    local = email.split("@", 1)[0]
    return (local or "Reader")[:64]


def _find_linkable_device_user(db: Session, device_id: str | None) -> User | None:
    if not device_id or not device_id.strip():
        return None
    user = db.query(User).filter(User.device_id == device_id.strip()).one_or_none()
    if user is None:
        return None
    if user.email or user.google_sub:
        return None
    return user


def _safe_device_id(db: Session, device_id: str | None) -> str | None:
    """Return device_id only if unused or linkable; never collide with a claimed account."""
    if not device_id or not device_id.strip():
        return None
    cleaned = device_id.strip()
    existing = db.query(User).filter(User.device_id == cleaned).one_or_none()
    if existing is None:
        return cleaned
    if existing.email or existing.google_sub:
        return None
    return cleaned


def issue_verification_code(db: Session, user: User) -> str:
    code = generate_verification_code()
    user.email_verification_code_hash = hash_verification_code(code)
    user.email_verification_expires_at = datetime.now(timezone.utc) + VERIFICATION_CODE_TTL
    db.commit()
    if user.email:
        get_mailer().send_verification_code(user.email, code)
    return code


def register_user(
    db: Session,
    *,
    email: str,
    password: str,
    display_name: str | None = None,
    device_id: str | None = None,
) -> User | None:
    """Register or re-claim an unverified email.

    Returns the user when a verification email was issued.
    Returns None when the email is already verified (anti-enumeration: caller
    should still respond with verification_required).
    """
    normalized = _normalize_email(email)
    existing = db.query(User).filter(User.email == normalized).one_or_none()

    if existing is not None and existing.email_verified:
        return None

    if existing is not None and not existing.email_verified:
        # Inbox owner wins: overwrite squat credentials and resend code.
        existing.password_hash = hash_password(password)
        existing.display_name = _default_display_name(normalized, display_name)
        existing.email_verified = False
        db.commit()
        issue_verification_code(db, existing)
        db.refresh(existing)
        return existing

    user = _find_linkable_device_user(db, device_id)
    if user is None:
        user = User(device_id=_safe_device_id(db, device_id))
        db.add(user)

    user.email = normalized
    user.password_hash = hash_password(password)
    user.display_name = _default_display_name(normalized, display_name)
    user.email_verified = False
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ValueError("registration_conflict") from exc
    db.refresh(user)
    issue_verification_code(db, user)
    db.refresh(user)
    return user


def authenticate_email_password(db: Session, *, email: str, password: str) -> User:
    normalized = _normalize_email(email)
    user = db.query(User).filter(User.email == normalized).one_or_none()
    if user is None or not user.password_hash:
        verify_password(password, DUMMY_PASSWORD_HASH)
        raise ValueError("invalid_credentials")
    if not verify_password(password, user.password_hash):
        raise ValueError("invalid_credentials")
    if not user.email_verified:
        raise ValueError("email_not_verified")
    return user


def verify_email_code(db: Session, *, email: str, code: str) -> User:
    if not code or not code.isdigit() or len(code) != 6:
        raise ValueError("invalid_code")

    normalized = _normalize_email(email)
    user = db.query(User).filter(User.email == normalized).one_or_none()
    if user is None or not user.email_verification_code_hash:
        raise ValueError("invalid_code")

    expires = user.email_verification_expires_at
    if expires is not None and expires.tzinfo is None:
        expires = expires.replace(tzinfo=timezone.utc)
    if expires is None or expires < datetime.now(timezone.utc):
        raise ValueError("invalid_code")

    expected = user.email_verification_code_hash
    actual = hash_verification_code(code)
    if not hmac.compare_digest(expected, actual):
        raise ValueError("invalid_code")

    user.email_verified = True
    user.email_verification_code_hash = None
    user.email_verification_expires_at = None
    db.commit()
    db.refresh(user)
    return user


def resend_verification(db: Session, *, email: str) -> None:
    normalized = _normalize_email(email)
    user = db.query(User).filter(User.email == normalized).one_or_none()
    if user is None or user.email_verified:
        return
    issue_verification_code(db, user)


def upsert_google_user(
    db: Session,
    *,
    google_claims: dict,
    device_id: str | None = None,
) -> User:
    sub = google_claims.get("sub")
    email = google_claims.get("email")
    if not sub:
        raise ValueError("invalid_google_claims")
    if email and google_claims.get("email_verified") is not True:
        raise ValueError("google_email_not_verified")

    user = db.query(User).filter(User.google_sub == sub).one_or_none()
    if user is None and email:
        by_email = db.query(User).filter(User.email == _normalize_email(email)).one_or_none()
        if by_email is not None:
            if by_email.google_sub and by_email.google_sub != sub:
                raise ValueError("email_linked_to_other_google")
            if not by_email.email_verified:
                # Unverified squat: inbox/Google owner takes over; wipe attacker password.
                by_email.password_hash = None
            user = by_email

    if user is None:
        user = _find_linkable_device_user(db, device_id)
    if user is None:
        user = User(
            device_id=_safe_device_id(db, device_id),
            display_name=_default_display_name(email or "reader", None),
        )
        db.add(user)

    user.google_sub = sub
    if email:
        user.email = _normalize_email(email)
    user.email_verified = True
    user.email_verification_code_hash = None
    user.email_verification_expires_at = None
    name = google_claims.get("name")
    if name:
        user.display_name = str(name)[:64]
    elif not user.display_name:
        user.display_name = _default_display_name(user.email or "reader", None)
    picture = google_claims.get("picture")
    if picture:
        user.avatar_url = str(picture)
    if device_id and device_id.strip() and user.device_id is None:
        user.device_id = _safe_device_id(db, device_id)

    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ValueError("google_link_conflict") from exc
    db.refresh(user)
    return user


def token_response(user: User) -> dict:
    return {
        "access_token": create_access_token(user.id),
        "token_type": "bearer",
        "user": {
            "id": user.id,
            "display_name": user.display_name,
            "email": user.email,
            "email_verified": user.email_verified,
            "avatar_url": user.avatar_url,
        },
    }
