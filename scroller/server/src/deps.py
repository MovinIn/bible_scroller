from __future__ import annotations

from fastapi import Depends, Header, HTTPException
from jwt import InvalidTokenError
from sqlalchemy.orm import Session

from src.database import get_db
from src.models import User
from src.services.auth import decode_access_token


def _user_from_authorization(db: Session, authorization: str | None) -> User | None:
    if not authorization:
        return None
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        return None
    try:
        user_id = decode_access_token(token.strip())
    except InvalidTokenError:
        return None
    return db.get(User, user_id)


def get_optional_user(
    db: Session = Depends(get_db),
    authorization: str | None = Header(default=None),
) -> User | None:
    return _user_from_authorization(db, authorization)


def require_user(
    db: Session = Depends(get_db),
    authorization: str | None = Header(default=None),
) -> User:
    if not authorization:
        raise HTTPException(status_code=401, detail="Authorization required")

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise HTTPException(status_code=401, detail="Authorization required")

    try:
        user_id = decode_access_token(token.strip())
    except InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid or expired token") from None

    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    if not user.email_verified:
        raise HTTPException(status_code=403, detail="email_not_verified")
    return user
