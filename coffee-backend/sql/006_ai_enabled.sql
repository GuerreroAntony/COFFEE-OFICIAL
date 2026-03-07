-- Migration 006: AI-Enabled Toggle for Materials
-- Materials matching "Aula \d+" pattern are AI-enabled by default.
-- Fallback-scraped materials default to false.

ALTER TABLE materiais
    ADD COLUMN IF NOT EXISTS ai_enabled BOOLEAN DEFAULT true;

-- Backfill: materials NOT matching "Aula X" pattern → ai_enabled = false
UPDATE materiais SET ai_enabled = false WHERE nome !~* 'Aula\s*\d+';

-- Partial index to speed up RAG queries filtering by ai_enabled
CREATE INDEX IF NOT EXISTS idx_materiais_ai_enabled
    ON materiais (disciplina_id) WHERE ai_enabled = true;
