from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    DATABASE_URL: str
    SUPABASE_URL: str
    SUPABASE_KEY: str
    OPENAI_API_KEY: str
    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRATION_HOURS: int = 168
    # Firebase Admin SDK (replaces legacy FCM_SERVER_KEY)
    GOOGLE_APPLICATION_CREDENTIALS: str = "firebase-service-account.json"
    FIREBASE_PROJECT_ID: str = ""
    SUPABASE_STORAGE_BUCKET: str = "materiais"
    SUPABASE_MEDIA_BUCKET: str = "gravacao-media"
    ENVIRONMENT: str = "development"
    SECRET_KEY: str = ""
    # App limits
    APPLE_SHARED_SECRET: str = ""
    TRIAL_DAYS: int = 7
    REFERRAL_BONUS_DAYS: int = 7
    QUESTION_LIMIT_TRIAL: int = 10
    QUESTION_LIMIT_PREMIUM: int = -1
    SYNC_COOLDOWN_HOURS: int = 4

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")


settings = Settings()


def get_settings() -> Settings:
    return settings
