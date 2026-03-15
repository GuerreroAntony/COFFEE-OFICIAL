"""
ESPM Schedule Extractor — Stub for development.
Will be replaced with real Canvas-based extractor.
"""


class ScheduleExtractor:
    """Extracts schedule/disciplines from ESPM Canvas portal."""

    async def extract(self, page) -> list[dict]:
        """
        Extract disciplines from Canvas page.
        Returns list of dicts with keys: nome, turma, professor, horario, semestre, horarios
        """
        return []
