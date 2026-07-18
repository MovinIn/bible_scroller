from __future__ import annotations

import logging
import smtplib
from email.message import EmailMessage
from typing import Protocol

from src.config import settings

logger = logging.getLogger(__name__)


class Mailer(Protocol):
    def send_verification_code(self, email: str, code: str) -> None: ...


class ConsoleMailer:
    """Dev mailer — logs the 6-digit code (never use in production)."""

    def send_verification_code(self, email: str, code: str) -> None:
        logger.info("Verification code for %s: %s", email, code)
        print(f"[mailer] Verification code for {email}: {code}")


class SmtpMailer:
    def __init__(
        self,
        *,
        host: str,
        port: int,
        username: str,
        password: str,
        from_addr: str,
    ) -> None:
        self._host = host
        self._port = port
        self._username = username
        self._password = password
        self._from = from_addr

    def send_verification_code(self, email: str, code: str) -> None:
        message = EmailMessage()
        message["Subject"] = "Your Bible Scroller verification code"
        message["From"] = self._from
        message["To"] = email
        message.set_content(
            f"Your verification code is: {code}\n\n"
            "This code expires in 15 minutes. If you did not request it, ignore this email."
        )
        with smtplib.SMTP(self._host, self._port, timeout=30) as smtp:
            smtp.starttls()
            if self._username:
                smtp.login(self._username, self._password)
            smtp.send_message(message)


class CaptureMailer:
    """Test mailer that records sent codes."""

    def __init__(self) -> None:
        self.sent: list[tuple[str, str]] = []

    def send_verification_code(self, email: str, code: str) -> None:
        self.sent.append((email, code))

    def last_code_for(self, email: str) -> str | None:
        for sent_email, code in reversed(self.sent):
            if sent_email == email:
                return code
        return None


_mailer: Mailer | None = None


def build_mailer() -> Mailer:
    if settings.smtp_host.strip():
        return SmtpMailer(
            host=settings.smtp_host.strip(),
            port=settings.smtp_port,
            username=settings.smtp_user,
            password=settings.smtp_password,
            from_addr=settings.smtp_from,
        )
    if settings.allow_console_mailer:
        return ConsoleMailer()
    raise RuntimeError(
        "SMTP_HOST is required when ALLOW_CONSOLE_MAILER is false. "
        "Configure SMTP or set ALLOW_CONSOLE_MAILER=true for local development."
    )


def get_mailer() -> Mailer:
    global _mailer
    if _mailer is None:
        _mailer = build_mailer()
    return _mailer


def set_mailer(mailer: Mailer) -> None:
    global _mailer
    _mailer = mailer
