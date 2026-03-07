-- ══════════════════════════════════════════════════════════════════════════════
-- Migration 002: turma, horarios JSONB; remove workload_hours
-- Run AFTER 001_espm_portal.sql
-- ══════════════════════════════════════════════════════════════════════════════

-- 1. Adicionar colunas novas
ALTER TABLE disciplinas
    ADD COLUMN IF NOT EXISTS turma    VARCHAR(20),
    ADD COLUMN IF NOT EXISTS horarios JSONB DEFAULT '[]';

-- 2. Remover workload_hours (inutilizado)
ALTER TABLE disciplinas
    DROP COLUMN IF EXISTS workload_hours;

-- 3. Popular turma + corrigir nome nas linhas existentes
--    "AD1N - Business Lab 1" → turma="AD1N", nome="Business Lab 1"
UPDATE disciplinas
SET
    turma = TRIM(SPLIT_PART(nome, ' - ', 1)),
    nome  = TRIM(SUBSTRING(nome FROM POSITION(' - ' IN nome) + 3))
WHERE nome LIKE '% - %';
