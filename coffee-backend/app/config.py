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
    ESPM_PORTAL_URL: str = "https://portal.espm.br"
    ESPM_USERNAME: str = ""
    ESPM_PASSWORD: str = ""
    ENVIRONMENT: str = "development"
    secret_key: str = ""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


settings = Settings()


def get_settings() -> Settings:
    return settings
