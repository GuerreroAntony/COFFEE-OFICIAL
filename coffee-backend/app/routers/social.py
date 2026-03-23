"""
Social Contacts & Sharing — friends, groups, share targets.

Endpoints:
  GET    /api/v1/social/friends           — List accepted friends
  GET    /api/v1/social/friends/requests   — Pending friend requests
  POST   /api/v1/social/friends/request    — Send friend request by email
  POST   /api/v1/social/friends/{id}/accept  — Accept friend request
  POST   /api/v1/social/friends/{id}/reject  — Reject friend request
  DELETE /api/v1/social/friends/{id}       — Remove friend
  GET    /api/v1/social/search             — Search users
  GET    /api/v1/social/groups             — List groups
  POST   /api/v1/social/groups             — Create custom group
  GET    /api/v1/social/groups/{id}        — Group detail
  POST   /api/v1/social/groups/{id}/members  — Add member
  DELETE /api/v1/social/groups/{id}/members/{user_id} — Remove member / leave
  DELETE /api/v1/social/groups/{id}        — Delete custom group
  GET    /api/v1/social/share-targets      — Friends + groups for share sheet
"""
from __future__ import annotations

import json
import logging
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, status

from app.database import execute_query, fetch_all, fetch_one
from app.dependencies import get_current_user
from app.schemas.base import error_response, success_response
from app.schemas.social import (
    AddMemberRequest,
    CreateGroupRequest,
    FriendResponse,
    GroupMemberResponse,
    GroupResponse,
    SendFriendRequest,
    ShareTargetResponse,
    UserSearchResult,
    _initials,
)

router = APIRouter(prefix="/api/v1/social", tags=["social"])
logger = logging.getLogger(__name__)


# ═══════════════════════════════════════════════════════════════════════════════
# Friends
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/friends")
async def list_friends(user_id: UUID = Depends(get_current_user)):
    """List accepted friends with pending share count."""
    rows = await fetch_all(
        """
        SELECT f.id,
               f.created_at,
               CASE WHEN f.requester_id = $1 THEN f.addressee_id ELSE f.requester_id END AS other_id,
               u.nome,
               u.email,
               COALESCE((
                   SELECT COUNT(*) FROM compartilhamentos c
                   WHERE c.recipient_id = $1
                     AND c.sender_id = CASE WHEN f.requester_id = $1 THEN f.addressee_id ELSE f.requester_id END
                     AND c.status = 'pending'
                     AND c.group_id IS NULL
               ), 0) AS pending_count
        FROM friends f
        JOIN users u ON u.id = CASE WHEN f.requester_id = $1 THEN f.addressee_id ELSE f.requester_id END
        WHERE (f.requester_id = $1 OR f.addressee_id = $1)
          AND f.status = 'accepted'
        ORDER BY u.nome
        """,
        user_id,
    )

    friends = []
    for r in rows:
        d = FriendResponse(
            id=r["id"],
            user_id=r["other_id"],
            nome=r["nome"],
            email=r["email"],
            initials=_initials(r["nome"]),
            status="accepted",
            created_at=r["created_at"],
        ).model_dump(mode="json")
        d["pending_count"] = r["pending_count"]
        friends.append(d)

    return success_response(friends)


@router.get("/friends/requests")
async def list_friend_requests(user_id: UUID = Depends(get_current_user)):
    """List pending friend requests (sent and received)."""
    # Sent requests
    sent_rows = await fetch_all(
        """
        SELECT f.id, f.addressee_id AS other_id, f.created_at,
               u.nome, u.email
        FROM friends f
        JOIN users u ON u.id = f.addressee_id
        WHERE f.requester_id = $1 AND f.status = 'pending'
        ORDER BY f.created_at DESC
        """,
        user_id,
    )

    # Received requests
    received_rows = await fetch_all(
        """
        SELECT f.id, f.requester_id AS other_id, f.created_at,
               u.nome, u.email
        FROM friends f
        JOIN users u ON u.id = f.requester_id
        WHERE f.addressee_id = $1 AND f.status = 'pending'
        ORDER BY f.created_at DESC
        """,
        user_id,
    )

    sent = [
        FriendResponse(
            id=r["id"],
            user_id=r["other_id"],
            nome=r["nome"],
            email=r["email"],
            initials=_initials(r["nome"]),
            status="pending_sent",
            created_at=r["created_at"],
        ).model_dump(mode="json")
        for r in sent_rows
    ]

    received = [
        FriendResponse(
            id=r["id"],
            user_id=r["other_id"],
            nome=r["nome"],
            email=r["email"],
            initials=_initials(r["nome"]),
            status="pending_received",
            created_at=r["created_at"],
        ).model_dump(mode="json")
        for r in received_rows
    ]

    return success_response({"sent": sent, "received": received})


