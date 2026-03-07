from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    DATABASE_URL: str
    SUPABASE_URL: str
    SUPABASE_KEY: str  # service-role key for storage uploads
    OPENAI_API_KEY: str
    ESPM_USERNAME: str = ""  # Canvas SSO email (optional fallback)
    ESPM_PASSWORD: str = ""  # Canvas SSO password (optional fallback)
    SECRET_KEY: str = ""  # Fernet key for decrypting user passwords
    ESPM_PORTAL_URL: str = "https://canvas.espm.br"
    SUPABASE_STORAGE_BUCKET: str = "materiais"
    DOWNLOAD_DIR: str = "/tmp/downloads"
    HEADLESS: bool = True
    LOG_LEVEL: str = "INFO"
    GOOGLE_APPLICATION_CREDENTIALS: str = "firebase-service-account.json"
    FIREBASE_PROJECT_ID: str = ""

    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )


settings = Settings()
