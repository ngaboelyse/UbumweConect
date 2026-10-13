import uuid
from datetime import datetime
from sqlalchemy import String, Boolean, DateTime, ForeignKey, Enum as SAEnum, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
import enum

from app.database import Base


class CallType(str, enum.Enum):
    VOICE = "voice"
    VIDEO = "video"


class CallStatus(str, enum.Enum):
    RINGING = "ringing"
    CONNECTED = "connected"
    ENDED = "ended"
    MISSED = "missed"
    REJECTED = "rejected"


class Call(Base):
    __tablename__ = "calls"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    conversation_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False)
    caller_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    call_type: Mapped[CallType] = mapped_column(
        SAEnum(CallType, values_callable=lambda enum_cls: [item.value for item in enum_cls],
               name="call_type", create_type=False),
        nullable=False,
    )
    status: Mapped[CallStatus] = mapped_column(
        SAEnum(CallStatus, values_callable=lambda enum_cls: [item.value for item in enum_cls],
               name="call_status", create_type=False),
        nullable=False,
        default=CallStatus.RINGING,
    )
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    duration_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    # Relationships
    conversation: Mapped["Conversation"] = relationship("Conversation", back_populates="calls")
    caller: Mapped["User"] = relationship("User", back_populates="calls_initiated", foreign_keys=[caller_id])
    participants: Mapped[list["CallParticipant"]] = relationship("CallParticipant", back_populates="call", cascade="all, delete-orphan")

    def __repr__(self) -> str:
        return f"<Call {self.id} ({self.call_type}, {self.status})>"


class CallParticipant(Base):
    __tablename__ = "call_participants"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    call_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("calls.id", ondelete="CASCADE"), nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    joined_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    left_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    is_muted: Mapped[bool] = mapped_column(Boolean, default=False)
    is_video_on: Mapped[bool] = mapped_column(Boolean, default=True)

    # Relationships
    call: Mapped["Call"] = relationship("Call", back_populates="participants")
