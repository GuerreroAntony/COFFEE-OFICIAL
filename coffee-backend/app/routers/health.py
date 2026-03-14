from datetime import datetime, timezone

from fastapi import APIRouter

from app.schemas.base import success_response

router = APIRouter(tags=["health"])


@router.get("/health")
async def health_check():
    return success_response({
        "status": "ok",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })
