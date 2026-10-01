from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, Dict, List, Any
from datetime import datetime
import uuid
from app.schemas.user import UserProfile


class ConversationCreate(BaseModel):
    type: str = Field(default="direct", pattern=r"^(direct|group)$")
    participant_ids: List[uuid.UUID] = Field(..., min_length=1)
    name: Optional[str] = Field(None, max_length=100)
    description: Optional[str] = None


class ConversationUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=100)
    description: Optional[str] = None
    avatar_url: Optional[str] = None


class ParticipantResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    role: str
    joined_at: datetime
    last_read_at: Optional[datetime] = None
    # Coerce the ORM User into the public profile schema so serialization works
    user: Optional[UserProfile] = None


class MessageCreate(BaseModel):
    content: str = Field(..., min_length=1, max_length=5000)
    message_type: str = Field(default="text", pattern=r"^(text|image|file|voice|system)$")
    reply_to_id: Optional[uuid.UUID] = None
    # Media attachments (URL comes from the upload endpoint)
    media_url: Optional[str] = None
    file_name: Optional[str] = Field(None, max_length=255)
    file_size: Optional[int] = None
    duration_seconds: Optional[float] = None


class MessageEdit(BaseModel):
    """Edit a text message's content."""
    content: str = Field(..., min_length=1, max_length=5000)


class ReactionCreate(BaseModel):
    emoji: str = Field(..., min_length=1, max_length=16)


class MessageReactionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    emoji: str
    created_at: datetime


class MessageResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    conversation_id: uuid.UUID
    sender_id: uuid.UUID
    message_type: str
    original_content: Optional[str] = None
    original_language: Optional[str] = None
    translated_contents: Optional[Dict[str, str]] = None
    audio_url: Optional[str] = None
    file_url: Optional[str] = None
    file_name: Optional[str] = None
    file_size: Optional[int] = None
    duration_seconds: Optional[float] = None
    is_deleted: bool
    is_edited: bool = False
    reply_to_id: Optional[uuid.UUID] = None
    created_at: datetime
    updated_at: datetime
    sender: Optional[UserProfile] = None
    status: Optional[str] = None
    reactions: List[MessageReactionResponse] = []


class ConversationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    type: str
    name: Optional[str] = None
    description: Optional[str] = None
    avatar_url: Optional[str] = None
    created_by: Optional[uuid.UUID] = None
    created_at: datetime
    updated_at: datetime
    participants: List[ParticipantResponse] = []
    last_message: Optional[MessageResponse] = None
    unread_count: int = 0


class PaginatedMessages(BaseModel):
    messages: List[MessageResponse]
    next_cursor: Optional[str] = None
    has_more: bool = False
    total: int = 0


class MessageStatusUpdate(BaseModel):
    message_id: uuid.UUID
    status: str = Field(..., pattern=r"^(sent|delivered|read)$")


class TypingIndicator(BaseModel):
    conversation_id: uuid.UUID
    user_id: uuid.UUID
    is_typing: bool


class AddParticipantRequest(BaseModel):
    user_id: uuid.UUID
    role: str = Field(default="member", pattern=r"^(admin|member)$")
