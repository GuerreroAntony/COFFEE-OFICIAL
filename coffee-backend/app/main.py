from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.database import close_pool, get_pool
from app.modules.espm import router as espm_router
from app.routers import auth, chat, devices, disciplinas, gravacoes, health, materiais, notificacoes, profile, referral, repositorios, resumos, settings, subscription


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
app.include_router(materiais.disc_router)
app.include_router(repositorios.router)
app.include_router(notificacoes.router)
app.include_router(profile.router)
app.include_router(subscription.router)
app.include_router(referral.router)
app.include_router(settings.router)
app.include_router(espm_router.router)


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException) -> JSONResponse:
    detail = exc.detail
    if isinstance(detail, dict) and "error" in detail:
        return JSONResponse(status_code=exc.status_code, content=detail)
    return JSONResponse(
        status_code=exc.status_code,
        content={"data": None, "error": "ERROR", "message": str(detail)},
    )


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(
        status_code=500,
        content={"data": None, "error": "INTERNAL_ERROR", "message": "Erro interno do servidor"},
    )
