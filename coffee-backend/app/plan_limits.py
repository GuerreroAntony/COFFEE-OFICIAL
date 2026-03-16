"""
Plan limits helper — centralizes per-plan question limits and gift code counts.

Plans:
  - trial (Degustação): same limits as cafe_com_leite, 7 days free
  - cafe_com_leite: Espresso 75, Lungo 30, Cold Brew 15
  - black: Espresso unlimited, Lungo 100, Cold Brew 25
"""
from app.config import settings


def get_plan_limits(plano: str) -> dict:
    """Return question limits dict for a given plan.

    Returns:
        dict with keys "espresso", "lungo", "cold_brew".
        Value of -1 means unlimited.
    """
    if plano == "black":
        return {
            "espresso": settings.BLACK_ESPRESSO_LIMIT,
            "lungo": settings.BLACK_LUNGO_LIMIT,
            "cold_brew": settings.BLACK_COLD_BREW_LIMIT,
        }
    # trial + cafe_com_leite share the same limits
    return {
        "espresso": settings.CAFE_ESPRESSO_LIMIT,
        "lungo": settings.CAFE_LUNGO_LIMIT,
        "cold_brew": settings.CAFE_COLD_BREW_LIMIT,
    }


def get_gift_code_count(plano: str) -> int:
    """How many gift codes a subscriber gets."""
    if plano == "black":
        return 3
    if plano == "cafe_com_leite":
        return 2
    return 0


def is_paid_plan(plano: str) -> bool:
    """Check if plano is a paid plan (not trial or expired)."""
    return plano in ("cafe_com_leite", "black")
