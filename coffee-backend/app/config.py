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
    SUPABASE_RECORDINGS_BUCKET: str = "recordings"
    TRANSCRIPTION_WAIT_MINUTES: int = 10
    ENVIRONMENT: str = "development"
    SECRET_KEY: str = ""
    # App limits
    APPLE_SHARED_SECRET: str = ""
    TRIAL_DAYS: int = 7
    GIFT_CODE_BONUS_DAYS: int = 7
    # Café com Leite limits (also used for trial/degustação)
    CAFE_ESPRESSO_LIMIT: int = 75
    CAFE_LUNGO_LIMIT: int = 30
    CAFE_COLD_BREW_LIMIT: int = 15
    # Black limits
    BLACK_ESPRESSO_LIMIT: int = -1   # unlimited
    BLACK_LUNGO_LIMIT: int = 100
    BLACK_COLD_BREW_LIMIT: int = 25
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
