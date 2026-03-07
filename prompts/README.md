# COFFEE — Cronograma de Prompts para Reestruturação do Backend

> 11 prompts, executados em sequência. Cada prompt é autossuficiente quando combinado com o CONTEXT.md.

---

## Como usar com Claude Code

1. Abra o projeto `COFFEE-OFICIAL` no Claude Code
2. Na primeira sessão, passe o arquivo `CONTEXT.md` como contexto permanente
3. Execute cada prompt na ordem (00 → 10)
4. Ao final de cada prompt, verifique os itens da seção "Verificação"
5. Só avance pro próximo prompt quando todos os itens estiverem OK

---

## Visão Geral do Cronograma

| # | Prompt | O que faz | Arquivos | Estimativa |
|---|--------|-----------|----------|------------|
| 00 | Schema Consolidation | Consolida 7 migrations em 1. Cria 5 tabelas novas. Colapsa transcricoes+resumos em gravacoes. | sql/ | 30min |
| 01 | Core Services | Cria embedding_service (gerar/remover), summary_service (background), adapta openai/push. | services/ | 45min |
| 02 | Gravações Rewrite | Reescreve gravacoes.py do zero. Recebe texto (não áudio). Auto-embed + auto-resumo. Media upload. | routers/gravacoes, schemas/gravacoes | 1h |
| 03 | Repositórios | CRUD novo de repositórios. 3 endpoints. | routers/repositorios, schemas/repositorios | 20min |
| 04 | Chat/RAG | Adapta pra source_type/source_id. Fixa fontes citadas. Limite de perguntas. RAG pra repos. | routers/chat, schemas/chat | 1h |
| 05 | Materiais | Toggle gera/remove embeddings. Upload manual. Cooldown 4h. | routers/materiais, schemas/materiais | 40min |
| 06 | Auth Expand | Referral no signup, logout, forgot-password, refresh, response expandido. | routers/auth, schemas/auth | 45min |
| 07 | Profile+Sub+Ref+Settings | 4 routers novos. Profile com usage, subscription, referral, settings. | 4 routers + 4 schemas | 1h |
| 08 | ESPM + Disciplinas | Rename /login→/connect, GET /status, padronizar DB. Limpar disciplinas. | modules/espm, routers/disciplinas | 40min |
| 09 | Envelope Padronizado | Padroniza TODOS os responses pra { data, error, message }. Códigos de erro. | todos os routers | 1h |
| 10 | Integração + Validação | Config, main.py, requirements, checklist de 40 endpoints. | config, main, requirements | 30min |

**Total estimado: ~8 horas de trabalho**

---

## Dependências entre Prompts

```
00 (Schema) ─────────────────────────────────────────→ TODOS dependem
01 (Services) ──────→ 02 (Gravações) ──→ 04 (Chat)
                  └──→ 05 (Materiais)
                  
03 (Repos) ─────────→ 04 (Chat) [suporte a repos no RAG]

06 (Auth) ──────────→ 07 (Profile/Sub/Ref)

08 (ESPM+Disc) ────→ independente

09 (Envelope) ──────→ depende de TODOS os anteriores
10 (Integração) ───→ último sempre
```

**Caminho crítico:** 00 → 01 → 02 → 04 → 09 → 10
(Esse é o fluxo que faz o core funcionar: gravar → embedar → IA responder)

---

## Arquivos neste diretório

```
claude-code-prompts/
├── CONTEXT.md                    ← Incluir em TODA sessão de Claude Code
├── 00_schema_consolidation.md    ← Prompt 00
├── 01_core_services.md           ← Prompt 01
├── 02_gravacoes_rewrite.md       ← Prompt 02
├── 03_repositorios.md            ← Prompt 03
├── 04_chat_rag.md                ← Prompt 04
├── 05_06_07_08_combined.md       ← Prompts 05-08 (agrupados por serem mais curtos)
├── 09_10_envelope_integration.md ← Prompts 09-10
└── README.md                     ← Este arquivo
```

---

## O que NÃO está coberto nestes prompts

1. **coffee-scraper/** — não é modificado. Funciona como está.
2. **Coffee/ (iOS)** — desenvolvido separadamente pelo sócio.
3. **Deploy no Railway** — feito manualmente após todos os prompts.
4. **Migration de dados existentes** — se há dados no banco atual, será necessário um script de migração separado (não coberto aqui pois os dados de dev podem ser descartados).
5. **Testes automatizados** — não cobertos. Recomendação: adicionar após MVP funcional.
