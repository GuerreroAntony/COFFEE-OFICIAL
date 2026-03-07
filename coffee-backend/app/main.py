from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.database import close_pool, get_pool
from app.modules.espm import router as espm_router
from app.routers import auth, chat, devices, disciplinas, gravacoes, health, materiais, notificacoes, resumos


@asynccontextmanager
async def lifespan(app: FastAPI):
    await get_pool()
    yield
    await close_pool()


app = FastAPI(
    title="Coffee API",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(disciplinas.router)
app.include_router(gravacoes.router)
app.include_router(resumos.router)
app.include_router(chat.router)
app.include_router(devices.router)
app.include_router(materiais.router)
app.include_router(notificacoes.router)
app.include_router(espm_router.router)


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(
        status_code=500,
        content={"success": False, "error": "Internal server error", "detail": str(exc)},
    )
