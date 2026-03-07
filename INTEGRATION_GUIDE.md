# Coffee ESPM Scraper — Integration Guide for Claude Code

## Overview

These files implement the ESPM portal web scraper — the component that logs into
portal.espm.br via Microsoft SSO and extracts the student's course schedule
(disciplinas). This code has been tested and works. Do NOT rewrite the core
authentication logic.

## Files to integrate

```
coffee-scraper-adapted/
├── auth/
│   ├── __init__.py              # empty
│   └── authenticator.py         # ESPMAuthenticator — MS SSO login (DO NOT MODIFY CORE FLOW)
├── schedule/
│   ├── __init__.py              # empty
│   └── extractor.py             # ScheduleExtractor — DOM parsing for course grid
├── espm_router.py               # FastAPI router adapted for Coffee (asyncpg)
├── sql/
│   └── 001_espm_portal.sql      # Migration: adds portal columns + dedup constraint
└── test_scraper.py              # Standalone test script
```

## Where each file goes in the Coffee project

```
coffee-backend/
├── app/
│   ├── modules/
│   │   ├── espm/
│   │   │   ├── __init__.py
│   │   │   ├── auth/
│   │   │   │   ├── __init__.py
│   │   │   │   └── authenticator.py    ← from auth/authenticator.py
│   │   │   ├── schedule/
│   │   │   │   ├── __init__.py
│   │   │   │   └── extractor.py        ← from schedule/extractor.py
│   │   │   └── router.py              ← from espm_router.py
│   ├── routers/
│   │   └── ... (existing routers)
├── sql/
│   ├── 000_foundation.sql
│   └── 001_espm_portal.sql            ← from sql/001_espm_portal.sql
```

## Integration steps

### 1. Run SQL migration
Execute `sql/001_espm_portal.sql` against the Supabase database.
This adds:
- `encrypted_portal_session BYTEA` and `espm_login VARCHAR(255)` to `users`
- `UNIQUE (nome, semestre)` constraint on `disciplinas`
- Extra metadata columns on `disciplinas` (days, time_start, time_end, etc.)

### 2. Add dependencies to requirements.txt
These should already be present from foundation, but verify:
```
playwright==1.49.1
cryptography==44.0.0
structlog==24.4.0
```
Then run: `playwright install chromium`

### 3. Add SECRET_KEY to .env
```
SECRET_KEY=<32-byte-base64-fernet-key>
```
Generate with: `python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"`

Add `SECRET_KEY: str` to `app/config.py` Settings class.

### 4. Register router in main.py
```python
from app.modules.espm.router import router as espm_router
app.include_router(espm_router)
```

### 5. Fix imports in espm_router.py
Adjust the relative imports based on final directory placement:
```python
from app.modules.espm.auth.authenticator import AuthenticationError, ESPMAuthenticator
from app.modules.espm.schedule.extractor import ScheduleExtractor
```

## API Endpoints

### POST /api/v1/espm/login
Authenticates student on ESPM portal and extracts their schedule.
Requires Coffee JWT (student must already have a Coffee account).

Request:
```json
{ "login": "aluno@espm.br", "password": "portal-password" }
```
Response:
```json
{
  "user_id": "uuid",
  "session_valid": true,
  "disciplines_synced": 6,
  "logs": ["Navegando para portal.espm.br...", "Login concluído com sucesso.", ...]
}
```

### POST /api/v1/espm/sync-schedule
Force re-sync of schedule (makes a new login, extracts fresh data).
Same request/response shape.

### GET /api/v1/espm/schedule
Returns the student's extracted disciplines.
```json
{
  "disciplinas": [
    { "id": "uuid", "nome": "...", "professor": "...", "horario": "...", "semestre": "2026.1" }
  ]
}
```

## How the authentication flow works (DO NOT CHANGE)

1. Navigate to `portal.espm.br`
2. Click `#ESPMExchange` button ("Conectar com sua conta ESPM")
3. Microsoft SSO page loads
4. Fill email field `input[name="loginfmt"]`, click Next
5. Wait for password field `input[name="passwd"]` to become visible
6. **Sleep 1 second** (critical — Microsoft animation)
7. Fill password, **sleep 1 second**, click Sign in
8. Loop waiting for redirect back to `portal.espm.br`:
   - Auto-dismiss "Stay signed in?" popup if it appears
   - Check URL every 2 seconds
   - Max 120 seconds timeout
9. Save Playwright `storage_state` (cookies + localStorage)
10. Encrypt with Fernet and store in `users.encrypted_portal_session`

### Critical pitfalls (tested the hard way):
- **Timeouts must be 60s** for SSO steps — Microsoft is slow
- **The 1-second sleeps after filling password/before submit are mandatory** — without them, Playwright loses track of the page state during Microsoft animations
- **`--disable-web-security` Chromium flag is required** — the SSO uses cross-origin iframes
- **Grid view activation requires JS fallback** — `svg.lucide-layout-grid` is inside a Lucide icon that doesn't respond to Playwright click; use `document.querySelector().closest('div').click()`
- **Portal shows duplicate cards** — the extractor deduplicates by `disc["nome"]`
- **NEXUS modal** — MUI modal appears on page load and blocks interaction; remove via JS `el.remove()` (more reliable than trying to click close)

## How the schedule extraction works

1. Navigate to `portal.espm.br/my-courses`
2. Remove NEXUS modal (MUI dialog) via JS
3. Find active course card `a[href*="my-courses/student-"]`
4. Navigate to course page (direct goto, not click — avoids new-tab issue)
5. Activate grid view via Lucide icon click (with JS fallback)
6. Wait 2 seconds for cards to render
7. Expand all collapse boxes
8. Extract text nodes from each `collapseBox` via JS DOM traversal
9. Parse each card: identify professor (heuristic), time chips, labels
10. Map to Coffee schema: nome, professor, horario, semestre

## Session reuse

The encrypted `storage_state` allows reusing a session without re-authenticating.
On subsequent requests:
1. Decrypt stored session
2. Create browser context with `storage_state`
3. Navigate to `my-courses`
4. If URL is still `portal.espm.br` → session valid, reuse
5. If redirected to Microsoft login → session expired, do fresh login

## iOS integration

The iOS app needs a new screen (post-onboarding or in settings):
- "Conectar ao portal ESPM"
- Email and password fields (ESPM portal credentials, NOT Coffee credentials)
- Button "Conectar e importar disciplinas"
- Loading state showing logs in real-time (optional: can just show spinner)
- On success: navigate to disciplinas list (which now has real data)

This replaces the `POST /api/v1/disciplinas/seed` development endpoint from Prompt 2.
