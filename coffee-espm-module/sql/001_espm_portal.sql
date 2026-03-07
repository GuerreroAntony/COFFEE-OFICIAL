-- ══════════════════════════════════════════════════════════════════════════════
-- Migration: Add ESPM portal session support to Coffee
-- Run AFTER 000_foundation.sql
-- ══════════════════════════════════════════════════════════════════════════════

-- 1. Add portal session columns to users table
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS encrypted_portal_session BYTEA,
    ADD COLUMN IF NOT EXISTS espm_login VARCHAR(255);

-- 2. Add unique constraint for disciplina dedup (used by upsert)
-- The scraper uses (nome, semestre) to detect if a course already exists
ALTER TABLE disciplinas
    ADD CONSTRAINT disciplinas_nome_semestre_unique
    UNIQUE (nome, semestre);

-- 3. Add metadata columns to disciplinas for richer portal data
ALTER TABLE disciplinas
    ADD COLUMN IF NOT EXISTS days TEXT[],
    ADD COLUMN IF NOT EXISTS time_start VARCHAR(10),
    ADD COLUMN IF NOT EXISTS time_end VARCHAR(10),
    ADD COLUMN IF NOT EXISTS period_start DATE,
    ADD COLUMN IF NOT EXISTS period_end DATE,
    ADD COLUMN IF NOT EXISTS workload_hours INTEGER;

-- 4. Index for faster schedule lookups
CREATE INDEX IF NOT EXISTS idx_disciplinas_semestre ON disciplinas(semestre);
