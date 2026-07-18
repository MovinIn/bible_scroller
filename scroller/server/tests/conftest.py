import os
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

os.environ.setdefault("DATABASE_URL", "sqlite+pysqlite:///:memory:")
os.environ.setdefault("JWT_SECRET", "test-jwt-secret-for-pytest-32bytes!!")
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("ALLOW_CONSOLE_MAILER", "true")

from src.database import Base, get_db
from src.main import app
from src.models import Reel
from src.seed import seed_reels
from src.services.bible_brain_service import reset_bible_client_for_tests
from src.services.mailer import CaptureMailer, ConsoleMailer, set_mailer
from src.services.rate_limit import auth_rate_limiter


@pytest.fixture(autouse=True)
def _reset_rate_limiter():
    auth_rate_limiter.clear()
    yield
    auth_rate_limiter.clear()


@pytest.fixture(autouse=True)
def _reset_bible_client():
    reset_bible_client_for_tests()
    yield
    reset_bible_client_for_tests()


@pytest.fixture()
def db_session():
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    TestingSessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    Base.metadata.create_all(bind=engine)
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(bind=engine)


@pytest.fixture()
def capture_mailer():
    mailer = CaptureMailer()
    set_mailer(mailer)
    try:
        yield mailer
    finally:
        set_mailer(ConsoleMailer())


@pytest.fixture()
def client(db_session, capture_mailer):
    def override_get_db():
        try:
            yield db_session
        finally:
            pass

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture()
def seeded_client(client, db_session):
    seed_reels(db_session, limit=5)
    return client


@pytest.fixture()
def device_headers() -> dict[str, str]:
    return {"X-Device-Id": "test-device-001"}


@pytest.fixture()
def verified_auth_headers(client, capture_mailer) -> dict[str, str]:
    email = "verified@example.com"
    password = "password123"
    client.post(
        "/auth/register",
        json={"email": email, "password": password, "display_name": "Verified"},
    )
    code = capture_mailer.last_code_for(email)
    verify = client.post("/auth/verify-email", json={"email": email, "code": code})
    token = verify.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def sample_reel(db_session) -> Reel:
    reel = Reel(
        reference="John 3:16",
        book="John",
        chapter=3,
        start_verse=16,
        end_verse=16,
        slug="John_3_16-test",
        image_url="https://example.com/john.png",
        iq_book_id="43",
    )
    db_session.add(reel)
    db_session.commit()
    db_session.refresh(reel)
    return reel
