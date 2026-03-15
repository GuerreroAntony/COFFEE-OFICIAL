-- Canvas API returns global IDs (shard + local) that overflow INT32.
-- Example: 115520000000049137 (shard=11552, local=49137)
ALTER TABLE disciplinas ALTER COLUMN canvas_course_id TYPE BIGINT;

-- Fix existing local IDs → global IDs (shard 11552 for ESPM Canvas)
UPDATE disciplinas
SET canvas_course_id = canvas_course_id + 115520000000000000
WHERE canvas_course_id IS NOT NULL AND canvas_course_id < 1000000000;
