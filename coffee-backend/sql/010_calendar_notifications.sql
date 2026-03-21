-- 010_calendar_notifications.sql
-- Add notification tracking columns to calendar_events

ALTER TABLE calendar_events ADD COLUMN IF NOT EXISTS notified_1d BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE calendar_events ADD COLUMN IF NOT EXISTS notified_1h BOOLEAN NOT NULL DEFAULT false;

-- Index for efficient notification queries (find un-notified upcoming events)
CREATE INDEX IF NOT EXISTS idx_calendar_events_notify_pending
    ON calendar_events (start_at)
    WHERE notified_1d = false OR notified_1h = false;
