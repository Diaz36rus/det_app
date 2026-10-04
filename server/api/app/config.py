from pydantic_settings import BaseSettings, SettingsConfigDict

_INSECURE_DEFAULTS = {
    "change-me-in-production",
    "change_me_long_random_jwt_secret",
    "ChangeMeNow123!",
    "change_me_release_upload_token",
}


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+psycopg://detapp:detapp@db:5432/detapp"
    app_env: str = "development"
    jwt_secret: str = "change-me-in-production"
    jwt_access_minutes: int = 60
    jwt_refresh_days: int = 30
    platform_admin_email: str = "admin@det-app.ru"
    platform_admin_password: str = "ChangeMeNow123!"
    platform_admin_name: str = "Platform Admin"
    platform_admin_phone: str = ""
    ## PIN для wipe и т.п. на клиенте зашит отдельно; на API — reserved.
    owner_destructive_pin: str = "9294"
    releases_dir: str = "/data/releases"
    public_base_url: str = "https://api.det-app.ru"
    release_upload_token: str = ""
    # Swagger /docs в production по умолчанию выключен.
    enable_docs: bool = False

    # Telegram bot (платформенный, multi-tenant через deep-link)
    telegram_bot_token: str = ""
    telegram_bot_username: str = ""
    telegram_bind_secret: str = ""
    # setWebhook(secret_token=…) → заголовок X-Telegram-Bot-Api-Secret-Token
    telegram_webhook_secret: str = ""
    # SMS fallback: POST JSON {phone, text}; Authorization: Bearer key
    sms_api_url: str = ""
    sms_api_key: str = ""
    # GlitchTip/Sentry DSN; пусто — отчёты об ошибках выключены.
    sentry_dsn: str = ""

    @property
    def is_production(self) -> bool:
        return self.app_env.strip().lower() in ("production", "prod")

    def assert_safe_for_production(self) -> None:
        if not self.is_production:
            return
        problems: list[str] = []
        if self.jwt_secret in _INSECURE_DEFAULTS or len(self.jwt_secret) < 32:
            problems.append("JWT_SECRET (нужно ≥32 случайных символов)")
        if self.platform_admin_password in _INSECURE_DEFAULTS or len(self.platform_admin_password) < 12:
            problems.append("PLATFORM_ADMIN_PASSWORD (нужно ≥12 символов, не дефолт)")
        token = self.release_upload_token.strip()
        if token and (token in _INSECURE_DEFAULTS or len(token) < 20):
            problems.append("RELEASE_UPLOAD_TOKEN (нужно ≥20 символов)")
        if problems:
            raise RuntimeError("Небезопасная конфигурация production: " + "; ".join(problems))


settings = Settings()
