from datetime import datetime, timedelta
from typing import Optional
import uuid

from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import firebase_admin
from firebase_admin import auth as firebase_auth

from app.config import settings
from app.models.user import User, UserSession, LanguageCode
from app.schemas.user import UserCreate


pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire, "type": "access", "jti": uuid.uuid4().hex})
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def create_refresh_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    to_encode.update({"exp": expire, "type": "refresh", "jti": uuid.uuid4().hex})
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        return payload
    except JWTError as e:
        raise ValueError(f"Invalid token: {e}")


async def create_user(db: AsyncSession, user_data: UserCreate) -> User:
    lang = LanguageCode(user_data.preferred_language) if user_data.preferred_language else LanguageCode.ENGLISH
    user = User(
        email=user_data.email,
        username=user_data.username,
        display_name=user_data.display_name,
        hashed_password=hash_password(user_data.password),
        phone=user_data.phone,
        preferred_language=lang,
    )
    db.add(user)
    await db.flush()
    await db.refresh(user)
    return user


async def authenticate_user(db: AsyncSession, email: str, password: str) -> Optional[User]:
    result = await db.execute(select(User).where(User.email == email, User.is_active == True))
    user = result.scalar_one_or_none()
    if not user or not user.hashed_password:
        return None
    if not verify_password(password, user.hashed_password):
        return None
    return user


async def verify_firebase_token(db: AsyncSession, firebase_token: str, preferred_language: str = "english") -> User:
    try:
        decoded_token = firebase_auth.verify_id_token(firebase_token)
        firebase_uid = decoded_token["uid"]
        email = decoded_token.get("email", "")
        display_name = decoded_token.get("name", email.split("@")[0])
        photo_url = decoded_token.get("picture")

        result = await db.execute(select(User).where(User.firebase_uid == firebase_uid))
        user = result.scalar_one_or_none()

        if not user:
            result = await db.execute(select(User).where(User.email == email))
            user = result.scalar_one_or_none()
            if user:
                user.firebase_uid = firebase_uid
                if photo_url and not user.avatar_url:
                    user.avatar_url = photo_url
            else:
                username = email.split("@")[0].replace(".", "_")[:50]
                lang = LanguageCode(preferred_language) if preferred_language in [e.value for e in LanguageCode] else LanguageCode.ENGLISH
                user = User(
                    email=email,
                    username=username,
                    display_name=display_name,
                    firebase_uid=firebase_uid,
                    avatar_url=photo_url,
                    preferred_language=lang,
                )
                db.add(user)
                await db.flush()
                await db.refresh(user)

        return user
    except firebase_admin.exceptions.FirebaseError as e:
        raise ValueError(f"Firebase token verification failed: {e}")


async def create_user_session(db: AsyncSession, user: User, refresh_token: str, device_info: Optional[str] = None) -> UserSession:
    expire = datetime.utcnow() + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    session = UserSession(
        user_id=user.id,
        refresh_token=refresh_token,
        device_info=device_info,
        expires_at=expire,
    )
    db.add(session)
    await db.flush()
    return session


async def invalidate_session(db: AsyncSession, refresh_token: str) -> bool:
    result = await db.execute(select(UserSession).where(UserSession.refresh_token == refresh_token))
    session = result.scalar_one_or_none()
    if session:
        session.is_active = False
        return True
    return False


async def get_user_by_id(db: AsyncSession, user_id: uuid.UUID) -> Optional[User]:
    result = await db.execute(select(User).where(User.id == user_id, User.is_active == True))
    return result.scalar_one_or_none()


async def get_user_by_email(db: AsyncSession, email: str) -> Optional[User]:
    result = await db.execute(select(User).where(User.email == email))
    return result.scalar_one_or_none()


async def update_online_status(db: AsyncSession, user_id: uuid.UUID, is_online: bool) -> None:
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if user:
        user.is_online = is_online
        if not is_online:
            user.last_seen = datetime.utcnow()
