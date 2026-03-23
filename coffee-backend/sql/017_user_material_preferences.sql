-- 017_user_material_preferences.sql
-- Per-user ai_enabled preference for materials
-- Default fallback: materiais.ai_enabled (set by scraper)

CREATE TABLE IF NOT EXISTS user_material_preferences (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    material_id UUID NOT NULL REFERENCES materiais(id) ON DELETE CASCADE,
    ai_enabled BOOLEAN NOT NULL DEFAULT true,
    PRIMARY KEY (user_id, material_id)
);

CREATE INDEX IF NOT EXISTS idx_ump_material ON user_material_preferences(material_id);
