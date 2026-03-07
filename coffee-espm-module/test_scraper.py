"""
Standalone test: verifica que authenticator + extractor funcionam.
Uso: python test_scraper.py <email@espm.br> <senha>

Requer:
  pip install playwright structlog cryptography
  playwright install chromium
"""
import asyncio
import sys
import json
from auth.authenticator import ESPMAuthenticator
from schedule.extractor import ScheduleExtractor


async def main(login: str, password: str):
    # Gerar chave temporária para teste
    from cryptography.fernet import Fernet
    test_key = Fernet.generate_key().decode()

    print(f"[1/3] Fazendo login no portal ESPM com {login}...")
    auth = ESPMAuthenticator(test_key)
    extractor = ScheduleExtractor()

    # Login + extração em uma única janela
    result = await auth.login_and_extract(login, password, extractor)

    print(f"\n[2/3] Logs do processo:")
    for log in result.get("logs", []):
        print(f"  → {log}")

    disciplines = result.get("disciplines", [])
    print(f"\n[3/3] Disciplinas extraídas: {len(disciplines)}")

    for i, disc in enumerate(disciplines, 1):
        print(f"\n  ── Disciplina {i} ──")
        print(f"  nome:      {disc.get('nome')}")
        print(f"  professor: {disc.get('professor')}")
        print(f"  horario:   {disc.get('horario')}")
        print(f"  semestre:  {disc.get('semestre')}")
        if disc.get("days"):
            print(f"  dias:      {disc.get('days')}")
        if disc.get("period_start"):
            print(f"  período:   {disc.get('period_start')} → {disc.get('period_end')}")

    # Salvar resultado completo
    output_file = "scraper_test_output.json"
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(disciplines, f, ensure_ascii=False, indent=2, default=str)
    print(f"\n✓ Resultado salvo em {output_file}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Uso: python test_scraper.py <email@espm.br> <senha>")
        sys.exit(1)
    asyncio.run(main(sys.argv[1], sys.argv[2]))
