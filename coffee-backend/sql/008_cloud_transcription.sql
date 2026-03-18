-- 008_cloud_transcription.sql
-- Cloud transcription pipeline: recording uploads + shared aula transcripts
-- Run after all previous migrations (000-007)

-- 1. recording_uploads: per-student audio upload metadata (temporary, audio deleted after processing)
CREATE TABLE IF NOT EXISTS recording_uploads (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    disciplina_id UUID NOT NULL REFERENCES disciplinas(id) ON DELETE CASCADE,
    gravacao_id UUID REFERENCES gravacoes(id) ON DELETE SET NULL,
    storage_path TEXT NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    duration_seconds INTEGER NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    quality_score REAL DEFAULT 0.0,
    status VARCHAR(20) DEFAULT 'uploaded'
        CHECK (status IN ('uploaded', 'selected', 'processed', 'discarded')),
    aula_transcript_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ru_disc_start ON recording_uploads(disciplina_id, start_time);
CREATE INDEX IF NOT EXISTS idx_ru_status ON recording_uploads(status);

-- 2. aula_transcripts: shared discipline-level transcript (1 per class session)
CREATE TABLE IF NOT EXISTS aula_transcripts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    disciplina_id UUID NOT NULL REFERENCES disciplinas(id) ON DELETE CASCADE,
    selected_upload_id UUID,
    date DATE NOT NULL,
    transcription TEXT,
    short_summary TEXT,
    full_summary JSONB,
    mind_map JSONB,
    status VARCHAR(20) DEFAULT 'pending'
        CHECK (status IN ('pending', 'transcribing', 'processing', 'ready', 'error')),
    cost_usd REAL DEFAULT 0.0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_at_disc_date ON aula_transcripts(disciplina_id, date);
CREATE INDEX IF NOT EXISTS idx_at_status ON aula_transcripts(status);

-- 3. FK from recording_uploads to aula_transcripts
ALTER TABLE recording_uploads
    ADD CONSTRAINT fk_ru_transcript FOREIGN KEY (aula_transcript_id)
    REFERENCES aula_transcripts(id) ON DELETE SET NULL;

-- 4. New columns on gravacoes to link to shared transcript
ALTER TABLE gravacoes ADD COLUMN IF NOT EXISTS aula_transcript_id UUID
    REFERENCES aula_transcripts(id) ON DELETE SET NULL;
ALTER TABLE gravacoes ADD COLUMN IF NOT EXISTS upload_type VARCHAR(20)
    DEFAULT 'text' CHECK (upload_type IN ('text', 'audio'));
CREATE INDEX IF NOT EXISTS idx_grav_aula_transcript ON gravacoes(aula_transcript_id)
    WHERE aula_transcript_id IS NOT NULL;
