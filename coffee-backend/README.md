# Coffee Backend

Python FastAPI backend for the Coffee iOS academic notebook app.

## Stack
- **FastAPI** + **uvicorn** — API server
- **asyncpg** — async PostgreSQL (Supabase)
- **OpenAI** — GPT-4o (chat), GPT-4o-mini (summaries), text-embedding-3-small (RAG)
- **Playwright** — ESPM portal scraper
- **Railway** — hosting

## Setup

```bash
cp .env.example .env
# fill in .env values

pip install -r requirements.txt
uvicorn app.main:app --reload
```

## Structure

```
app/
├── main.py          # FastAPI app factory
├── config.py        # Environment settings
├── database.py      # asyncpg connection pool
├── dependencies.py  # Shared FastAPI dependencies
├── models/          # SQLAlchemy declarative models (future ORM use)
├── schemas/         # Pydantic request/response schemas
├── routers/         # API route handlers
├── services/        # Business logic (OpenAI, etc.)
└── utils/           # Security, embeddings
sql/
└── 000_foundation.sql  # Initial schema
```
