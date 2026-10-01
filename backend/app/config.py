from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import List
import json


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # Application
    APP_NAME: str = "UbumweConnect"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False

    # Security
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # Database
    DATABASE_URL: str
    DATABASE_URL_SYNC: str = ""

    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"

    # Firebase
    FIREBASE_CREDENTIALS_PATH: str = "./firebase-credentials.json"
    FIREBASE_WEB_API_KEY: str = ""

    # OpenAI
    OPENAI_API_KEY: str

    # AWS S3
    AWS_ACCESS_KEY_ID: str = ""
    AWS_SECRET_ACCESS_KEY: str = ""
    AWS_REGION: str = "us-east-1"
    AWS_S3_BUCKET: str = "ubumwe-connect-storage"

    # CORS
    CORS_ORIGINS: str = '["http://localhost:3000", "http://localhost:8080"]'

    # Trusted hosts (Host header allow-list). "testserver" is included for pytest.
    TRUSTED_HOSTS: str = '["localhost", "127.0.0.1", "testserver", "test", "0.0.0.0"]'

    # Email
    SMTP_HOST: str = "smtp.gmail.com"
    SMTP_PORT: int = 587
    SMTP_USER: str = ""
    SMTP_PASSWORD: str = ""
    EMAIL_FROM: str = "Ubumwe Connect <noreply@ubumweconnect.com>"

    # WebRTC / TURN
    TURN_SERVER_URL: str = "turn:localhost:3478"
    TURN_USERNAME: str = "ubumwe"
    TURN_PASSWORD: str = "ubumwe"

    # Rate Limiting
    RATE_LIMIT_PER_MINUTE: int = 100
    TRANSLATION_RATE_LIMIT_PER_MINUTE: int = 20

    def get_cors_origins(self) -> List[str]:
        try:
            return json.loads(self.CORS_ORIGINS)
        except Exception:
            return ["http://localhost:3000", "http://localhost:8080"]

    def get_trusted_hosts(self) -> List[str]:
        try:
            return json.loads(self.TRUSTED_HOSTS)
        except Exception:
            return ["localhost", "127.0.0.1", "testserver"]


settings = Settings()
