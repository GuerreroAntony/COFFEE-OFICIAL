-- ══════════════════════════════════════════════════════════════════════════════
-- Migration 005: Fix device_tokens column name + notificacoes.lida
-- Run AFTER 004_intelligent_scraper.sql
-- ══════════════════════════════════════════════════════════════════════════════

-- 1. Rename token → fcm_token (code already references fcm_token)
ALTER TABLE device_tokens RENAME COLUMN token TO fcm_token;

-- 2. Unique constraint needed for ON CONFLICT (fcm_token) upsert
ALTER TABLE device_tokens ADD CONSTRAINT device_tokens_fcm_token_unique UNIQUE (fcm_token);

-- 3. updated_at column for token refresh tracking
ALTER TABLE device_tokens ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- 4. lida column for notification read status
ALTER TABLE notificacoes ADD COLUMN IF NOT EXISTS lida BOOLEAN DEFAULT false;
