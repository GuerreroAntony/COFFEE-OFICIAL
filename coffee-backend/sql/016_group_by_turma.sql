-- 016_group_by_turma.sql
-- Change auto-groups from per-discipline to per-turma (one group per class)

-- Add turma column to groups
ALTER TABLE groups ADD COLUMN IF NOT EXISTS turma VARCHAR(20);

-- Drop old unique index (per-discipline)
DROP INDEX IF EXISTS idx_groups_auto_disc;

-- Create new unique index (per-turma + semestre via nome)
CREATE UNIQUE INDEX IF NOT EXISTS idx_groups_auto_turma
    ON groups(turma) WHERE is_auto = true AND turma IS NOT NULL;

-- Clean up any auto-groups created per-discipline (start fresh)
DELETE FROM groups WHERE is_auto = true;
