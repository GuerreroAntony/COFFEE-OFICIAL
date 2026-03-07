-- Migration 003: Canvas Scraper Support
-- Adds canvas_course_id to disciplinas and canvas_file_id to materiais
-- for deduplication and course matching with Canvas ESPM.

ALTER TABLE disciplinas
    ADD COLUMN IF NOT EXISTS canvas_course_id INTEGER;

ALTER TABLE materiais
    ADD COLUMN IF NOT EXISTS canvas_file_id INTEGER;

-- Partial unique index: one canvas file per material (NULLs allowed for manual uploads)
CREATE UNIQUE INDEX IF NOT EXISTS idx_materiais_canvas_file
    ON materiais (canvas_file_id) WHERE canvas_file_id IS NOT NULL;

-- Index for fast course matching
CREATE INDEX IF NOT EXISTS idx_disciplinas_canvas_course
    ON disciplinas (canvas_course_id) WHERE canvas_course_id IS NOT NULL;
