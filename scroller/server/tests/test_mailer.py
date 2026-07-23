from __future__ import annotations

from typing import Any

import pytest

from src.services import mailer as mailer_module
from src.services.mailer import ResendMailer, build_mailer


class _FakeResponse:
    def __init__(self, status_code: int = 200, text: str = "ok") -> None:
        self.status_code = status_code
        self.text = text

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise RuntimeError(f"HTTP {self.status_code}: {self.text}")


class _FakeHttpClient:
    def __init__(self) -> None:
        self.calls: list[dict[str, Any]] = []

    def post(self, url: str, *, headers: dict[str, str], json: dict[str, Any], timeout: float) -> _FakeResponse:
        self.calls.append({"url": url, "headers": headers, "json": json, "timeout": timeout})
        return _FakeResponse()


def test_build_mailer_returns_resend_mailer_when_api_key_is_set(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(mailer_module.settings, "resend_api_key", "re_test_key")
    monkeypatch.setattr(mailer_module.settings, "resend_from", "Bible Scroller <noreply@bscroller.navedu.uk>")
    monkeypatch.setattr(mailer_module.settings, "smtp_host", "")

    built = build_mailer()

    assert isinstance(built, ResendMailer)


def test_resend_mailer_posts_verification_email_to_resend_api() -> None:
    http = _FakeHttpClient()
    mailer = ResendMailer(
        api_key="re_test_key",
        from_addr="Bible Scroller <noreply@bscroller.navedu.uk>",
        http_client=http,
    )

    mailer.send_verification_code("reader@example.com", "123456")

    assert len(http.calls) == 1
    call = http.calls[0]
    assert call["url"] == "https://api.resend.com/emails"
    assert call["headers"]["Authorization"] == "Bearer re_test_key"
    assert call["json"]["from"] == "Bible Scroller <noreply@bscroller.navedu.uk>"
    assert call["json"]["to"] == ["reader@example.com"]
    assert call["json"]["subject"] == "Your Bible Scroller verification code"
    assert "123456" in call["json"]["text"]


def test_build_mailer_prefers_resend_over_smtp_when_both_configured(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(mailer_module.settings, "resend_api_key", "re_test_key")
    monkeypatch.setattr(mailer_module.settings, "resend_from", "noreply@bscroller.navedu.uk")
    monkeypatch.setattr(mailer_module.settings, "smtp_host", "smtp.example.com")

    built = build_mailer()

    assert isinstance(built, ResendMailer)