@router.post("/friends/request")
async def send_friend_request(
    body: SendFriendRequest,
    background_tasks: BackgroundTasks,
    user_id: UUID = Depends(get_current_user),
):
    """Send a friend request by email or user_id."""
    # Look up addressee by ID or email
    if body.addressee_id:
        addressee = await fetch_one(
            "SELECT id, nome FROM users WHERE id = $1",
            body.addressee_id,
        )
    elif body.addressee_email:
        addressee = await fetch_one(
            "SELECT id, nome FROM users WHERE email = $1",
            body.addressee_email,
        )
    else:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=error_response("VALIDATION_ERROR", "Forneça addressee_email ou addressee_id."),
        )
    if not addressee:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=error_response("USER_NOT_FOUND", "Nenhum usuário encontrado."),
        )
    addressee_id = addressee["id"]

    if addressee_id == user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=error_response("SELF_REQUEST", "Você não pode adicionar a si mesmo."),
        )

    # Check for existing friendship in either direction
    existing = await fetch_one(
        """
        SELECT id, status, requester_id, addressee_id
        FROM friends
        WHERE (requester_id = $1 AND addressee_id = $2)
           OR (requester_id = $2 AND addressee_id = $1)
        """,
        user_id, addressee_id,
    )

    if existing:
        if existing["status"] == "accepted":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_response("ALREADY_FRIENDS", "Vocês já são amigos."),
            )
        if existing["status"] == "blocked":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_response("BLOCKED", "Não é possível enviar solicitação."),
            )
        # Pending — check direction
        if existing["requester_id"] == user_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_response("ALREADY_SENT", "Solicitação já enviada."),
            )
        # REVERSE pending: they already sent to us — auto-accept
        await execute_query(
            "UPDATE friends SET status = 'accepted' WHERE id = $1",
            existing["id"],
        )
        # Notify both parties
        sender = await fetch_one("SELECT nome FROM users WHERE id = $1", user_id)
        sender_name = sender["nome"] if sender else "Aluno"
        addressee_name = addressee["nome"]

        # Notify the original requester (addressee in this call) that we accepted
        await execute_query(
            """INSERT INTO notificacoes (user_id, tipo, titulo, corpo)
               VALUES ($1, 'friend_accepted', $2, $3)""",
            addressee_id,
            f"{sender_name} aceitou sua solicitação",
            f"Você e {sender_name} agora são amigos no Coffee.",
        )
        background_tasks.add_task(_send_friend_push, addressee_id, sender_name, "accepted")

        return success_response({
            "id": str(existing["id"]),
            "status": "accepted",
            "message": "Solicitação mútua detectada — amizade aceita automaticamente.",
        })

    # Create new pending request
    row = await fetch_one(
        """INSERT INTO friends (requester_id, addressee_id, status)
           VALUES ($1, $2, 'pending')
           RETURNING id, created_at""",
        user_id, addressee_id,
    )

    # Get sender name for notifications
    sender = await fetch_one("SELECT nome FROM users WHERE id = $1", user_id)
    sender_name = sender["nome"] if sender else "Aluno"

    # Create notification
    await execute_query(
        """INSERT INTO notificacoes (user_id, tipo, titulo, corpo)
           VALUES ($1, 'friend_request', $2, $3)""",
        addressee_id,
        f"{sender_name} quer ser seu amigo",
        f"{sender_name} enviou uma solicitação de amizade.",
    )

    # Push notification in background
    background_tasks.add_task(_send_friend_push, addressee_id, sender_name, "request")

    return success_response({
        "id": str(row["id"]),
        "status": "pending",
        "created_at": row["created_at"].isoformat(),
    })


