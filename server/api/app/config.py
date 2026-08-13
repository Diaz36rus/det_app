from pydantic_settings import BaseSettings, SettingsConfigDict


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
    releases_dir: str = "/data/releases"
    public_base_url: str = "http://api.det-app.ru"
    release_upload_token: str = ""


settings = Settings()
