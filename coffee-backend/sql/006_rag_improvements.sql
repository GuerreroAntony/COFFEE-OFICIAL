-- 006_rag_improvements.sql
-- Hybrid Search: tsvector column + GIN index for full-text search on embeddings
-- Used alongside vector similarity for Reciprocal Rank Fusion (RRF)

-- 1. Add tsvector column for Portuguese full-text search
ALTER TABLE embeddings ADD COLUMN IF NOT EXISTS tsv tsvector;

-- 2. Populate tsvector for all existing rows
UPDATE embeddings SET tsv = to_tsvector('portuguese', texto_chunk)
WHERE tsv IS NULL;

-- 3. GIN index for fast full-text queries
CREATE INDEX IF NOT EXISTS idx_embeddings_tsv ON embeddings USING GIN (tsv);

-- 4. Auto-update trigger: keeps tsv in sync on INSERT/UPDATE
CREATE OR REPLACE FUNCTION embeddings_tsv_trigger() RETURNS trigger AS $$
BEGIN
    NEW.tsv := to_tsvector('portuguese', NEW.texto_chunk);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_embeddings_tsv ON embeddings;
CREATE TRIGGER trg_embeddings_tsv
    BEFORE INSERT OR UPDATE OF texto_chunk ON embeddings
    FOR EACH ROW EXECUTE FUNCTION embeddings_tsv_trigger();