@router.post("/friends/{friend_id}/accept")
async def accept_friend_request(
    friend_id: UUID,
    background_tasks: BackgroundTasks,
    user_id: UUID = Depends(get_current_user),
):
    """Accept a pending friend request. Only the addressee can accept."""
    row = await fetch_one(
        "SELECT id, requester_id, addressee_id, status FROM friends WHERE id = $1",
        friend_id,
    )
    if not row:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Solicitação não encontrada."))
    if row["addressee_id"] != user_id:
        raise HTTPException(status_code=403, detail=error_response("FORBIDDEN", "Apenas o destinatário pode aceitar."))
    if row["status"] != "pending":
        raise HTTPException(status_code=400, detail=error_response("ALREADY_HANDLED", "Solicitação já processada."))

    await execute_query("UPDATE friends SET status = 'accepted' WHERE id = $1", friend_id)

    # Notify requester
    accepter = await fetch_one("SELECT nome FROM users WHERE id = $1", user_id)
    accepter_name = accepter["nome"] if accepter else "Aluno"
    requester_id = row["requester_id"]

    await execute_query(
        """INSERT INTO notificacoes (user_id, tipo, titulo, corpo)
           VALUES ($1, 'friend_accepted', $2, $3)""",
        requester_id,
        f"{accepter_name} aceitou sua solicitação",
        f"Você e {accepter_name} agora são amigos no Coffee.",
    )
    background_tasks.add_task(_send_friend_push, requester_id, accepter_name, "accepted")

    return success_response({"id": str(friend_id), "status": "accepted"})


