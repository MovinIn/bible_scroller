from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

_DEFAULT_JWT_SECRET = "dev-change-me"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql://bible_scroller:bible_scroller@localhost:5432/bible_scroller"
    bible_brain_api_key: str = ""
    bible_brain_base_url: str = "https://4.dbt.io/api"
    pipeline_images_roots: str = ""
    pipeline_mount_root: str = ""
    # Local helloao chapter JSON cache (pipeline/data/chapters). Used when
    # BIBLE_BRAIN_API_KEY is unset so browsing still has real verse text/audio.
    chapter_cache_root: str = ""
    media_base_url: str = "http://127.0.0.1:8000"
    seed_manifest_path: str = ""
    # 0 = seed every group from the manifest.
    seed_limit: int = 0

    environment: str = "development"  # development | test | production
    google_client_ids: str = ""
    jwt_secret: str = _DEFAULT_JWT_SECRET
    jwt_expire_minutes: int = 60 * 24 * 30
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from: str = "noreply@biblescroller.local"
    allow_console_mailer: bool = True

    # Rate limits (per key per window)
    auth_register_limit: int = 5
    auth_verify_limit: int = 10
    auth_resend_limit: int = 5
    auth_rate_window_seconds: int = 900

    @property
    def google_client_id_list(self) -> list[str]:
        return [part.strip() for part in self.google_client_ids.split(",") if part.strip()]

    @property
    def is_production(self) -> bool:
        return self.environment.lower() == "production"

    @field_validator("jwt_secret")
    @classmethod
    def jwt_secret_min_length(cls, value: str) -> str:
        if len(value) < 32 and value != _DEFAULT_JWT_SECRET:
            raise ValueError("JWT_SECRET must be at least 32 characters")
        return value


settings = Settings()


def validate_runtime_settings() -> None:
    """Fail fast for insecure production configuration."""
    if settings.environment.lower() == "test":
        return
    if settings.jwt_secret == _DEFAULT_JWT_SECRET:
        if settings.is_production:
            raise RuntimeError("JWT_SECRET must be set to a strong secret in production")
    if settings.is_production and not settings.smtp_host.strip() and not settings.allow_console_mailer:
        raise RuntimeError("SMTP_HOST must be configured in production")
    if settings.is_production and settings.allow_console_mailer and not settings.smtp_host.strip():
        raise RuntimeError(
            "ALLOW_CONSOLE_MAILER cannot be used in production; configure SMTP_HOST"
        )
