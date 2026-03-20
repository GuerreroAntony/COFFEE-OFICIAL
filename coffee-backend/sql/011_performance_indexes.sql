-- 011_performance_indexes.sql
-- Composite indexes for frequently queried patterns

-- Chat messages: ordered by creation date (used in message history + last message subqueries)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_msg_chat_created
    ON mensagens(chat_id, created_at DESC);

-- Gravacoes: filter by user + source (used in recordings list)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_grav_user_source
    ON gravacoes(user_id, source_type, source_id);

-- Chats: list user's chats ordered by last update
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chats_user_updated
    ON chats(user_id, updated_at DESC);
