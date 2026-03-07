# Prompt 00 — Consolidação do Schema SQL

## Contexto
O banco atual tem 7 migrations (000-006) que foram empilhadas incrementalmente, gerando redundância e campos confusos. A tabela `disciplinas` tem 3 representações de horário (horario varchar, horarios JSONB, days text[] + time_start/end). A tabela `users` tem dois mecanismos de auth ESPM (encrypted_portal_session e encrypted_espm_password). As tabelas `transcricoes` e `resumos` existem separadas de `gravacoes` com relação 1:1:1 desnecessária. Faltam 5 tabelas novas.

## Arquivos a modificar
- `coffee-backend/sql/` — apagar todos os arquivos existentes (000-006)
- `coffee-backend/sql/000_v2_foundation.sql` — CRIAR (schema limpo e completo)

## Tarefa

Criar UM ÚNICO arquivo `000_v2_foundation.sql` que substitua TODAS as 7 migrations. Este arquivo deve:

### 1. Extensions
```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";
```

### 2. Tabela `users`
```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    plano VARCHAR(20) DEFAULT 'trial' CHECK (plano IN ('trial', 'premium', 'expired')),
    trial_end TIMESTAMP WITH TIME ZONE,
    espm_login VARCHAR(255),
    encrypted_espm_password BYTEA,
    referral_code VARCHAR(20) UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_referral ON users(referral_code);
```
**Removidos:** encrypted_portal_session (não usado no fluxo novo).
**Adicionados:** plano, trial_end, referral_code.

### 3. Tabela `disciplinas`
```sql
CREATE TABLE disciplinas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome VARCHAR(255) NOT NULL,
    turma VARCHAR(20),
    professor VARCHAR(255),
    horario VARCHAR(100),
    sala VARCHAR(50),
    semestre VARCHAR(20),
    horarios JSONB DEFAULT '[]',
    canvas_course_id INTEGER,
    last_scraped_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT disciplinas_nome_semestre_unique UNIQUE (nome, semestre)
);
CREATE INDEX idx_disciplinas_canvas ON disciplinas(canvas_course_id) WHERE canvas_course_id IS NOT NULL;
CREATE INDEX idx_disciplinas_scraped ON disciplinas(last_scraped_at NULLS FIRST);
```
**Removidos:** days text[], time_start, time_end, period_start, period_end, codigo_espm (redundante com canvas_course_id).
**Adicionado:** sala.
**Consolidado:** horario (varchar resumo legível) + horarios (JSONB detalhado) — são complementares, não redundantes.

### 4. Tabela `user_disciplinas`
```sql
CREATE TABLE user_disciplinas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    disciplina_id UUID NOT NULL REFERENCES disciplinas(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, disciplina_id)
);
CREATE INDEX idx_ud_user ON user_disciplinas(user_id);
CREATE INDEX idx_ud_disc ON user_disciplinas(disciplina_id);
```

### 5. Tabela `repositorios` [NOVA]
```sql
CREATE TABLE repositorios (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    nome VARCHAR(50) NOT NULL,
    icone VARCHAR(50) DEFAULT 'folder',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_repos_user ON repositorios(user_id);
```

### 6. Tabela `gravacoes` [REESTRUTURADA]
```sql
CREATE TABLE gravacoes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source_type VARCHAR(20) NOT NULL CHECK (source_type IN ('disciplina', 'repositorio')),
    source_id UUID NOT NULL,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    duration_seconds INTEGER DEFAULT 0,
    status VARCHAR(20) DEFAULT 'processing' CHECK (status IN ('processing', 'ready', 'error')),
    transcription TEXT,
    short_summary TEXT,
    full_summary JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_grav_user ON gravacoes(user_id);
CREATE INDEX idx_grav_source ON gravacoes(source_type, source_id);
CREATE INDEX idx_grav_status ON gravacoes(status);
```
**Colapsado:** transcricoes e resumos como campos inline. Não existem mais como tabelas separadas.
**Novo:** source_type + source_id substituem disciplina_id.
**Removidos:** data_aula renomeado pra date. Status simplificado (sem 'recording' — gravação é on-device).

### 7. Tabela `gravacao_media` [NOVA]
```sql
CREATE TABLE gravacao_media (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    gravacao_id UUID NOT NULL REFERENCES gravacoes(id) ON DELETE CASCADE,
    type VARCHAR(20) DEFAULT 'photo',
    label VARCHAR(255),
    timestamp_seconds INTEGER NOT NULL,
    url_storage TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_gmedia_grav ON gravacao_media(gravacao_id);
```

