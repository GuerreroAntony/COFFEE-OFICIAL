-- 007_discipline_appearance.sql
-- Adiciona campos de aparência customizável por disciplina (ícone + cor)
-- Campos em user_disciplinas (per-user, não na disciplina em si)

ALTER TABLE user_disciplinas
    ADD COLUMN IF NOT EXISTS icon VARCHAR(50) DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS icon_color VARCHAR(7) DEFAULT NULL;

-- icon: SF Symbol name (ex: "star.fill", "book.fill")
-- icon_color: hex color sem # (ex: "715038", "D4A574")
-- NULL = frontend usa default por índice
