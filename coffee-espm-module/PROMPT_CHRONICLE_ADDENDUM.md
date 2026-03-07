# Prompt Chronicle — Addendum: ESPM Portal Scraper

## What this changes

The Coffee project includes a **pre-built, tested ESPM portal scraper** located at
`app/modules/espm/`. This module handles Microsoft SSO authentication and schedule
extraction. **Do NOT rewrite this code** — it has been tested against the live portal
and the SSO flow is fragile.

This addendum modifies **Prompt 0** (Foundation) and **Prompt 2** (Disciplinas) from
the main Chronicle to integrate the scraper.

---

## Prompt 0 — Foundation (ADD to existing prompt)

Append the following after the backend directory structure section:

```
═══════════════════════════════════════
STEP 1B: ESPM SCRAPER MODULE (PRE-BUILT)
═══════════════════════════════════════

The following files are PRE-BUILT and already exist in the project.
DO NOT REWRITE THEM. Only verify they are present and imports resolve.

coffee-backend/
├── app/
│   ├── modules/
│   │   ├── __init__.py
│   │   └── espm/
│   │       ├── __init__.py
│   │       ├── router.py              # FastAPI endpoints for ESPM portal
│   │       ├── auth/
│   │       │   ├── __init__.py
│   │       │   └── authenticator.py   # Microsoft SSO flow (DO NOT MODIFY)
│   │       └── schedule/
│   │           ├── __init__.py
│   │           └── extractor.py       # Portal DOM parser (DO NOT MODIFY)
├── sql/
│   ├── 000_foundation.sql
│   └── 001_espm_portal.sql            # Adds portal columns to users + dedup constraint

INTEGRATION STEPS:

1. Run sql/001_espm_portal.sql after 000_foundation.sql.
   This adds to the `users` table:
     - encrypted_portal_session BYTEA
     - espm_login VARCHAR(255)
   And adds to `disciplinas`:
     - UNIQUE(nome, semestre) constraint
     - Extra columns: days TEXT[], time_start, time_end, period_start, period_end, workload_hours

2. Add to app/config.py Settings class (if not already present):
     secret_key: str    # Fernet key for session encryption

3. Add to requirements.txt (if not already present):
     playwright==1.49.1
     cryptography==44.0.0
     structlog==24.4.0

4. Register the ESPM router in app/main.py:
     from app.modules.espm.router import router as espm_router
     app.include_router(espm_router)

5. In Dockerfile or deployment setup, add:
     RUN playwright install chromium

VERIFY:
- python -c "from app.modules.espm.auth.authenticator import ESPMAuthenticator; print('Auth OK')"
- python -c "from app.modules.espm.schedule.extractor import ScheduleExtractor; print('Extractor OK')"
- python -c "from app.modules.espm.router import router; print('Router OK')"
```

---

## Prompt 2 — Disciplinas (REPLACE seed logic)

In Prompt 2, **replace ENDPOINT 4 (POST /api/v1/disciplinas/seed)** with:

```
ENDPOINT 4: REMOVED — replaced by ESPM portal scraper

Instead of a seed endpoint, disciplinas are populated by the ESPM portal integration:
  POST /api/v1/espm/login          — Authenticates on portal + extracts schedule
  POST /api/v1/espm/sync-schedule  — Force re-sync of schedule
  GET  /api/v1/espm/schedule       — Get extracted disciplinas

These endpoints are already implemented in app/modules/espm/router.py.
Do NOT recreate them. They are tested and working.

For local development/testing without portal access, create a simple seed script:
  coffee-backend/scripts/seed_dev.py

  import asyncio
  import asyncpg

  async def seed():
      conn = await asyncpg.connect("postgresql://...")
      # Insert 4 test disciplinas + link to a test user
      for disc in [
          ("Marketing Digital", "Prof. Ana Silva", "Seg 19:00-21:00", "2026.1"),
          ("Branding", "Prof. Carlos Lima", "Qua 19:00-21:00", "2026.1"),
          ("Finanças Corporativas", "Prof. Maria Santos", "Ter 21:00-23:00", "2026.1"),
          ("Gestão de Projetos", "Prof. Roberto Alves", "Qui 19:00-21:00", "2026.1"),
      ]:
          await conn.execute("""
              INSERT INTO disciplinas (nome, professor, horario, semestre)
              VALUES ($1, $2, $3, $4)
              ON CONFLICT (nome, semestre) DO NOTHING
          """, *disc)
      await conn.close()

  asyncio.run(seed())
```

Also in Prompt 2, **add to the iOS section**:

```
CREATE: Views/ESPM/ESPMConnectView.swift
- Shown after signup (or accessible from settings)
- Purpose: connect student's ESPM portal account to import their real disciplinas
- @State var espmEmail = ""
- @State var espmPassword = ""
- @State var isConnecting = false
- @State var connectionLogs: [String] = []
- Layout:
  - "conectar ao portal espm" title (espresso, 22px)
  - "importe suas disciplinas automaticamente" subtitle (almond, 14px)
  - CoffeeTextField(placeholder: "email espm", text: $espmEmail)
  - CoffeeTextField(placeholder: "senha do portal", text: $espmPassword, isSecure: true)
  - CoffeeButton(title: "Importar disciplinas", isLoading: isConnecting) {
      POST /api/v1/espm/login → on success navigate to DisciplinasListView
    }
  - Note below: "suas credenciais são usadas apenas para importar a grade e ficam criptografadas" (almond, 12px)
- On success: dismiss + reload disciplinas list

UPDATE: CoffeeApp.swift flow:
- if !isAuthenticated → LoginView
- else if !hasCompletedOnboarding → OnboardingView
- else if needsESPMConnect (no disciplinas yet) → ESPMConnectView
- else → MainTabView
```

---

## Prompt 6 — Scraper (MODIFY scope)

The ESPM schedule scraper is already done. Prompt 6 should focus ONLY on:
1. **Material scraper** — downloading slides/PDFs from within a disciplina page
2. **Embedding pipeline** for scraped materials
3. **Nightly cron job** for automatic material sync

The authentication and navigation code from the ESPM module can be reused:
```python
from app.modules.espm.auth.authenticator import ESPMAuthenticator
# Reuse login + session management
# Only add new navigation logic for material download pages
```
```

---

## Summary of Changes

| Chronicle Prompt | Change |
|---|---|
| Prompt 0 (Foundation) | ADD: espm module verification + integration steps |
| Prompt 2 (Disciplinas) | REPLACE: seed endpoint → ESPM portal scraper + ESPMConnectView |
| Prompt 6 (Scraper) | NARROW: only material scraper (auth already done) |
