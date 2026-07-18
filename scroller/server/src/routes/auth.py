from __future__ import annotations

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy.orm import Session

from src.config import settings
from src.database import get_db
from src.services import auth as auth_service
from src.services.rate_limit import auth_rate_limiter

router = APIRouter(prefix="/auth", tags=["auth"])


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    display_name: str | None = Field(default=None, min_length=2, max_length=64)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class VerifyEmailRequest(BaseModel):
    email: EmailStr
    code: str


class ResendVerificationRequest(BaseModel):
    email: EmailStr


class GoogleAuthRequest(BaseModel):
    id_token: str = Field(min_length=1)


def _client_key(request: Request, email: str | None = None) -> str:
    host = request.client.host if request.client else "unknown"
    if email:
        return f"{host}:{email.strip().lower()}"
    return host


def _enforce_rate_limit(key: str, *, limit: int) -> None:
    allowed = auth_rate_limiter.hit(
        key,
        limit=limit,
        window_seconds=float(settings.auth_rate_window_seconds),
    )
    if not allowed:
        raise HTTPException(status_code=429, detail="Too many attempts. Try again later.")


@router.post("/register", status_code=201)
def register(
    payload: RegisterRequest,
    request: Request,
    db: Session = Depends(get_db),
    x_device_id: str | None = Header(default=None, alias="X-Device-Id"),
) -> dict:
    email = str(payload.email)
    _enforce_rate_limit(
        f"register:{_client_key(request, email)}",
        limit=settings.auth_register_limit,
    )
    try:
        auth_service.register_user(
            db,
            email=email,
            password=payload.password,
            display_name=payload.display_name,
            device_id=x_device_id,
        )
    except ValueError as exc:
        if str(exc) == "registration_conflict":
            raise HTTPException(status_code=409, detail="Could not complete registration") from None
        raise
    # Always same shape (anti-enumeration for already-verified emails).
    return {"status": "verification_required", "email": email.strip().lower()}


@router.post("/login")
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> dict:
    try:
        user = auth_service.authenticate_email_password(
            db, email=str(payload.email), password=payload.password
        )
    except ValueError as exc:
        if str(exc) == "email_not_verified":
            raise HTTPException(status_code=403, detail="email_not_verified") from None
        raise HTTPException(status_code=401, detail="Invalid email or password") from None
    return auth_service.token_response(user)


@router.post("/verify-email")
def verify_email(
    payload: VerifyEmailRequest,
    request: Request,
    db: Session = Depends(get_db),
) -> dict:
    email = str(payload.email)
    _enforce_rate_limit(
        f"verify:{_client_key(request, email)}",
        limit=settings.auth_verify_limit,
    )
    try:
        user = auth_service.verify_email_code(db, email=email, code=payload.code.strip())
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid or expired verification code") from None
    return auth_service.token_response(user)


@router.post("/resend-verification")
def resend_verification(
    payload: ResendVerificationRequest,
    request: Request,
    db: Session = Depends(get_db),
) -> dict:
    email = str(payload.email)
    _enforce_rate_limit(
        f"resend:{_client_key(request, email)}",
        limit=settings.auth_resend_limit,
    )
    auth_service.resend_verification(db, email=email)
    return {"status": "ok"}


@router.post("/google")
def google_auth(
    payload: GoogleAuthRequest,
    db: Session = Depends(get_db),
    x_device_id: str | None = Header(default=None, alias="X-Device-Id"),
) -> dict:
    try:
        claims = auth_service.verify_google_id_token(payload.id_token)
        user = auth_service.upsert_google_user(db, google_claims=claims, device_id=x_device_id)
    except ValueError as exc:
        detail = str(exc)
        if detail in {"google_email_not_verified", "email_linked_to_other_google", "google_link_conflict"}:
            raise HTTPException(status_code=401, detail="Invalid Google token") from None
        raise HTTPException(status_code=401, detail="Invalid Google token") from None
    return auth_service.token_response(user)
