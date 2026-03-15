"""
ESPM Authenticator — Stub for development.
Will be replaced with real Playwright-based authenticator.
"""
from cryptography.fernet import Fernet
import base64
import hashlib


class AuthenticationError(Exception):
    """Raised when ESPM portal authentication fails."""
    pass


class ESPMAuthenticator:
    """Handles ESPM portal login via Microsoft SSO (Playwright)."""

    def __init__(self, secret_key: str):
        key = base64.urlsafe_b64encode(hashlib.sha256(secret_key.encode()).digest())
        self._fernet = Fernet(key)

    async def login_and_extract(self, matricula: str, password: str, extractor=None) -> dict:
        """
        Login to ESPM portal and extract schedule.
        Returns dict with keys: disciplines, logs, state, auth_error
        """
        raise AuthenticationError(
            "ESPM authenticator not configured. "
            "Copy the real authenticator module to app/modules/espm/auth/"
        )

    def encrypt_session(self, data: dict) -> bytes:
        """Encrypt session data using Fernet."""
        import json
        return self._fernet.encrypt(json.dumps(data).encode())

    def decrypt_session(self, encrypted: bytes) -> dict:
        """Decrypt session data."""
        import json
        return json.loads(self._fernet.decrypt(encrypted).decode())
