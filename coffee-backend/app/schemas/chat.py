from uuid import UUID
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel


class PersonalityConfigSchema(BaseModel):
    profundidade: int = 50
    linguagem: int = 50
    exemplos: int = 50
    questionamento: int = 50
    foco: int = 50


class ChatSendRequest(BaseModel):
    mensagem: str
    chat_id: Optional[UUID] = None
    disciplina_id: Optional[UUID] = None
    modo: str = "disciplina"
    personality: Optional[PersonalityConfigSchema] = None


class MensagemResponse(BaseModel):
    id: UUID
    chat_id: UUID
    role: str
    conteudo: str
    fontes: list
    created_at: datetime


class ChatSummaryResponse(BaseModel):
    id: UUID
    disciplina_id: Optional[UUID] = None
    disciplina_nome: Optional[str] = None
    modo: str
    last_message_preview: Optional[str] = None
    created_at: datetime


class HistoryResponse(BaseModel):
    messages: List[MensagemResponse]


class ChatsListResponse(BaseModel):
    chats: List[ChatSummaryResponse]
