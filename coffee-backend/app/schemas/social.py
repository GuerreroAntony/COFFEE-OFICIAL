"""Schemas for Social Contacts & Sharing (friends, groups, share targets)."""
from __future__ import annotations

from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field


def _initials(nome: str) -> str:
    """Generate initials from name (e.g. 'Ana Beatriz' -> 'AB')."""
    parts = nome.strip().split()
    if len(parts) >= 2:
        return (parts[0][0] + parts[1][0]).upper()
    elif parts:
        return parts[0][:2].upper()
    return "?"


# ── Friends ───────────────────────────────────────────────────────────────────

class SendFriendRequest(BaseModel):
    addressee_email: str | None = None
    addressee_id: UUID | None = None


class FriendResponse(BaseModel):
    id: UUID
    user_id: UUID
    nome: str
    email: str
    initials: str
    status: str
    created_at: datetime


class UserSearchResult(BaseModel):
    id: UUID
    nome: str
    email: str
    initials: str
    is_friend: bool
    friendship_status: Optional[str] = None


# ── Groups ────────────────────────────────────────────────────────────────────

class CreateGroupRequest(BaseModel):
    nome: str = Field(min_length=1, max_length=100)
    member_ids: list[UUID] = []


class AddMemberRequest(BaseModel):
    user_id: UUID


class GroupMemberResponse(BaseModel):
    user_id: UUID
    nome: str
    initials: str
    role: str


class GroupResponse(BaseModel):
    id: UUID
    nome: str
    is_auto: bool
    turma: Optional[str] = None
    disciplina_id: Optional[UUID] = None
    member_count: int
    members: Optional[list[GroupMemberResponse]] = None
    created_at: datetime


# ── Share Targets ─────────────────────────────────────────────────────────────

class ShareTargetResponse(BaseModel):
    friends: list[FriendResponse]
    groups: list[GroupResponse]
