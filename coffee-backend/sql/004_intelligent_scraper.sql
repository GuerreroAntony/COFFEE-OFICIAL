-- Migration 004: Intelligent Multi-User Scraper Support
-- Stores encrypted ESPM passwords for credential pooling
-- and tracks scraping freshness per disciplina.

-- Store encrypted ESPM password for scraper credential pool
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS encrypted_espm_password BYTEA;

-- Track when each disciplina was last scraped for materials
ALTER TABLE disciplinas
    ADD COLUMN IF NOT EXISTS last_scraped_at TIMESTAMP WITH TIME ZONE;

-- Index for finding stale disciplinas efficiently (NULLs = never scraped = first)
CREATE INDEX IF NOT EXISTS idx_disciplinas_last_scraped
    ON disciplinas (last_scraped_at NULLS FIRST);
