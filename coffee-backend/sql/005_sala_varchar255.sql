-- sala column was VARCHAR(50) which truncated long Canvas section names
-- (e.g. "AD1N-02837-GADMSSPA-2601-AD1N-2837-Branding..." = 76 chars)
ALTER TABLE disciplinas ALTER COLUMN sala TYPE VARCHAR(255);
