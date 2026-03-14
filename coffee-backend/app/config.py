from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    DATABASE_URL: str
    SUPABASE_URL: str
    SUPABASE_KEY: str
    OPENAI_API_KEY: str
    ANTHROPIC_API_KEY: str = ""
    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRATION_HOURS: int = 168
    # Firebase Admin SDK
    GOOGLE_APPLICATION_CREDENTIALS: str = "firebase-service-account.json"
    FIREBASE_PROJECT_ID: str = ""
    SUPABASE_STORAGE_BUCKET: str = "materiais"
    SUPABASE_MEDIA_BUCKET: str = "gravacao-media"
    ENVIRONMENT: str = "development"
    SECRET_KEY: str = ""
    # App limits
    APPLE_SHARED_SECRET: str = ""
    TRIAL_DAYS: int = 7
    GIFT_CODE_BONUS_DAYS: int = 7
    LUNGO_MONTHLY_LIMIT: int = 30
    COLD_BREW_MONTHLY_LIMIT: int = 15
    SYNC_COOLDOWN_HOURS: int = 1
    # Support
    SUPPORT_EMAIL: str = "suportecoffeeapp@gmail.com"
    SMTP_HOST: str = ""
    SMTP_PORT: int = 587
    SMTP_USER: str = ""
    SMTP_PASSWORD: str = ""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")


settings = Settings()


def get_settings() -> Settings:
    return settings
