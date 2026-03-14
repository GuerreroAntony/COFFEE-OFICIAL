-- ============================================================
-- Coffee v3.1 — Migration from v2 foundation
-- Run AFTER 000_v2_foundation.sql
-- ============================================================

-- ============================================================
-- 1. users: add Canvas token columns
-- ============================================================
ALTER TABLE users ADD COLUMN IF NOT EXISTS canvas_token TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS canvas_token_expires_at TIMESTAMPTZ;

-- ============================================================
-- 2. disciplinas: drop columns Canvas API doesn't provide
-- ============================================================
ALTER TABLE disciplinas DROP COLUMN IF EXISTS professor;
ALTER TABLE disciplinas DROP COLUMN IF EXISTS horario;
ALTER TABLE disciplinas DROP COLUMN IF EXISTS sala;
ALTER TABLE disciplinas DROP COLUMN IF EXISTS horarios;

-- ============================================================
-- 3. gravacoes: add mind_map and received_from
-- ============================================================
ALTER TABLE gravacoes ADD COLUMN IF NOT EXISTS mind_map JSONB;
ALTER TABLE gravacoes ADD COLUMN IF NOT EXISTS received_from VARCHAR(255);

-- ============================================================
-- 4. mensagens: add mode column (espresso/lungo/cold_brew)
-- ============================================================
ALTER TABLE mensagens ADD COLUMN IF NOT EXISTS mode VARCHAR(20);

-- ============================================================
-- 5. NEW TABLE: compartilhamentos
-- ============================================================
CREATE TABLE IF NOT EXISTS compartilhamentos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    gravacao_id UUID NOT NULL REFERENCES gravacoes(id) ON DELETE CASCADE,
    shared_content JSONB DEFAULT '[]',
    message TEXT,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
    destination_type VARCHAR(20),
    destination_id UUID,
    created_gravacao_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_comp_sender ON compartilhamentos(sender_id);
CREATE INDEX IF NOT EXISTS idx_comp_recipient ON compartilhamentos(recipient_id);
CREATE INDEX IF NOT EXISTS idx_comp_recipient_status ON compartilhamentos(recipient_id, status);

-- ============================================================
-- 6. NEW TABLE: gift_codes (replaces referrals)
-- ============================================================
CREATE TABLE IF NOT EXISTS gift_codes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code VARCHAR(20) UNIQUE NOT NULL,
    redeemed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    redeemed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_gc_owner ON gift_codes(owner_id);
CREATE INDEX IF NOT EXISTS idx_gc_code ON gift_codes(code);

-- ============================================================
-- 7. DROP referrals table (replaced by gift_codes)
-- ============================================================
DROP TABLE IF EXISTS referrals;

-- Drop old referral index on users (column stays for now, unused)
DROP INDEX IF EXISTS idx_users_referral;
