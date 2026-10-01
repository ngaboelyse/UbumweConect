from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List, Any
from datetime import datetime
import uuid


class CallCreate(BaseModel):
    conversation_id: uuid.UUID
    call_type: str = Field(..., pattern=r"^(voice|video)$")


class CallResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    conversation_id: uuid.UUID
    caller_id: uuid.UUID
    call_type: str
    status: str
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    duration_seconds: Optional[int] = None
    created_at: datetime
    caller: Optional[Any] = None
    participants: List[Any] = []


class CallUpdate(BaseModel):
    status: str = Field(..., pattern=r"^(ringing|active|ended|missed|rejected)$")


class WebRTCSignal(BaseModel):
    signal_type: str = Field(..., pattern=r"^(offer|answer|ice-candidate|hangup)$")
    sdp: Optional[str] = None
    candidate: Optional[dict] = None
    from_user_id: uuid.UUID
    to_user_id: uuid.UUID
    call_id: uuid.UUID


class TURNCredentials(BaseModel):
    urls: List[str]
    username: str
    credential: str


class CallParticipantResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    call_id: uuid.UUID
    user_id: uuid.UUID
    joined_at: Optional[datetime] = None
    left_at: Optional[datetime] = None
    is_muted: bool
    is_video_on: bool
