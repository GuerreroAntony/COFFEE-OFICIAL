-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);

-- Disciplinas table
CREATE TABLE disciplinas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome VARCHAR(255) NOT NULL,
    professor VARCHAR(255),
    horario VARCHAR(100),
    semestre VARCHAR(20),
    codigo_espm VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- User-Disciplina junction (N:N)
CREATE TABLE user_disciplinas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    disciplina_id UUID NOT NULL REFERENCES disciplinas(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, disciplina_id)
);

CREATE INDEX idx_user_disc_user ON user_disciplinas(user_id);
CREATE INDEX idx_user_disc_disc ON user_disciplinas(disciplina_id);

-- Gravacoes table
CREATE TABLE gravacoes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    disciplina_id UUID NOT NULL REFERENCES disciplinas(id) ON DELETE CASCADE,
    data_aula DATE NOT NULL,
    duracao_segundos INTEGER DEFAULT 0,
    status VARCHAR(20) DEFAULT 'recording' CHECK (status IN ('recording', 'processing', 'completed', 'failed')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_gravacoes_user ON gravacoes(user_id);
CREATE INDEX idx_gravacoes_disc ON gravacoes(disciplina_id);

-- Transcricoes table
CREATE TABLE transcricoes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    gravacao_id UUID NOT NULL REFERENCES gravacoes(id) ON DELETE CASCADE,
    texto TEXT NOT NULL,
    idioma VARCHAR(10) DEFAULT 'pt-BR',
    confianca FLOAT DEFAULT 0.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_transcricoes_gravacao ON transcricoes(gravacao_id);

-- Resumos table
CREATE TABLE resumos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transcricao_id UUID NOT NULL REFERENCES transcricoes(id) ON DELETE CASCADE,
    titulo VARCHAR(255),
    topicos JSONB DEFAULT '[]',
    conceitos_chave JSONB DEFAULT '[]',
    resumo_geral TEXT,
    conexoes TEXT,
    modelo_usado VARCHAR(50) DEFAULT 'gpt-4o-mini',
    tokens_usados INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Materiais table
CREATE TABLE materiais (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    disciplina_id UUID NOT NULL REFERENCES disciplinas(id) ON DELETE CASCADE,
    tipo VARCHAR(20) CHECK (tipo IN ('slide', 'pdf', 'foto', 'outro')),
    nome VARCHAR(255) NOT NULL,
    url_storage TEXT,
    texto_extraido TEXT,
    fonte VARCHAR(20) DEFAULT 'scraper' CHECK (fonte IN ('scraper', 'upload_manual')),
    hash_arquivo VARCHAR(64),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_materiais_disc ON materiais(disciplina_id);
CREATE INDEX idx_materiais_hash ON materiais(hash_arquivo);

-- Chats table
CREATE TABLE chats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    disciplina_id UUID REFERENCES disciplinas(id) ON DELETE SET NULL,
    modo VARCHAR(20) DEFAULT 'disciplina' CHECK (modo IN ('disciplina', 'interdisciplinar', 'geral')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_chats_user ON chats(user_id);

-- Mensagens table
CREATE TABLE mensagens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    role VARCHAR(10) NOT NULL CHECK (role IN ('user', 'assistant')),
    conteudo TEXT NOT NULL,
    fontes JSONB DEFAULT '[]',
    tokens_usados INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_mensagens_chat ON mensagens(chat_id);

-- Embeddings table (pgvector)
CREATE TABLE embeddings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    disciplina_id UUID NOT NULL REFERENCES disciplinas(id) ON DELETE CASCADE,
    fonte_tipo VARCHAR(20) NOT NULL CHECK (fonte_tipo IN ('transcricao', 'resumo', 'material')),
    fonte_id UUID NOT NULL,
    chunk_index INTEGER NOT NULL,
    texto_chunk TEXT NOT NULL,
    embedding VECTOR(1536) NOT NULL,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_embeddings_disc ON embeddings(disciplina_id);
CREATE INDEX idx_embeddings_fonte ON embeddings(fonte_tipo, fonte_id);
CREATE INDEX idx_embeddings_vector ON embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- Device tokens for push notifications
CREATE TABLE device_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform VARCHAR(10) DEFAULT 'ios',
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_device_tokens_user ON device_tokens(user_id);

-- Notificacoes log
CREATE TABLE notificacoes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tipo VARCHAR(30) NOT NULL,
    titulo VARCHAR(255),
    corpo TEXT,
    data_payload JSONB DEFAULT '{}',
    enviada BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
