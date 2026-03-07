-- Migration 001: ESPM Portal Integration
-- Adds columns needed by app/modules/espm/router.py

-- Users: ESPM session + login
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS encrypted_portal_session BYTEA,
    ADD COLUMN IF NOT EXISTS espm_login VARCHAR(255);

-- Disciplinas: schedule detail fields
ALTER TABLE disciplinas
    ADD COLUMN IF NOT EXISTS days TEXT[],
    ADD COLUMN IF NOT EXISTS time_start VARCHAR(10),
    ADD COLUMN IF NOT EXISTS time_end VARCHAR(10),
    ADD COLUMN IF NOT EXISTS period_start DATE,
    ADD COLUMN IF NOT EXISTS period_end DATE;

-- Unique constraint for upsert dedup (IF NOT EXISTS)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'disciplinas_nome_semestre_unique'
    ) THEN
        ALTER TABLE disciplinas
            ADD CONSTRAINT disciplinas_nome_semestre_unique UNIQUE (nome, semestre);
    END IF;
END $$;