@router.post("/friends/{friend_id}/reject")
async def reject_friend_request(
    friend_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Reject a pending friend request. Only the addressee can reject. Deletes the row."""
    row = await fetch_one(
        "SELECT id, addressee_id, status FROM friends WHERE id = $1",
        friend_id,
    )
    if not row:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Solicitação não encontrada."))
    if row["addressee_id"] != user_id:
        raise HTTPException(status_code=403, detail=error_response("FORBIDDEN", "Apenas o destinatário pode rejeitar."))
    if row["status"] != "pending":
        raise HTTPException(status_code=400, detail=error_response("ALREADY_HANDLED", "Solicitação já processada."))

    await execute_query("DELETE FROM friends WHERE id = $1", friend_id)
    return success_response({"status": "rejected"})


@router.delete("/friends/{friend_id}")
async def remove_friend(
    friend_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Remove an accepted friendship. Either party can remove."""
    row = await fetch_one(
        "SELECT id, requester_id, addressee_id, status FROM friends WHERE id = $1",
        friend_id,
    )
    if not row:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Amizade não encontrada."))
    if row["requester_id"] != user_id and row["addressee_id"] != user_id:
        raise HTTPException(status_code=403, detail=error_response("FORBIDDEN", "Você não faz parte dessa amizade."))

    await execute_query("DELETE FROM friends WHERE id = $1", friend_id)
    return success_response({"status": "removed"})


@router.get("/search")
async def search_users(
    q: str = Query(min_length=2, max_length=100),
    user_id: UUID = Depends(get_current_user),
):
    """Search for Coffee users by name or email. Returns up to 20 results."""
    rows = await fetch_all(
        """
        SELECT id, nome, email
        FROM users
        WHERE (nome ILIKE '%' || $2 || '%' OR email ILIKE '%' || $2 || '%')
          AND id != $1
          AND espm_login IS NOT NULL
        LIMIT 20
        """,
        user_id, q,
    )

    results = []
    for r in rows:
        # Check friendship status
        friendship = await fetch_one(
            """
            SELECT status, requester_id
            FROM friends
            WHERE (requester_id = $1 AND addressee_id = $2)
               OR (requester_id = $2 AND addressee_id = $1)
            """,
            user_id, r["id"],
        )

        is_friend = False
        friendship_status = None
        if friendship:
            if friendship["status"] == "accepted":
                is_friend = True
                friendship_status = "accepted"
            elif friendship["status"] == "pending":
                if friendship["requester_id"] == user_id:
                    friendship_status = "pending_sent"
                else:
                    friendship_status = "pending_received"
            elif friendship["status"] == "blocked":
                friendship_status = "blocked"

        results.append(
            UserSearchResult(
                id=r["id"],
                nome=r["nome"],
                email=r["email"],
                initials=_initials(r["nome"]),
                is_friend=is_friend,
                friendship_status=friendship_status,
            ).model_dump(mode="json")
        )

    return success_response(results)


# ═══════════════════════════════════════════════════════════════════════════════
# Groups
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/groups")
async def list_groups(user_id: UUID = Depends(get_current_user)):
    """List groups where the current user is a member, with pending share count."""
    rows = await fetch_all(
        """
        SELECT g.id, g.nome, g.is_auto, g.turma, g.disciplina_id, g.created_at,
               (SELECT COUNT(*) FROM group_members gm2 WHERE gm2.group_id = g.id) AS member_count,
               COALESCE((
                   SELECT COUNT(*) FROM compartilhamentos c
                   WHERE c.group_id = g.id
                     AND c.recipient_id = $1
                     AND c.status = 'pending'
               ), 0) AS pending_count
        FROM groups g
        JOIN group_members gm ON gm.group_id = g.id
        WHERE gm.user_id = $1
        ORDER BY g.is_auto DESC, g.nome
        """,
        user_id,
    )

    groups = []
    for r in rows:
        d = GroupResponse(
            id=r["id"],
            nome=r["nome"],
            is_auto=r["is_auto"],
            turma=r.get("turma"),
            disciplina_id=r.get("disciplina_id"),
            member_count=r["member_count"],
            members=None,
            created_at=r["created_at"],
        ).model_dump(mode="json")
        d["pending_count"] = r["pending_count"]
        groups.append(d)

    return success_response(groups)


@router.post("/groups")
async def create_group(
    body: CreateGroupRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Create a custom group. All member_ids must be accepted friends."""
    # Validate all member_ids are accepted friends
    for mid in body.member_ids:
        if mid == user_id:
            continue  # skip self
        friendship = await fetch_one(
            """
            SELECT id FROM friends
            WHERE ((requester_id = $1 AND addressee_id = $2)
                OR (requester_id = $2 AND addressee_id = $1))
              AND status = 'accepted'
            """,
            user_id, mid,
        )
        if not friendship:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_response("NOT_FRIEND", f"Usuário {mid} não é seu amigo."),
            )

    # Create group
    row = await fetch_one(
        """INSERT INTO groups (nome, created_by, is_auto)
           VALUES ($1, $2, false)
           RETURNING id, created_at""",
        body.nome, user_id,
    )
    group_id = row["id"]

    # Add creator as admin
    await execute_query(
        """INSERT INTO group_members (group_id, user_id, role)
           VALUES ($1, $2, 'admin')""",
        group_id, user_id,
    )

    # Add members
    for mid in body.member_ids:
        if mid == user_id:
            continue
        await execute_query(
            """INSERT INTO group_members (group_id, user_id, role)
               VALUES ($1, $2, 'member')
               ON CONFLICT (group_id, user_id) DO NOTHING""",
            group_id, mid,
        )

    member_count = 1 + len([m for m in body.member_ids if m != user_id])

    return success_response(
        GroupResponse(
            id=group_id,
            nome=body.nome,
            is_auto=False,
            disciplina_id=None,
            member_count=member_count,
            members=None,
            created_at=row["created_at"],
        ).model_dump(mode="json")
    )


@router.get("/groups/{group_id}")
async def get_group(
    group_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Get group detail with full members list. User must be a member."""
    # Verify membership
    membership = await fetch_one(
        "SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2",
        group_id, user_id,
    )
    if not membership:
        raise HTTPException(status_code=403, detail=error_response("FORBIDDEN", "Você não é membro desse grupo."))

    group_row = await fetch_one(
        """SELECT g.id, g.nome, g.is_auto, g.turma, g.disciplina_id, g.created_at,
                  (SELECT COUNT(*) FROM group_members gm2 WHERE gm2.group_id = g.id) AS member_count
           FROM groups g
           WHERE g.id = $1""",
        group_id,
    )
    if not group_row:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Grupo não encontrado."))

    # Fetch members
    member_rows = await fetch_all(
        """SELECT gm.user_id, gm.role, u.nome
           FROM group_members gm
           JOIN users u ON u.id = gm.user_id
           WHERE gm.group_id = $1
           ORDER BY gm.role, u.nome""",
        group_id,
    )

    members = [
        GroupMemberResponse(
            user_id=m["user_id"],
            nome=m["nome"],
            initials=_initials(m["nome"]),
            role=m["role"],
        ).model_dump(mode="json")
        for m in member_rows
    ]

    return success_response(
        GroupResponse(
            id=group_row["id"],
            nome=group_row["nome"],
            is_auto=group_row["is_auto"],
            turma=group_row.get("turma"),
            disciplina_id=group_row.get("disciplina_id"),
            member_count=group_row["member_count"],
            members=members,
            created_at=group_row["created_at"],
        ).model_dump(mode="json")
    )


@router.post("/groups/{group_id}/members")
async def add_group_member(
    group_id: UUID,
    body: AddMemberRequest,
    user_id: UUID = Depends(get_current_user),
):
    """Add a member to a group. For custom groups, must be admin. New user must be a friend."""
    # Get group info
    group_row = await fetch_one(
        "SELECT id, is_auto, created_by FROM groups WHERE id = $1",
        group_id,
    )
    if not group_row:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Grupo não encontrado."))

    # Check current user's membership and role
    my_membership = await fetch_one(
        "SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2",
        group_id, user_id,
    )
    if not my_membership:
        raise HTTPException(status_code=403, detail=error_response("FORBIDDEN", "Você não é membro desse grupo."))

    # For custom groups, must be admin
    if not group_row["is_auto"] and my_membership["role"] != "admin":
        raise HTTPException(status_code=403, detail=error_response("FORBIDDEN", "Apenas administradores podem adicionar membros."))

    # Check the new user is a friend of the current user
    friendship = await fetch_one(
        """
        SELECT id FROM friends
        WHERE ((requester_id = $1 AND addressee_id = $2)
            OR (requester_id = $2 AND addressee_id = $1))
          AND status = 'accepted'
        """,
        user_id, body.user_id,
    )
    if not friendship:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=error_response("NOT_FRIEND", "O usuário precisa ser seu amigo para ser adicionado."),
        )

    # Check if already a member
    already = await fetch_one(
        "SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2",
        group_id, body.user_id,
    )
    if already:
        raise HTTPException(status_code=400, detail=error_response("ALREADY_MEMBER", "Usuário já é membro do grupo."))

    await execute_query(
        """INSERT INTO group_members (group_id, user_id, role)
           VALUES ($1, $2, 'member')""",
        group_id, body.user_id,
    )

    return success_response({"status": "added", "group_id": str(group_id), "user_id": str(body.user_id)})


@router.delete("/groups/{group_id}/members/{member_user_id}")
async def remove_group_member(
    group_id: UUID,
    member_user_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Remove a member or leave a group."""
    group_row = await fetch_one(
        "SELECT id, is_auto, created_by FROM groups WHERE id = $1",
        group_id,
    )
    if not group_row:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Grupo não encontrado."))

    if member_user_id == user_id:
        # Leaving the group
        if group_row["is_auto"]:
            raise HTTPException(
                status_code=400,
                detail=error_response("CANNOT_LEAVE_AUTO", "Não é possível sair de um grupo automático de disciplina."),
            )
        await execute_query(
            "DELETE FROM group_members WHERE group_id = $1 AND user_id = $2",
            group_id, user_id,
        )
        return success_response({"status": "left"})
    else:
        # Removing someone else — must be admin + custom group
        if group_row["is_auto"]:
            raise HTTPException(
                status_code=400,
                detail=error_response("CANNOT_REMOVE_AUTO", "Não é possível remover membros de grupos automáticos."),
            )
        my_membership = await fetch_one(
            "SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2",
            group_id, user_id,
        )
        if not my_membership or my_membership["role"] != "admin":
            raise HTTPException(status_code=403, detail=error_response("FORBIDDEN", "Apenas administradores podem remover membros."))

        result = await execute_query(
            "DELETE FROM group_members WHERE group_id = $1 AND user_id = $2",
            group_id, member_user_id,
        )
        return success_response({"status": "removed"})


@router.delete("/groups/{group_id}")
async def delete_group(
    group_id: UUID,
    user_id: UUID = Depends(get_current_user),
):
    """Delete a custom group. Only the creator can delete. Auto groups cannot be deleted."""
    group_row = await fetch_one(
        "SELECT id, is_auto, created_by FROM groups WHERE id = $1",
        group_id,
    )
    if not group_row:
        raise HTTPException(status_code=404, detail=error_response("NOT_FOUND", "Grupo não encontrado."))
    if group_row["is_auto"]:
        raise HTTPException(status_code=400, detail=error_response("CANNOT_DELETE_AUTO", "Grupos automáticos não podem ser excluídos."))
    if group_row["created_by"] != user_id:
        raise HTTPException(status_code=403, detail=error_response("FORBIDDEN", "Apenas o criador pode excluir o grupo."))

    # CASCADE deletes group_members
    await execute_query("DELETE FROM groups WHERE id = $1", group_id)
    return success_response({"status": "deleted"})


# ═══════════════════════════════════════════════════════════════════════════════
# Share Targets
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/share-targets")
async def get_share_targets(user_id: UUID = Depends(get_current_user)):
    """Return combined friends + groups for the share sheet."""
    # Friends
    friend_rows = await fetch_all(
        """
        SELECT f.id, f.created_at,
               CASE WHEN f.requester_id = $1 THEN f.addressee_id ELSE f.requester_id END AS other_id,
               u.nome, u.email
        FROM friends f
        JOIN users u ON u.id = CASE WHEN f.requester_id = $1 THEN f.addressee_id ELSE f.requester_id END
        WHERE (f.requester_id = $1 OR f.addressee_id = $1)
          AND f.status = 'accepted'
        ORDER BY u.nome
        """,
        user_id,
    )
    friends = [
        FriendResponse(
            id=r["id"],
            user_id=r["other_id"],
            nome=r["nome"],
            email=r["email"],
            initials=_initials(r["nome"]),
            status="accepted",
            created_at=r["created_at"],
        ).model_dump(mode="json")
        for r in friend_rows
    ]

    # Groups
    group_rows = await fetch_all(
        """
        SELECT g.id, g.nome, g.is_auto, g.turma, g.disciplina_id, g.created_at,
               (SELECT COUNT(*) FROM group_members gm2 WHERE gm2.group_id = g.id) AS member_count
        FROM groups g
        JOIN group_members gm ON gm.group_id = g.id
        WHERE gm.user_id = $1
        ORDER BY g.is_auto DESC, g.nome
        """,
        user_id,
    )
    groups = [
        GroupResponse(
            id=r["id"],
            nome=r["nome"],
            is_auto=r["is_auto"],
            turma=r.get("turma"),
            disciplina_id=r.get("disciplina_id"),
            member_count=r["member_count"],
            members=None,
            created_at=r["created_at"],
        ).model_dump(mode="json")
        for r in group_rows
    ]

    return success_response(
        ShareTargetResponse(friends=friends, groups=groups).model_dump(mode="json")
    )


# ═══════════════════════════════════════════════════════════════════════════════
# Push helper
# ═══════════════════════════════════════════════════════════════════════════════

async def _send_friend_push(target_user_id: UUID, actor_name: str, action: str):
    """Send push notification for friend request / acceptance."""
    try:
        from app.services.push_service import send_push_to_user

        if action == "request":
            title = f"{actor_name} quer ser seu amigo"
            body = "Abra o Coffee para aceitar a solicitação."
        else:
            title = f"{actor_name} aceitou sua solicitação"
            body = f"Você e {actor_name} agora são amigos no Coffee."

        await send_push_to_user(
            target_user_id,
            title,
            body,
            {"type": f"friend_{action}", "deep_link": "coffee://social"},
        )
    except Exception as e:
        logger.warning("Push notification failed for friend %s: %s", action, e)
