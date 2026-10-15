import uuid
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, Text, ForeignKey, Enum as SAEnum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy import JSON

# JSONB variant: PostgreSQL gets native JSONB, other dialects (SQLite tests) fall back to JSON.
def _json_variant() -> JSON:
    return JSON().with_variant(JSONB, "postgresql")

JSONVariant = _json_variant()

import enum

from app.database import Base


class LanguageCode(str, enum.Enum):
    KINYARWANDA = "kinyarwanda"
    ENGLISH = "english"
    FRENCH = "french"
    SWAHILI = "swahili"
    SPANISH = "spanish"
    ARABIC = "arabic"
    PORTUGUESE = "portuguese"
    GERMAN = "german"
    CHINESE = "chinese"


class UserRole(str, enum.Enum):
    USER = "user"
    ADMIN = "admin"
    MODERATOR = "moderator"


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    username: Mapped[str] = mapped_column(String(50), unique=True, nullable=False, index=True)
    display_name: Mapped[str] = mapped_column(String(100), nullable=False)
    hashed_password: Mapped[str | None] = mapped_column(String(255), nullable=True)
    firebase_uid: Mapped[str | None] = mapped_column(String(128), unique=True, nullable=True, index=True)
    phone: Mapped[str | None] = mapped_column(String(20), nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    bio: Mapped[str | None] = mapped_column(Text, nullable=True)
    preferred_language: Mapped[LanguageCode] = mapped_column(
        SAEnum(
            LanguageCode,
            values_callable=lambda enum_cls: [item.value for item in enum_cls],
            name="language_code",
            create_type=False,
        ),
        nullable=False,
        default=LanguageCode.ENGLISH,
    )
    role: Mapped[UserRole] = mapped_column(
        SAEnum(
            UserRole,
            values_callable=lambda enum_cls: [item.value for item in enum_cls],
            name="user_role",
            create_type=False,
        ),
        nullable=False,
        default=UserRole.USER,
    )
    is_online: Mapped[bool] = mapped_column(Boolean, default=False)
    last_seen: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    push_token: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow
    )

    # Relationships
    sent_messages: Mapped[list["Message"]] = relationship("Message", back_populates="sender", foreign_keys="Message.sender_id")
    contacts: Mapped[list["UserContact"]] = relationship("UserContact", foreign_keys="UserContact.user_id", back_populates="user")
    conversation_participants: Mapped[list["ConversationParticipant"]] = relationship("ConversationParticipant", back_populates="user")
    calls_initiated: Mapped[list["Call"]] = relationship("Call", back_populates="caller", foreign_keys="Call.caller_id")

    def __repr__(self) -> str:
        return f"<User {self.username} ({self.preferred_language})>"


class UserContact(Base):
    __tablename__ = "user_contacts"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    contact_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    nickname: Mapped[str | None] = mapped_column(String(100), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    # Relationships
    user: Mapped["User"] = relationship("User", foreign_keys=[user_id], back_populates="contacts")
    contact: Mapped["User"] = relationship("User", foreign_keys=[contact_id])


class UserSession(Base):
    __tablename__ = "user_sessions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    refresh_token: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    device_info: Mapped[dict | None] = mapped_column(JSONVariant, nullable=True)
    is_active: Mapped[bool] = mapped_column("is_valid", Boolean, default=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
