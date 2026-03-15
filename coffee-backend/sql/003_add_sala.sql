-- ============================================================
-- Coffee v3.1.1 — Re-add sala column to disciplinas
-- Run AFTER 001_v3_1_migration.sql
-- ============================================================
-- The sala column was dropped in 001 because Canvas API didn't
-- provide it directly. Now we extract it from sections/course_code.

ALTER TABLE disciplinas ADD COLUMN IF NOT EXISTS sala VARCHAR(50);
