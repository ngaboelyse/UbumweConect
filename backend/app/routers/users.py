from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_, func
import uuid

from app.database import get_db
from app.models.user import User, UserContact
from app.schemas.user import UserResponse, UserUpdate, UserProfile, ContactResponse, LanguageUpdateRequest, OnlineStatusResponse
from app.services.file_service import FileService
from app.middleware.auth_middleware import get_current_user
from pydantic import BaseModel

router = APIRouter(prefix="/users", tags=["Users"])
file_service = FileService()


class PushTokenRequest(BaseModel):
    token: str
    platform: str = "android"


@router.get("/profile", response_model=UserResponse)
async def get_profile(current_user: User = Depends(get_current_user)):
    return UserResponse.model_validate(current_user)


@router.put("/profile", response_model=UserResponse)
async def update_profile(
    data: UserUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if data.display_name is not None:
        current_user.display_name = data.display_name
    if data.bio is not None:
        current_user.bio = data.bio
    if data.phone is not None:
        current_user.phone = data.phone
    if data.avatar_url is not None:
        current_user.avatar_url = data.avatar_url
    if data.push_token is not None:
        current_user.push_token = data.push_token
    if data.preferred_language is not None:
        from app.models.user import LanguageCode
        try:
            current_user.preferred_language = LanguageCode(data.preferred_language)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid language code")

    await db.commit()
    await db.refresh(current_user)
    return UserResponse.model_validate(current_user)


@router.post("/push-token", status_code=204)
async def register_push_token(
    data: PushTokenRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Register/refresh the device's FCM token so the server can send push
    notifications. Called by the app on login and whenever the token rotates."""
    if data.platform not in ("android", "ios", "web"):
        raise HTTPException(status_code=400, detail="Invalid platform")
    current_user.push_token = data.token
    await db.commit()


@router.post("/avatar", response_model=UserResponse)
async def upload_avatar(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if not file_service.validate_file_type(file.filename, ["jpg", "jpeg", "png", "webp"]):
        raise HTTPException(status_code=400, detail="Invalid file type. Use JPG, PNG, or WebP")
    if not file_service.validate_file_size(file.size or 0, max_mb=5):
        raise HTTPException(status_code=400, detail="File too large. Max 5MB")

    try:
        avatar_url = await file_service.upload_file_object(
            file, file.filename, folder="avatars", user_id=str(current_user.id)
        )
        current_user.avatar_url = avatar_url
        await db.commit()
        await db.refresh(current_user)
        return UserResponse.model_validate(current_user)
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))


@router.get("/search", response_model=List[UserProfile])
async def search_users(
    q: str = Query(..., min_length=2),
    limit: int = Query(default=20, le=50),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(User).where(
            User.is_active == True,
            User.id != current_user.id,
            or_(
                User.username.ilike(f"%{q}%"),
                User.display_name.ilike(f"%{q}%"),
                User.email.ilike(f"%{q}%"),
            ),
        ).limit(limit)
    )
    users = result.scalars().all()
    return [UserProfile.model_validate(u) for u in users]


@router.get("/{user_id}", response_model=UserProfile)
async def get_user(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(User).where(User.id == user_id, User.is_active == True))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return UserProfile.model_validate(user)


@router.get("/contacts/list", response_model=List[UserProfile])
async def get_contacts(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(User).join(
            UserContact, UserContact.contact_id == User.id
        ).where(UserContact.user_id == current_user.id)
    )
    contacts = result.scalars().all()
    return [UserProfile.model_validate(c) for c in contacts]


@router.post("/contacts/{user_id}", status_code=201)
async def add_contact(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if user_id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot add yourself as contact")

    result = await db.execute(select(User).where(User.id == user_id, User.is_active == True))
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="User not found")

    existing = await db.execute(
        select(UserContact).where(
            UserContact.user_id == current_user.id,
            UserContact.contact_id == user_id,
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Contact already added")

    contact = UserContact(user_id=current_user.id, contact_id=user_id)
    db.add(contact)
    await db.commit()
    return {"message": "Contact added"}


@router.delete("/contacts/{user_id}", status_code=204)
async def remove_contact(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(UserContact).where(
            UserContact.user_id == current_user.id,
            UserContact.contact_id == user_id,
        )
    )
    contact = result.scalar_one_or_none()
    if not contact:
        raise HTTPException(status_code=404, detail="Contact not found")
    await db.delete(contact)
    await db.commit()


@router.put("/language", response_model=UserResponse)
async def update_language(
    data: LanguageUpdateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    from app.models.user import LanguageCode
    current_user.preferred_language = LanguageCode(data.preferred_language)
    await db.commit()
    await db.refresh(current_user)
    return UserResponse.model_validate(current_user)
