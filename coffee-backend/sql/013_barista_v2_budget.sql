-- 013_barista_v2_budget.sql
-- Barista v2: token tracking + usage budget

-- Add token tracking columns to mensagens
ALTER TABLE mensagens ADD COLUMN IF NOT EXISTS input_tokens INTEGER;
ALTER TABLE mensagens ADD COLUMN IF NOT EXISTS output_tokens INTEGER;
ALTER TABLE mensagens ADD COLUMN IF NOT EXISTS cost_usd REAL;

-- Usage budget table (per-user per-cycle)
CREATE TABLE IF NOT EXISTS usage_budget (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    cycle_start DATE NOT NULL,
    cycle_end DATE NOT NULL,
    budget_usd REAL NOT NULL,
    used_usd REAL NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, cycle_start)
);

CREATE INDEX IF NOT EXISTS idx_usage_budget_user ON usage_budget(user_id, cycle_start DESC);
