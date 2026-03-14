-- 002_password_reset.sql
-- Adds password reset support (6-digit code, 15min expiry)

ALTER TABLE users ADD COLUMN IF NOT EXISTS reset_code_hash VARCHAR(128);
ALTER TABLE users ADD COLUMN IF NOT EXISTS reset_code_expires TIMESTAMPTZ;
