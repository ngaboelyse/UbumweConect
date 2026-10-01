from fastapi import APIRouter, Depends, HTTPException, status, BackgroundTasks
from typing import Optional
import uuid
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update

from app.database import get_db
from app.schemas.user import (
    UserCreate, LoginRequest, FirebaseLoginRequest, TokenResponse,
    RefreshTokenRequest, PasswordResetRequest, UserResponse
)
from app.services import auth_service
from app.models.user import User, UserSession
from app.middleware.auth_middleware import get_current_user

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def register(user_data: UserCreate, db: AsyncSession = Depends(get_db)):
    # Check email uniqueness
    result = await db.execute(select(User).where(User.email == user_data.email))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Email already registered")

    result = await db.execute(select(User).where(User.username == user_data.username))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Username already taken")

    user = await auth_service.create_user(db, user_data)

    access_token = auth_service.create_access_token({"sub": str(user.id)})
    refresh_token = auth_service.create_refresh_token({"sub": str(user.id)})
    await auth_service.create_user_session(db, user, refresh_token)
    await db.commit()

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user=UserResponse.model_validate(user),
    )


@router.post("/login", response_model=TokenResponse)
async def login(credentials: LoginRequest, db: AsyncSession = Depends(get_db)):
    user = await auth_service.authenticate_user(db, credentials.email, credentials.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    access_token = auth_service.create_access_token({"sub": str(user.id)})
    refresh_token = auth_service.create_refresh_token({"sub": str(user.id)})
    await auth_service.create_user_session(db, user, refresh_token)
    await db.commit()

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user=UserResponse.model_validate(user),
    )


@router.post("/firebase-login", response_model=TokenResponse)
async def firebase_login(data: FirebaseLoginRequest, db: AsyncSession = Depends(get_db)):
    try:
        user = await auth_service.verify_firebase_token(db, data.firebase_token, data.preferred_language)
    except ValueError as e:
        raise HTTPException(status_code=401, detail=str(e))

    access_token = auth_service.create_access_token({"sub": str(user.id)})
    refresh_token = auth_service.create_refresh_token({"sub": str(user.id)})
    await auth_service.create_user_session(db, user, refresh_token)
    await db.commit()

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user=UserResponse.model_validate(user),
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(data: RefreshTokenRequest, db: AsyncSession = Depends(get_db)):
    try:
        payload = auth_service.decode_token(data.refresh_token)
        if payload.get("type") != "refresh":
            raise HTTPException(status_code=401, detail="Invalid token type")
        user_id = uuid.UUID(str(payload.get("sub")))
    except ValueError:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    result = await db.execute(
        select(UserSession).where(
            UserSession.refresh_token == data.refresh_token,
            UserSession.is_active == True,
        )
    )
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=401, detail="Session expired")

    user = await auth_service.get_user_by_id(db, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # Rotate tokens
    session.is_active = False
    new_access = auth_service.create_access_token({"sub": str(user.id)})
    new_refresh = auth_service.create_refresh_token({"sub": str(user.id)})
    await auth_service.create_user_session(db, user, new_refresh)
    await db.commit()

    return TokenResponse(
        access_token=new_access,
        refresh_token=new_refresh,
        user=UserResponse.model_validate(user),
    )


@router.post("/logout")
async def logout(
    data: Optional[RefreshTokenRequest] = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Invalidate the current user's session(s).
    A specific refresh token may be supplied to log out a single session;
    otherwise all sessions for the authenticated user are invalidated."""
    stmt = update(UserSession).where(
        UserSession.user_id == current_user.id,
        UserSession.is_active == True,  # noqa: E712
    )
    if data and data.refresh_token:
        stmt = stmt.where(UserSession.refresh_token == data.refresh_token)
    await db.execute(stmt.values(is_active=False))
    await db.commit()
    return {"message": "Logged out successfully"}


@router.get("/me", response_model=UserResponse)
async def get_me(current_user: User = Depends(get_current_user)):
    return UserResponse.model_validate(current_user)


@router.post("/forgot-password", status_code=status.HTTP_202_ACCEPTED)
async def forgot_password(data: PasswordResetRequest, db: AsyncSession = Depends(get_db)):
    # In production, send email with reset link via Firebase
    user = await auth_service.get_user_by_email(db, data.email)
    # Always return success to prevent email enumeration
    return {"message": "If this email exists, a reset link has been sent"}
