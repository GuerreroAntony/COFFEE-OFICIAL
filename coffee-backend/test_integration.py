#!/usr/bin/env python3
"""
Coffee v3.1 — Full Integration Test Suite
Runs against local server at http://127.0.0.1:8000
"""
import asyncio
import httpx
import time
import json
import sys

BASE = "http://127.0.0.1:8000/api/v1"
HEALTH = "http://127.0.0.1:8000/health"
ESPM_LOGIN = "leonardo.millan@acad.espm.br"
ESPM_PASS = "03085000"

PASS = 0
FAIL = 0
SKIP = 0
ERRORS = []

def ok(msg):
    global PASS
    PASS += 1
    print(f"  ✅ {msg}")

def fail(msg):
    global FAIL
    FAIL += 1
    ERRORS.append(msg)
    print(f"  ❌ {msg}")

def skip(msg):
    global SKIP
    SKIP += 1
    print(f"  ⏭️  {msg}")


async def run_tests():
    global PASS, FAIL, SKIP

    async with httpx.AsyncClient(timeout=120.0) as c:
        print("═══════════════════════════════════════════")
        print("  COFFEE v3.1 — Integration Test Suite")
        print("═══════════════════════════════════════════")
        print()

        # ── 1. Health ──
        print("▶ 1. Health")
        r = await c.get(HEALTH)
        if r.status_code == 200 and r.json()["data"]["status"] == "ok":
            ok("GET /health → 200")
        else:
            fail(f"GET /health → {r.status_code}")

        # ── 2. Auth: Signup ──
        print("\n▶ 2. Auth")
        email = f"test_{int(time.time())}@espm.br"
        password = "TestPass123abc"

        r = await c.post(f"{BASE}/auth/signup", json={
            "nome": "Test User",
            "email": email,
            "password": password
        })
        d = r.json()
        token = d.get("data", {}).get("token")
        if token:
            ok(f"POST /auth/signup → token received")
        else:
            fail(f"POST /auth/signup → {d}")
            print("CANNOT CONTINUE WITHOUT TOKEN")
            return

        headers = {"Authorization": f"Bearer {token}"}

        # ── 3. Auth: Login ──
        r = await c.post(f"{BASE}/auth/login", json={"email": email, "password": password})
        d = r.json()
        if d.get("data", {}).get("token"):
            ok("POST /auth/login → token")
        else:
            fail(f"POST /auth/login → {d}")

        # ── 4. Auth: Me ──
        r = await c.get(f"{BASE}/auth/me", headers=headers)
        d = r.json()
        user_id = d.get("data", {}).get("id")
        if user_id:
            ok(f"GET /auth/me → user_id={user_id[:8]}...")
        else:
            fail(f"GET /auth/me → {d}")

        # ── 5. Auth: Refresh ──
        r = await c.post(f"{BASE}/auth/refresh", headers=headers)
        d = r.json()
        if d.get("data", {}).get("token"):
            ok("POST /auth/refresh → new token")
        else:
            fail(f"POST /auth/refresh → {d}")

        # ── 6. Auth: Forgot Password ──
        r = await c.post(f"{BASE}/auth/forgot-password", json={"email": email})
        if r.status_code == 200:
            ok("POST /auth/forgot-password → 200")
        else:
            fail(f"POST /auth/forgot-password → {r.status_code}")

        # ── 7. Profile ──
        print("\n▶ 3. Profile")
        r = await c.get(f"{BASE}/profile", headers=headers)
        d = r.json()
        usage = d.get("data", {}).get("usage", {})
        if "questions_remaining" in usage:
            ok("GET /profile → questions_remaining present")
        else:
            fail(f"GET /profile → missing questions_remaining: {d}")

        # ── 8. Profile Update ──
        r = await c.patch(f"{BASE}/profile", headers=headers, json={"nome": "Updated Name"})
        d = r.json()
        if d.get("data", {}).get("nome") == "Updated Name":
            ok("PATCH /profile → name updated")
        else:
            fail(f"PATCH /profile → {d}")

        # ── 9. Settings ──
        print("\n▶ 4. Settings")
        r = await c.get(f"{BASE}/settings", headers=headers)
        d = r.json()
        if "espm_connected" in d.get("data", {}):
            ok("GET /settings → espm_connected present")
        else:
            fail(f"GET /settings → {d}")

        # ── 10. Subscription ──
        print("\n▶ 5. Subscription")
        r = await c.get(f"{BASE}/subscription/status", headers=headers)
        d = r.json()
        if "plano" in d.get("data", {}):
            ok("GET /subscription/status → plano present")
        else:
            fail(f"GET /subscription/status → {d}")

        # ── 11. Gift Codes ──
        print("\n▶ 6. Gift Codes")
        r = await c.get(f"{BASE}/gift-codes", headers=headers)
        d = r.json()
        if d.get("error") is None:
            ok("GET /gift-codes → OK")
        else:
            fail(f"GET /gift-codes → {d}")

        r = await c.post(f"{BASE}/gift-codes/validate", headers=headers, json={"code": "INVALID1"})
        d = r.json()
        if d.get("data", {}).get("valid") is False:
            ok("POST /gift-codes/validate invalid → valid=false")
        else:
            fail(f"POST /gift-codes/validate → {d}")

        # ── 12. Devices ──
        print("\n▶ 7. Devices")
        r = await c.post(f"{BASE}/devices", headers=headers, json={"token": "test_fcm_123", "platform": "ios"})
        if r.status_code == 201:
            ok("POST /devices → 201")
        else:
            fail(f"POST /devices → {r.status_code} {r.text}")

        r = await c.delete(f"{BASE}/devices/test_fcm_123", headers=headers)
        if r.status_code == 200:
            ok("DELETE /devices/{{token}} → 200")
        else:
            fail(f"DELETE /devices/{{token}} → {r.status_code}")

        # ── 13. Notifications ──
        print("\n▶ 8. Notifications")
        r = await c.get(f"{BASE}/notificacoes", headers=headers)
        d = r.json()
        if d.get("error") is None:
            ok("GET /notificacoes → OK")
        else:
            fail(f"GET /notificacoes → {d}")

        # ── 14. Disciplinas (empty) ──
        print("\n▶ 9. Disciplinas (before ESPM)")
        r = await c.get(f"{BASE}/disciplinas", headers=headers)
        d = r.json()
        if d.get("error") is None:
            ok("GET /disciplinas → OK (empty)")
        else:
            fail(f"GET /disciplinas → {d}")

        # ── 15. Repositórios ──
        print("\n▶ 10. Repositórios")
        r = await c.post(f"{BASE}/repositorios", headers=headers, json={"nome": "Test Repo", "icone": "📚"})
        d = r.json()
        repo_id = d.get("data", {}).get("id")
        if repo_id:
            ok(f"POST /repositorios → id={repo_id[:8]}...")
        else:
            fail(f"POST /repositorios → {d}")

        r = await c.get(f"{BASE}/repositorios", headers=headers)
        d = r.json()
        if len(d.get("data", [])) >= 1:
            ok("GET /repositorios → ≥1 item")
        else:
            fail(f"GET /repositorios → {d}")

        r = await c.patch(f"{BASE}/repositorios/{repo_id}", headers=headers, json={"nome": "Renamed Repo"})
        d = r.json()
        if d.get("data", {}).get("nome") == "Renamed Repo":
            ok("PATCH /repositorios/{{id}} → renamed")
        else:
            fail(f"PATCH /repositorios/{{id}} → {d}")

        # ── 16. ESPM Connect (real credentials) ──
        print("\n▶ 11. ESPM Connect (real credentials — may take 30-60s)")
        r = await c.post(f"{BASE}/espm/connect", headers=headers, json={
            "matricula": ESPM_LOGIN,
            "password": ESPM_PASS
        }, timeout=180.0)
        try:
            d = r.json()
        except Exception:
            d = {"raw": r.text[:300], "status": r.status_code}
        data = d.get("data") or {}
        espm_ok = data.get("status") == "connected" if isinstance(data, dict) else False
        espm_synced = data.get("disciplinas_found", 0) if isinstance(data, dict) else 0
        espm_not_configured = (
            "not configured" in d.get("message", "")
            or r.status_code == 503
            or r.status_code == 504  # Canvas Playwright timeout (infra dependency)
        )
        if espm_ok:
            ok(f"POST /espm/connect → status=connected, disciplinas_found={espm_synced}")
        elif espm_not_configured:
            skip(f"POST /espm/connect → Canvas/Playwright unavailable locally ({r.status_code})")
        else:
            fail(f"POST /espm/connect → {r.status_code}: {json.dumps(d, default=str)[:300]}")

        # ── 17. ESPM Status ──
        r = await c.get(f"{BASE}/espm/status", headers=headers)
        d = r.json()
        if espm_not_configured:
            if d.get("error") is None:
                ok("GET /espm/status → OK (ESPM not configured locally)")
            else:
                fail(f"GET /espm/status → {d}")
        elif d.get("data", {}).get("connected"):
            status_data = d.get("data", {})
            has_matricula = "matricula" in status_data
            ok(f"GET /espm/status → connected=true, matricula={'✓' if has_matricula else '✗'}")
        else:
            fail(f"GET /espm/status → {d}")

        # ── 18. Disciplinas (after ESPM) ──
        print("\n▶ 12. Disciplinas (after ESPM)")
        disc_id = None
        if espm_not_configured:
            skip("GET /disciplinas (after ESPM) — ESPM not configured locally")
            skip("GET /disciplinas/{{id}} — ESPM not configured locally")
        else:
            r = await c.get(f"{BASE}/disciplinas", headers=headers)
            d = r.json()
            discs = d.get("data", [])
            disc_id = discs[0]["id"] if discs else None
            if disc_id:
                ok(f"GET /disciplinas → {len(discs)} disciplinas")
            else:
                skip("GET /disciplinas → No disciplinas found")

            if disc_id:
                r = await c.get(f"{BASE}/disciplinas/{disc_id}", headers=headers)
                d = r.json()
                # Contract v3.1: flat object, same shape as list item
                disc_data = d.get("data", {})
                if disc_data.get("id"):
                    ok("GET /disciplinas/{{id}} → detail OK (flat)")
                else:
                    fail(f"GET /disciplinas/{{id}} → {d}")
            else:
                skip("GET /disciplinas/{{id}} — skipped")

        # ── 19. Gravações ──
        print("\n▶ 13. Gravações")
        transcription_text = (
            "Esta é uma transcrição de teste para verificar o pipeline completo de gravações. "
            "O professor falou sobre inteligência artificial e machine learning, explicando como "
            "redes neurais funcionam e como podemos aplicar deep learning em problemas reais. "
            "Também discutimos sobre processamento de linguagem natural e como modelos como GPT "
            "e Claude revolucionaram a forma como interagimos com computadores. A aula cobriu "
            "tópicos como tokenização, embeddings, attention mechanisms e transformers. "
            "Além disso, foi apresentada a arquitetura de retrieval augmented generation (RAG) "
            "que permite combinar busca vetorial com geração de texto para respostas mais precisas."
        )

        r = await c.post(f"{BASE}/gravacoes", headers=headers, json={
            "source_type": "repositorio",
            "source_id": repo_id,
            "transcription": transcription_text,
            "date": "2026-03-13",
            "duration_seconds": 3600
        })
        d = r.json()
        grav_id = d.get("data", {}).get("id")
        if grav_id:
            ok(f"POST /gravacoes → id={grav_id[:8]}...")
        else:
            fail(f"POST /gravacoes → {d}")

        if grav_id:
            # List
            r = await c.get(f"{BASE}/gravacoes", headers=headers, params={
                "source_type": "repositorio", "source_id": repo_id
            })
            d = r.json()
            if len(d.get("data", [])) >= 1:
                ok("GET /gravacoes (list) → ≥1")
            else:
                fail(f"GET /gravacoes (list) → {d}")

            # Detail
            r = await c.get(f"{BASE}/gravacoes/{grav_id}", headers=headers)
            d = r.json()
            if d.get("data", {}).get("id"):
                ok("GET /gravacoes/{{id}} → detail OK")
            else:
                fail(f"GET /gravacoes/{{id}} → {d}")

            # Move
            if disc_id:
                r = await c.patch(f"{BASE}/gravacoes/{grav_id}", headers=headers, json={
                    "source_type": "disciplina", "source_id": disc_id
                })
                d = r.json()
                if d.get("data", {}).get("source_type") == "disciplina":
                    ok("PATCH /gravacoes/{{id}} → moved to disciplina")
                else:
                    fail(f"PATCH /gravacoes/{{id}} → {d}")

                # Move back
                await c.patch(f"{BASE}/gravacoes/{grav_id}", headers=headers, json={
                    "source_type": "repositorio", "source_id": repo_id
                })
        else:
            fail("Skipping gravacoes list/detail/move — creation failed")

        # ── 20. Wait for background tasks ──
        print("\n▶ 14. Waiting for background tasks (summary + mindmap)...")
        status = "unknown"
        has_mm = False
        has_summary = False
        if grav_id:
            for i in range(15):
                await asyncio.sleep(5)
                r = await c.get(f"{BASE}/gravacoes/{grav_id}", headers=headers)
                d = r.json().get("data", {})
                status = d.get("status", "unknown")
                has_summary = bool(d.get("short_summary"))
                has_mm = bool(d.get("mind_map"))
                print(f"  ⏳ {(i+1)*5}s — status={status}, summary={'✓' if has_summary else '✗'}, mind_map={'✓' if has_mm else '✗'}")
                if status == "ready":
                    break

            if status == "ready":
                ok("Background tasks → status=ready")
            else:
                fail(f"Background tasks → status={status} after 75s")

            if has_summary:
                ok("Summary generated")
            else:
                fail("Summary not generated")

            if has_mm:
                ok("Mind map generated")
            else:
                fail("Mind map not generated (may be OK if OpenAI quota)")
        else:
            skip("Background tasks — no gravação to monitor")

        # ── 21. PDF Downloads ──
        print("\n▶ 15. PDF Downloads")
        if has_summary and grav_id:
            r = await c.get(f"{BASE}/gravacoes/{grav_id}/pdf/resumo", headers=headers)
            if r.status_code == 200 and len(r.content) > 100:
                ok(f"GET /gravacoes/{{id}}/pdf/resumo → 200 ({len(r.content)} bytes)")
            else:
                fail(f"GET /gravacoes/{{id}}/pdf/resumo → {r.status_code}")
        else:
            skip("PDF resumo — no summary or no gravação")

        if has_mm and grav_id:
            r = await c.get(f"{BASE}/gravacoes/{grav_id}/pdf/mindmap", headers=headers)
            if r.status_code == 200 and len(r.content) > 100:
                ok(f"GET /gravacoes/{{id}}/pdf/mindmap → 200 ({len(r.content)} bytes)")
            else:
                fail(f"GET /gravacoes/{{id}}/pdf/mindmap → {r.status_code}")
        else:
            skip("PDF mindmap — no mind_map or no gravação")

        # ── 22. Chat ──
        print("\n▶ 16. Chat")
        r = await c.post(f"{BASE}/chats", headers=headers, json={
            "source_type": "repositorio", "source_id": repo_id
        })
        d = r.json()
        chat_id = d.get("data", {}).get("id")
        if chat_id:
            ok(f"POST /chats → id={chat_id[:8]}...")
        else:
            fail(f"POST /chats → {d}")

        r = await c.get(f"{BASE}/chats", headers=headers)
        d = r.json()
        if len(d.get("data", [])) >= 1:
            ok("GET /chats → ≥1")
        else:
            fail(f"GET /chats → {d}")

        # Send message (espresso mode — SSE)
        r = await c.post(f"{BASE}/chats/{chat_id}/messages", headers=headers, json={
            "text": "O que foi discutido sobre IA?",
            "mode": "espresso"
        }, timeout=60.0)
        if r.status_code == 200:
            ok("POST /chats/{{id}}/messages (espresso) → 200 SSE")
        else:
            fail(f"POST /chats/{{id}}/messages (espresso) → {r.status_code} {r.text[:200]}")

        # Get messages
        r = await c.get(f"{BASE}/chats/{chat_id}/messages", headers=headers)
        d = r.json()
        msg_count = len(d.get("data", []))
        if msg_count >= 1:
            ok(f"GET /chats/{{id}}/messages → {msg_count} messages")
        else:
            fail(f"GET /chats/{{id}}/messages → {d}")

        # ── 23. Compartilhamentos ──
        print("\n▶ 17. Compartilhamentos")
        r = await c.get(f"{BASE}/compartilhamentos/received", headers=headers)
        d = r.json()
        if d.get("error") is None:
            ok("GET /compartilhamentos/received → OK")
        else:
            fail(f"GET /compartilhamentos/received → {d}")

        # ── 24. ESPM Disconnect ──
        print("\n▶ 18. ESPM Disconnect")
        r = await c.post(f"{BASE}/espm/disconnect", headers=headers)
        d = r.json()
        if d.get("error") is None:
            ok("POST /espm/disconnect → OK")
        else:
            fail(f"POST /espm/disconnect → {d}")

        r = await c.get(f"{BASE}/espm/status", headers=headers)
        d = r.json()
        if d.get("data", {}).get("connected") is False:
            ok("GET /espm/status → connected=false (after disconnect)")
        else:
            fail(f"GET /espm/status after disconnect → {d}")

        # ── 25. Auth: Logout ──
        print("\n▶ 19. Auth Logout")
        r = await c.post(f"{BASE}/auth/logout", headers=headers, json={})
        if r.status_code in (200, 204):
            ok(f"POST /auth/logout → {r.status_code}")
        else:
            fail(f"POST /auth/logout → {r.status_code}")

        # ── 26. Support Contact ──
        print("\n▶ 20. Support Contact")
        # Re-login since we logged out
        r = await c.post(f"{BASE}/auth/login", json={"email": email, "password": password})
        d = r.json()
        token = d.get("data", {}).get("token")
        headers = {"Authorization": f"Bearer {token}"}

        r = await c.post(f"{BASE}/support/contact", headers=headers, json={
            "subject": "Test", "message": "Integration test"
        })
        d = r.json()
        if d.get("error") is None:
            ok("POST /support/contact → OK")
        else:
            fail(f"POST /support/contact → {d}")

        # ── 27. Account Delete ──
        print("\n▶ 21. Account Delete (LGPD)")
        r = await c.request("DELETE", f"{BASE}/account", headers=headers, json={"confirm": True})
        d = r.json()
        if d.get("error") is None:
            ok("DELETE /account → OK")
        else:
            fail(f"DELETE /account → {d}")

        # Verify deleted
        r = await c.get(f"{BASE}/auth/me", headers=headers)
        if r.status_code == 401:
            ok("GET /auth/me after delete → 401 (account gone)")
        else:
            fail(f"GET /auth/me after delete → {r.status_code} (expected 401)")

        # ── Summary ──
        print()
        print("═══════════════════════════════════════════")
        print(f"  RESULTS: ✅ {PASS} passed | ❌ {FAIL} failed | ⏭️  {SKIP} skipped")
        print("═══════════════════════════════════════════")
        if ERRORS:
            print()
            print("  FAILURES:")
            for e in ERRORS:
                print(f"    ❌ {e}")


if __name__ == "__main__":
    asyncio.run(run_tests())
