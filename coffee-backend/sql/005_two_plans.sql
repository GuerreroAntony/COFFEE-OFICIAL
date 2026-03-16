-- ============================================================
-- Coffee — Migration 005: Two-tier plan system
-- Café com Leite (R$29.90) + Black (R$49.90)
-- ============================================================

-- 1. Expand plano CHECK on users to support new plan names
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_plano_check;
ALTER TABLE users ADD CONSTRAINT users_plano_check
    CHECK (plano IN ('trial', 'cafe_com_leite', 'black', 'expired'));

-- 2. Migrate existing premium users → cafe_com_leite
UPDATE users SET plano = 'cafe_com_leite' WHERE plano = 'premium';

-- 3. Expand subscriptions plano CHECK
ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS subscriptions_plano_check;
ALTER TABLE subscriptions ADD CONSTRAINT subscriptions_plano_check
    CHECK (plano IN ('cafe_com_leite', 'black'));

-- 4. Migrate existing subscriptions
UPDATE subscriptions SET plano = 'cafe_com_leite' WHERE plano = 'premium';
