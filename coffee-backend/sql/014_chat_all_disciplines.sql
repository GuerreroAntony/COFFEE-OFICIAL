-- 014_chat_all_disciplines.sql
-- Allow source_type = 'all' for cross-discipline Barista chats

-- Drop old constraint and add new one with 'all'
ALTER TABLE chats DROP CONSTRAINT IF EXISTS chats_source_type_check;
ALTER TABLE chats ADD CONSTRAINT chats_source_type_check
    CHECK (source_type IN ('disciplina', 'repositorio', 'all'));