### 8. Tabela `materiais` (atualizada)
```sql
CREATE TABLE materiais (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    disciplina_id UUID NOT NULL REFERENCES disciplinas(id) ON DELETE CASCADE,
    tipo VARCHAR(20) CHECK (tipo IN ('pdf', 'slide', 'foto', 'outro')),
    nome VARCHAR(255) NOT NULL,
    url_storage TEXT,
    texto_extraido TEXT,
    fonte VARCHAR(20) DEFAULT 'canvas' CHECK (fonte IN ('canvas', 'manual')),
    canvas_file_id INTEGER,
    hash_arquivo VARCHAR(64),
    ai_enabled BOOLEAN DEFAULT true,
    size_bytes BIGINT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_mat_disc ON materiais(disciplina_id);
CREATE UNIQUE INDEX idx_mat_canvas ON materiais(canvas_file_id) WHERE canvas_file_id IS NOT NULL;
CREATE INDEX idx_mat_ai ON materiais(disciplina_id) WHERE ai_enabled = true;
```
**Adicionado:** size_bytes.
**Renomeado:** fonte='scraper' → fonte='canvas'.

### 9. Tabela `chats` (atualizada)
```sql
CREATE TABLE chats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source_type VARCHAR(20) NOT NULL CHECK (source_type IN ('disciplina', 'repositorio')),
    source_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_chats_user ON chats(user_id);
CREATE INDEX idx_chats_source ON chats(source_type, source_id);
```
**Removido:** modo (disciplina/interdisciplinar/geral) — substituído por source_type/source_id.
**Removido:** disciplina_id — substituído por source_type/source_id.
**Adicionado:** updated_at (pra ordenar conversas recentes).

### 10. Tabela `mensagens` (mantida)
```sql
CREATE TABLE mensagens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    role VARCHAR(10) NOT NULL CHECK (role IN ('user', 'assistant')),
    conteudo TEXT NOT NULL,
    fontes JSONB DEFAULT '[]',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_msg_chat ON mensagens(chat_id);
```
**Removido:** tokens_usados (desnecessário pro MVP).

### 11. Tabela `embeddings` (mantida)
```sql
CREATE TABLE embeddings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    disciplina_id UUID NOT NULL REFERENCES disciplinas(id) ON DELETE CASCADE,
    fonte_tipo VARCHAR(20) NOT NULL CHECK (fonte_tipo IN ('transcricao', 'material')),
    fonte_id UUID NOT NULL,
    chunk_index INTEGER NOT NULL,
    texto_chunk TEXT NOT NULL,
    embedding VECTOR(1536) NOT NULL,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_emb_disc ON embeddings(disciplina_id);
CREATE INDEX idx_emb_fonte ON embeddings(fonte_tipo, fonte_id);
CREATE INDEX idx_emb_vector ON embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
```
**Removido:** fonte_tipo 'resumo' (resumos não são embedados separadamente).

### 12. Tabela `device_tokens` (mantida)
```sql
CREATE TABLE device_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    fcm_token TEXT NOT NULL UNIQUE,
    platform VARCHAR(10) DEFAULT 'ios',
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_dt_user ON device_tokens(user_id);
```

### 13. Tabela `notificacoes` (mantida)
```sql
CREATE TABLE notificacoes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tipo VARCHAR(30) NOT NULL,
    titulo VARCHAR(255),
    corpo TEXT,
    disciplina_id UUID REFERENCES disciplinas(id) ON DELETE SET NULL,
    data_payload JSONB DEFAULT '{}',
    lida BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_notif_user ON notificacoes(user_id);
```

### 14. Tabela `referrals` [NOVA]
```sql
CREATE TABLE referrals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    referrer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    referred_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code VARCHAR(20) NOT NULL,
    reward_applied BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_ref_referrer ON referrals(referrer_id);
CREATE INDEX idx_ref_code ON referrals(code);
```

### 15. Tabela `subscriptions` [NOVA]
```sql
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plano VARCHAR(20) DEFAULT 'premium',
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'expired', 'cancelled')),
    trial_end TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    apple_transaction_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX idx_sub_user ON subscriptions(user_id);
```

### 16. Tabela `user_settings` [NOVA]
```sql
CREATE TABLE user_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    auto_transcription BOOLEAN DEFAULT true,
    auto_summaries BOOLEAN DEFAULT true,
    push_notifications BOOLEAN DEFAULT true,
    class_reminders BOOLEAN DEFAULT true,
    audio_quality VARCHAR(10) DEFAULT 'high' CHECK (audio_quality IN ('high', 'medium', 'low')),
    summary_language VARCHAR(10) DEFAULT 'pt-BR'
);
CREATE INDEX idx_settings_user ON user_settings(user_id);
```

## Verificação
1. `000_v2_foundation.sql` cria todas as 16 tabelas sem erro
2. Todos os índices estão presentes
3. Todas as constraints estão corretas
4. Arquivos 001-006 foram removidos
5. Não há tabela `transcricoes` nem tabela `resumos` — foram colapsadas em `gravacoes`
