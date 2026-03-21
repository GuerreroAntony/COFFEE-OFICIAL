# v2.5 — force update middleware
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from app.config import get_settings
from app.database import close_pool, get_pool
from app.modules.espm import router as espm_router
from app.routers import account, auth, calendario, chat, compartilhamentos, devices, disciplinas, gift_codes, gravacoes, health, materiais, notificacoes, profile, repositorios, settings, subscription


def _version_tuple(v: str) -> tuple[int, ...]:
    """Parse '1.2.3' → (1, 2, 3) for comparison."""
    try:
        return tuple(int(x) for x in v.strip().split("."))
    except (ValueError, AttributeError):
        return (0,)


class VersionCheckMiddleware(BaseHTTPMiddleware):
    """Block requests from outdated app versions (HTTP 426 Upgrade Required)."""

    async def dispatch(self, request: Request, call_next):
        # Skip version check for health endpoint (Railway monitoring)
        if request.url.path == "/health":
            return await call_next(request)

        app_version = request.headers.get("X-App-Version")

        # If header is absent, allow (backward compatibility)
        if app_version:
            cfg = get_settings()
            min_version = cfg.MIN_IOS_VERSION

            if _version_tuple(app_version) < _version_tuple(min_version):
                return JSONResponse(
                    status_code=426,
                    content={
                        "data": {
                            "min_version": min_version,
                            "store_url": cfg.APP_STORE_URL,
                        },
                        "error": "UPDATE_REQUIRED",
                        "message": "Atualize o Coffee para continuar usando",
                    },
                )

        return await call_next(request)


@asynccontextmanager
async def lifespan(app: FastAPI):
    import asyncio
    try:
        await get_pool()
    except Exception as exc:
        import logging
        logging.getLogger("coffee").warning("DB pool not ready at startup: %s", exc)

    # Start background processing loop for cloud transcription
    from app.services.processing_loop import start_processing_loop
    processing_task = asyncio.create_task(start_processing_loop())

    yield

    processing_task.cancel()
    try:
        await processing_task
    except asyncio.CancelledError:
        pass
    await close_pool()


app = FastAPI(
    title="Coffee API",
    version="3.1.0",
    lifespan=lifespan,
)

app.add_middleware(VersionCheckMiddleware)
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
app.include_router(chat.router)
app.include_router(devices.router)
app.include_router(materiais.router)
app.include_router(materiais.disc_router)
app.include_router(repositorios.router)
app.include_router(notificacoes.router)
app.include_router(profile.router)
app.include_router(subscription.router)
app.include_router(gift_codes.router)
app.include_router(settings.router)
app.include_router(account.router)
app.include_router(compartilhamentos.router)
app.include_router(calendario.router)
app.include_router(espm_router.router)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    """Return 422 validation errors in the standard envelope format."""
    errors = exc.errors()
    fields = [e.get("loc", ["?"])[-1] for e in errors]
    msgs = [e.get("msg", "") for e in errors]
    detail_msg = "; ".join(f"{f}: {m}" for f, m in zip(fields, msgs))
    return JSONResponse(
        status_code=422,
        content={"data": None, "error": "VALIDATION_ERROR", "message": detail_msg},
    )


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
