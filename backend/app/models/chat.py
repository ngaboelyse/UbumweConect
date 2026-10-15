import uuid
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, Text, ForeignKey, Enum as SAEnum, Integer, Float
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy import JSON

# JSONB variant: PostgreSQL gets native JSONB, other dialects (SQLite tests) fall back to JSON.
def _json_variant() -> JSON:
    return JSON().with_variant(JSONB, "postgresql")

JSONVariant = _json_variant()

import enum

from app.database import Base


class ConversationType(str, enum.Enum):
    DIRECT = "direct"
    GROUP = "group"


class MessageType(str, enum.Enum):
    TEXT = "text"
    VOICE = "voice"
    IMAGE = "image"
    FILE = "file"
    SYSTEM = "system"


class MessageStatusType(str, enum.Enum):
    SENT = "sent"
    DELIVERED = "delivered"
    READ = "read"


class ParticipantRole(str, enum.Enum):
    ADMIN = "admin"
    MEMBER = "member"


class Conversation(Base):
    __tablename__ = "conversations"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    type: Mapped[ConversationType] = mapped_column(
        SAEnum(ConversationType, values_callable=lambda enum_cls: [item.value for item in enum_cls],
               name="conversation_type", create_type=False),
        nullable=False,
        default=ConversationType.DIRECT,
    )
    name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow
    )

    # Relationships
    participants: Mapped[list["ConversationParticipant"]] = relationship("ConversationParticipant", back_populates="conversation", cascade="all, delete-orphan")
    messages: Mapped[list["Message"]] = relationship("Message", back_populates="conversation", cascade="all, delete-orphan")
    calls: Mapped[list["Call"]] = relationship("Call", back_populates="conversation", cascade="all, delete-orphan")

    def __repr__(self) -> str:
        return f"<Conversation {self.id} ({self.type})>"


class ConversationParticipant(Base):
    __tablename__ = "conversation_participants"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    conversation_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    role: Mapped[ParticipantRole] = mapped_column(
        SAEnum(ParticipantRole, values_callable=lambda enum_cls: [item.value for item in enum_cls],
               name="participant_role", create_type=False),
        nullable=False,
        default=ParticipantRole.MEMBER,
    )
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    last_read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    # Relationships
    conversation: Mapped["Conversation"] = relationship("Conversation", back_populates="participants")
    user: Mapped["User"] = relationship("User", back_populates="conversation_participants")


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    conversation_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False, index=True)
    sender_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    message_type: Mapped[MessageType] = mapped_column(
        SAEnum(MessageType, values_callable=lambda enum_cls: [item.value for item in enum_cls],
               name="message_type", create_type=False),
        nullable=False,
        default=MessageType.TEXT,
    )
    original_content: Mapped[str | None] = mapped_column(Text, nullable=True)
    original_language: Mapped[str | None] = mapped_column(String(20), nullable=True)
    # Stores translations as {"english": "...", "french": "...", "kinyarwanda": "...", "swahili": "..."}
    translated_contents: Mapped[dict | None] = mapped_column(JSONVariant, nullable=True, default=dict)
    audio_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    file_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    file_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    file_size: Mapped[int | None] = mapped_column(Integer, nullable=True)
    duration_seconds: Mapped[float | None] = mapped_column(Float, nullable=True)
    is_edited: Mapped[bool] = mapped_column(Boolean, default=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    reply_to_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("messages.id", ondelete="SET NULL"), nullable=True)
    extra_metadata: Mapped[dict | None] = mapped_column("metadata", JSONVariant, nullable=True, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, index=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow
    )

    # Relationships
    conversation: Mapped["Conversation"] = relationship("Conversation", back_populates="messages")
    sender: Mapped["User"] = relationship("User", back_populates="sent_messages", foreign_keys=[sender_id])
    statuses: Mapped[list["MessageStatus"]] = relationship("MessageStatus", back_populates="message", cascade="all, delete-orphan")
    reactions: Mapped[list["MessageReaction"]] = relationship("MessageReaction", back_populates="message", cascade="all, delete-orphan")
    reply_to: Mapped["Message | None"] = relationship("Message", remote_side="Message.id", foreign_keys=[reply_to_id])

    def get_content_for_language(self, language: str) -> str:
        """Return the translation for the given language, or original content."""
        if self.translated_contents and language in self.translated_contents:
            return self.translated_contents[language]
        return self.original_content or ""

    def __repr__(self) -> str:
        return f"<Message {self.id} ({self.message_type})>"


class MessageStatus(Base):
    __tablename__ = "message_statuses"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    message_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("messages.id", ondelete="CASCADE"), nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    status: Mapped[MessageStatusType] = mapped_column(
        SAEnum(MessageStatusType, values_callable=lambda enum_cls: [item.value for item in enum_cls],
               name="message_status", create_type=False),
        nullable=False,
        default=MessageStatusType.SENT,
    )
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    message: Mapped["Message"] = relationship("Message", back_populates="statuses")


class MessageReaction(Base):
    __tablename__ = "message_reactions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    message_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("messages.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    emoji: Mapped[str] = mapped_column(String(16), nullable=False)  # e.g. "❤️", "👍", "😂"
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    # Relationships
    message: Mapped["Message"] = relationship("Message", back_populates="reactions")
    user: Mapped["User"] = relationship("User", foreign_keys=[user_id])
