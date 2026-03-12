"""
Canvas ESPM - Scraper Completo
Pega dados do aluno, disciplinas e baixa todos os PDFs/PPTXs de todos os cursos.
"""

import os
import sys
import json
import asyncio
import requests
from datetime import datetime
from urllib.parse import unquote_plus
from concurrent.futures import ThreadPoolExecutor, as_completed


# ── Helpers estáticos ─────────────────────────────────────────
def _limpar_nome_disciplina(nome_completo):
    if " - " in nome_completo:
        partes = nome_completo.split(" - ", 1)
        return partes[0].strip(), partes[1].strip()
    if "-" in nome_completo:
        partes = nome_completo.split("-", 1)
        return partes[0].strip(), partes[1].strip()
    return "", nome_completo


def _nome_seguro(nome):
    for ch in '<>:"/\\|?*':
        nome = nome.replace(ch, "_")
    return nome.strip()


# ── Classe principal ──────────────────────────────────────────
class CanvasScraper:
    EXTENSOES_ACEITAS = {".pdf", ".pptx"}
    NOMES_IGNORADOS = [
        "contrato", "pea", "combinados", "programa",
        "codigo", "código", "calendario", "calendário", "grade",
    ]
    MAX_WORKERS = 4

    def __init__(
        self,
        token: str = None,
        canvas_url: str = "https://canvas.espm.br",
        export_dir: str = None,
        token_file: str = None,
        email: str = None,
        password: str = None,
    ):
        self.canvas_url = canvas_url
        base = os.path.dirname(os.path.abspath(__file__))
        self.export_dir = export_dir or os.path.join(base, "canvas_export")
        self.token_file = token_file or os.path.join(base, "canvas_token.json")
        self._email = email
        self._password = password
        self.token = token or self._load_or_generate_token()
        self.headers = {"Authorization": f"Bearer {self.token}"}

    # ── Token ─────────────────────────────────────────────────
    def _load_or_generate_token(self) -> str:
        if os.path.exists(self.token_file):
            with open(self.token_file) as f:
                data = json.load(f)
            expires_at = datetime.fromisoformat(data["expires_at"])
            if expires_at > datetime.now():
                print(f"🔑 Token carregado (expira em {expires_at.strftime('%d/%m/%Y')})")
                return data["token"]
            print("⚠️  Token expirado, gerando novo...")
        else:
            print("⚠️  Token não encontrado, gerando novo...")

        email = self._email or os.environ.get("CANVAS_EMAIL", "")
        password = self._password or os.environ.get("CANVAS_PASSWORD", "")
        if not email or not password:
            print("❌ Defina CANVAS_EMAIL e CANVAS_PASSWORD para gerar o token")
            sys.exit(1)

        from generate_canvas_token import generate_token
        result = asyncio.run(generate_token(email=email, password=password))
        return result["token"]

    # ── API ───────────────────────────────────────────────────
    def api_get(self, endpoint, params=None):
        if params is None:
            params = {}
        params["per_page"] = 100
        url = f"{self.canvas_url}/api/v1/{endpoint}"
        all_results = []

        while url:
            resp = requests.get(url, headers=self.headers, params=params)
            resp.raise_for_status()
            data = resp.json()
            if isinstance(data, list):
                all_results.extend(data)
            else:
                return data

            link = resp.headers.get("Link", "")
            url = None
            params = {}
            for part in link.split(","):
                if 'rel="next"' in part:
                    url = part.split(";")[0].strip().strip("<>")
                    break

        return all_results

    # ── Download ──────────────────────────────────────────────
    def _download_one(self, file_url, destino):
        try:
            file_resp = requests.get(file_url, headers=self.headers)
            file_resp.raise_for_status()
            download_url = file_resp.json().get("url")
            if not download_url:
                return destino, False, "Sem URL"

            dl = requests.get(download_url, headers=self.headers, stream=True)
            dl.raise_for_status()
            with open(destino, "wb") as f:
                for chunk in dl.iter_content(chunk_size=8192):
                    f.write(chunk)

            size_kb = os.path.getsize(destino) / 1024
            return destino, True, f"{size_kb:.0f} KB"
        except Exception as e:
            return destino, False, str(e)

    def _download_batch(self, downloads):
        """Baixa lista de (file_url, destino) em paralelo."""
        if not downloads:
            return
        with ThreadPoolExecutor(max_workers=self.MAX_WORKERS) as pool:
            futures = {
                pool.submit(self._download_one, url, dest): dest
                for url, dest in downloads
            }
            for future in as_completed(futures):
                dest, ok, info = future.result()
                nome = os.path.basename(dest)
                if ok:
                    print(f"      ✅ {nome} ({info})")
                else:
                    print(f"      ❌ {nome}: {info}")

    # ── Scrape ────────────────────────────────────────────────
    def run(self):
        os.makedirs(self.export_dir, exist_ok=True)

        print("👤 Buscando dados do aluno...")
        user = self.api_get("users/self/profile")
        nome_aluno = user.get("name", "Desconhecido")
        print(f"   Nome: {nome_aluno}\n")

        print("📚 Buscando cursos...")
        cursos = self.api_get("courses", params={"include[]": "term"})
        cursos_validos = [c for c in cursos if isinstance(c, dict) and c.get("name")]
        print(f"   {len(cursos_validos)} cursos encontrados\n")

        resultado = {
            "aluno": nome_aluno,
            "total_cursos": len(cursos_validos),
            "cursos": [],
        }
        total_arquivos = 0

        for curso in cursos_validos:
            course_id = curso["id"]
            nome_completo = curso["name"]
            turma, disciplina = _limpar_nome_disciplina(nome_completo)
            codigo = curso.get("course_code", "")

            term = curso.get("term", {})
            semestre = term.get("name", "Não informado") if term else "Não informado"

            print(f"{'='*60}")
            print(f"📖 {disciplina}")
            print(f"   Código: {codigo} | ID: {course_id}")
            print(f"   🏷️  Turma: {turma}")
            print(f"   📅 Semestre: {semestre}")

            pasta_disciplina = os.path.join(self.export_dir, _nome_seguro(disciplina))
            os.makedirs(pasta_disciplina, exist_ok=True)

            curso_info = {
                "id": course_id,
                "disciplina": disciplina,
                "codigo": codigo,
                "turma": turma,
                "semestre": semestre,
                "arquivos": [],
            }

            try:
                modulos = self.api_get(f"courses/{course_id}/modules")
            except Exception:
                print(f"   ⚠️  Não foi possível acessar módulos")
                resultado["cursos"].append(curso_info)
                continue

            if not modulos:
                print(f"   (sem módulos)")
                resultado["cursos"].append(curso_info)
                continue

            print(f"   📦 {len(modulos)} módulos")

            for mod in modulos:
                mod_id = mod["id"]
                mod_nome = mod.get("name", "?")

                try:
                    itens = self.api_get(f"courses/{course_id}/modules/{mod_id}/items")
                except Exception:
                    continue

                if not itens:
                    continue

                arquivos = [it for it in itens if it.get("type") == "File"]
                if not arquivos:
                    continue

                arquivos_validos = []
                for arq in arquivos:
                    titulo = arq.get("title", "")
                    ext = os.path.splitext(titulo)[1].lower()
                    if ext not in self.EXTENSOES_ACEITAS:
                        continue
                    titulo_lower = titulo.lower()
                    if any(p in titulo_lower for p in self.NOMES_IGNORADOS):
                        continue
                    arquivos_validos.append(arq)

                if not arquivos_validos:
                    continue

                print(f"   📂 {mod_nome} → {len(arquivos_validos)} arquivo(s)")

                # Separar: já existentes vs pendentes de download
                pendentes = []
                for arq in arquivos_validos:
                    titulo = arq["title"]
                    file_api_url = arq.get("url", "")
                    nome_arquivo = _nome_seguro(unquote_plus(titulo))
                    destino = os.path.join(pasta_disciplina, nome_arquivo)

                    if os.path.exists(destino):
                        print(f"      ⏭️  {titulo}")
                    else:
                        print(f"      📄 {titulo}")
                        pendentes.append((file_api_url, destino))

                    curso_info["arquivos"].append(nome_arquivo)
                    total_arquivos += 1

                # Download paralelo dos pendentes
                self._download_batch(pendentes)

            resultado["cursos"].append(curso_info)

        json_path = os.path.join(self.export_dir, "resumo_export.json")
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(resultado, f, indent=2, ensure_ascii=False)

        print(f"\n{'='*60}")
        print(f"🎉 EXPORTAÇÃO COMPLETA!")
        print(f"   👤 Aluno: {nome_aluno}")
        print(f"   📚 Cursos: {len(cursos_validos)}")
        print(f"   📄 Arquivos (PDFs/PPTXs): {total_arquivos}")
        print(f"   📁 Pasta: {self.export_dir}")
        print(f"   📋 Resumo: {json_path}")

        return resultado


# ── Main ──────────────────────────────────────────────────────
if __name__ == "__main__":
    scraper = CanvasScraper()
    scraper.run()
