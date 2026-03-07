from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from app.database import fetch_one
from app.dependencies import get_current_user
from app.schemas.auth import AuthResponse, LoginRequest, SignupRequest, UserResponse
from app.utils.security import create_jwt, hash_password, verify_password

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


@router.post("/signup", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def signup(body: SignupRequest):
    existing = await fetch_one(
        "SELECT id FROM users WHERE email = $1",
        body.email,
    )
    if existing:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email já cadastrado")

    password_hash = hash_password(body.senha)

    user = await fetch_one(
        """
        INSERT INTO users (nome, email, password_hash)
        VALUES ($1, $2, $3)
        RETURNING id, nome, email, created_at
        """,
        body.nome,
        body.email,
        password_hash,
    )

    token = create_jwt(user["id"])
    return AuthResponse(user=UserResponse(**dict(user)), token=token)


@router.post("/login", response_model=AuthResponse, status_code=status.HTTP_200_OK)
async def login(body: LoginRequest):
    user = await fetch_one(
        "SELECT id, nome, email, password_hash, created_at FROM users WHERE email = $1",
        body.email,
    )
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Usuário não encontrado")

    if not verify_password(body.senha, user["password_hash"]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Senha incorreta")

    token = create_jwt(user["id"])
    return AuthResponse(
        user=UserResponse(
            id=user["id"],
            nome=user["nome"],
            email=user["email"],
            created_at=user["created_at"],
        ),
        token=token,
    )


@router.get("/me", response_model=UserResponse, status_code=status.HTTP_200_OK)
async def me(user_id: UUID = Depends(get_current_user)):
    user = await fetch_one(
        "SELECT id, nome, email, created_at FROM users WHERE id = $1",
        user_id,
    )
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Usuário não encontrado")

    return UserResponse(**dict(user))
