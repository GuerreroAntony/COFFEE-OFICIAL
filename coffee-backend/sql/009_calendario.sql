-- 009_calendario.sql
-- Calendar events table (Canvas planner items + manual events)

CREATE TABLE IF NOT EXISTS calendar_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    disciplina_id   UUID REFERENCES disciplinas(id) ON DELETE SET NULL,

    -- Source tracking
    source          TEXT NOT NULL DEFAULT 'manual',  -- 'canvas_assignment', 'canvas_quiz', 'manual'
    canvas_plannable_id  BIGINT,                      -- dedup key from Canvas planner/items
    plannable_type  TEXT,                              -- 'assignment', 'quiz', 'announcement'

    -- Event info
    title           TEXT NOT NULL,
    description     TEXT,
    location        TEXT,
    event_type      TEXT NOT NULL DEFAULT 'event',     -- 'assignment', 'quiz', 'exam', 'deadline', 'event', 'reminder'

    -- Dates
    start_at        TIMESTAMPTZ NOT NULL,
    end_at          TIMESTAMPTZ,
    all_day         BOOLEAN NOT NULL DEFAULT false,
    due_at          TIMESTAMPTZ,

    -- Assignment/quiz data from Canvas
    points_possible REAL,
    submitted       BOOLEAN DEFAULT false,
    graded          BOOLEAN DEFAULT false,
    late            BOOLEAN DEFAULT false,
    missing         BOOLEAN DEFAULT false,

    -- Deep link
    canvas_url      TEXT,
    course_name     TEXT,                             -- cached context_name from Canvas

    -- Status
    completed       BOOLEAN NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Dedup: one Canvas plannable per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_calendar_events_canvas_dedup
    ON calendar_events (user_id, canvas_plannable_id, plannable_type)
    WHERE canvas_plannable_id IS NOT NULL;

-- Query by user + date range
CREATE INDEX IF NOT EXISTS idx_calendar_events_user_start
    ON calendar_events (user_id, start_at);

-- Track last sync time per user
ALTER TABLE users ADD COLUMN IF NOT EXISTS calendar_last_synced_at TIMESTAMPTZ;
