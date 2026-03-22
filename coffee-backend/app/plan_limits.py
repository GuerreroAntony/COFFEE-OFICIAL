"""
Plan limits helper — centralizes per-plan budgets, gift codes, and plan checks.

Barista v2: single model (Sonnet 4), budget-based limits instead of per-mode counts.

Plans:
  - trial (Degustação): same budget as cafe_com_leite, 7 days free
  - cafe_com_leite: $1.75/cycle
  - black: $2.92/cycle
"""
from app.config import settings


def get_plan_budget(plano: str) -> float:
    """Return AI budget in USD for a given plan's 30-day cycle."""
    if plano == "black":
        return settings.BLACK_BUDGET_USD
    # trial + cafe_com_leite share the same budget
    return settings.CAFE_COM_LEITE_BUDGET_USD


# Legacy: keep old function for backward compatibility during transition
def get_plan_limits(plano: str) -> dict:
    """Legacy — return question limits dict (for old code paths).

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
