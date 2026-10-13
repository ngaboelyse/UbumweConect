from typing import List
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from sqlalchemy.orm import selectinload
import uuid
from datetime import datetime, timezone

from app.database import get_db
from app.models.chat import Conversation, ConversationParticipant
from app.models.call import Call, CallParticipant, CallType, CallStatus
from app.models.user import User
from app.schemas.call import CallCreate, CallResponse, WebRTCSignal, TURNCredentials
from app.websocket.manager import manager
from app.middleware.auth_middleware import get_current_user
from app.services.notification_service import notification_service
from app.config import settings

router = APIRouter(prefix="/calls", tags=["Calls"])


@router.post("", response_model=CallResponse, status_code=201)
async def initiate_call(
    data: CallCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Verify conversation access
    result = await db.execute(
        select(Conversation)
        .where(Conversation.id == data.conversation_id)
        .options(selectinload(Conversation.participants).selectinload(ConversationParticipant.user))
    )
    conversation = result.scalar_one_or_none()
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")

    participant_ids = [p.user_id for p in conversation.participants]
    if current_user.id not in participant_ids:
        raise HTTPException(status_code=403, detail="Access denied")

    call = Call(
        conversation_id=data.conversation_id,
        caller_id=current_user.id,
        call_type=CallType(data.call_type),
        status=CallStatus.RINGING,
    )
    db.add(call)
    await db.flush()

    caller_participant = CallParticipant(call_id=call.id, user_id=current_user.id)
    db.add(caller_participant)

    await db.commit()
    await db.refresh(call)

    # Notify other participants
    call_data = {
        "event": "incoming_call",
        "data": {
            "call_id": str(call.id),
            "caller_id": str(current_user.id),
            "caller_name": current_user.display_name,
            "caller_avatar": current_user.avatar_url,
            "call_type": data.call_type,
            "conversation_id": str(data.conversation_id),
        },
    }
    for participant in conversation.participants:
        if participant.user_id != current_user.id:
            await manager.send_personal_message(str(participant.user_id), call_data)
            # Push notification
            if participant.user and participant.user.push_token:
                await notification_service.send_call_notification(
                    caller_name=current_user.display_name,
                    caller_avatar=current_user.avatar_url,
                    recipient_push_token=participant.user.push_token,
                    call_type=data.call_type,
                    call_id=str(call.id),
                )

    return _call_response(call)


def _call_response(call: Call) -> CallResponse:
    """Serialize a Call from its column values only.
    Never touch `call.caller` / `call.participants` relationships here:
    lazy-loading them on an AsyncSession raises MissingGreenlet (500)."""
    return CallResponse(
        id=call.id,
        conversation_id=call.conversation_id,
        caller_id=call.caller_id,
        call_type=call.call_type.value if isinstance(call.call_type, CallType) else str(call.call_type),
        status=call.status.value if isinstance(call.status, CallStatus) else str(call.status),
        started_at=call.started_at,
        ended_at=call.ended_at,
        duration_seconds=call.duration_seconds,
        created_at=call.created_at,
    )


async def _get_call_for_user(call_id: uuid.UUID, db: AsyncSession, current_user: User) -> Call:
    """Fetch a call and verify current_user is the caller, a call participant,
    or a participant of the call's conversation (the callee is only added as a
    CallParticipant upon accept, so they must be authorized via the
    conversation membership). Raises 404/403."""
    result = await db.execute(
        select(Call).where(Call.id == call_id).options(selectinload(Call.participants))
    )
    call = result.scalar_one_or_none()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")

    is_caller = call.caller_id == current_user.id
    is_participant = any(p.user_id == current_user.id for p in call.participants)
    if not (is_caller or is_participant):
        # Fall back to conversation membership (callee ringing side).
        conv_result = await db.execute(
            select(ConversationParticipant).where(
                ConversationParticipant.conversation_id == call.conversation_id,
                ConversationParticipant.user_id == current_user.id,
            )
        )
        if conv_result.scalar_one_or_none() is None:
            raise HTTPException(status_code=403, detail="Access denied")
    return call


@router.put("/{call_id}/accept", response_model=CallResponse)
async def accept_call(
    call_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    call = await _get_call_for_user(call_id, db, current_user)

    if call.status not in (CallStatus.RINGING, CallStatus.CONNECTED):
        raise HTTPException(status_code=409, detail="Call is no longer available")

    call.status = CallStatus.CONNECTED
    call.started_at = call.started_at or datetime.utcnow()

    # Only create a participant record if this user hasn't joined yet
    existing = next((p for p in call.participants if p.user_id == current_user.id), None)
    if not existing:
        participant = CallParticipant(call_id=call.id, user_id=current_user.id, joined_at=datetime.utcnow())
        db.add(participant)
    elif not existing.joined_at:
        existing.joined_at = datetime.utcnow()

    await db.commit()
    await db.refresh(call)

    # Notify caller
    await manager.send_personal_message(
        str(call.caller_id),
        {"event": "call_accepted", "data": {"call_id": str(call_id), "user_id": str(current_user.id)}}
    )

    return _call_response(call)


@router.put("/{call_id}/reject", response_model=CallResponse)
async def reject_call(
    call_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    call = await _get_call_for_user(call_id, db, current_user)

    call.status = CallStatus.REJECTED
    call.ended_at = datetime.utcnow()
    await db.commit()
    await db.refresh(call)

    await manager.send_personal_message(
        str(call.caller_id),
        {"event": "call_rejected", "data": {"call_id": str(call_id), "user_id": str(current_user.id)}}
    )

    return _call_response(call)


@router.put("/{call_id}/end", response_model=CallResponse)
async def end_call(
    call_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    call = await _get_call_for_user(call_id, db, current_user)

    now = datetime.now(timezone.utc)
    call.status = CallStatus.ENDED
    call.ended_at = now
    if call.started_at:
        # started_at may be naive (legacy rows) or timezone-aware (from DB).
        started = call.started_at
        if started.tzinfo is None:
            started = started.replace(tzinfo=timezone.utc)
        call.duration_seconds = int((now - started).total_seconds())

    for p in call.participants:
        if not p.left_at:
            p.left_at = datetime.utcnow()

    await db.commit()
    await db.refresh(call)

    # Notify all participants
    for p in call.participants:
        if p.user_id != current_user.id:
            await manager.send_personal_message(
                str(p.user_id),
                {"event": "call_ended", "data": {"call_id": str(call_id)}}
            )

    return _call_response(call)


@router.get("/history", response_model=List[CallResponse])
async def call_history(
    limit: int = 20,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Call)
        .join(CallParticipant, CallParticipant.call_id == Call.id)
        .where(CallParticipant.user_id == current_user.id)
        .order_by(desc(Call.created_at))
        .limit(limit)
    )
    calls = result.scalars().all()
    return [_call_response(c) for c in calls]


@router.post("/{call_id}/signal")
async def webrtc_signal(
    call_id: uuid.UUID,
    signal: WebRTCSignal,
    current_user: User = Depends(get_current_user),
):
    """Forward WebRTC signaling messages between peers."""
    await manager.send_call_signal(
        str(signal.to_user_id),
        {
            "signal_type": signal.signal_type,
            "sdp": signal.sdp,
            "candidate": signal.candidate,
            "from_user_id": str(current_user.id),
            "call_id": str(call_id),
        },
    )
    return {"status": "signal sent"}


@router.get("/turn-credentials", response_model=TURNCredentials)
async def get_turn_credentials(current_user: User = Depends(get_current_user)):
    """Get TURN/STUN server credentials for WebRTC."""
    urls = []
    if settings.TURN_SERVER_URL:
        urls.append(settings.TURN_SERVER_URL)
        urls.append(settings.TURN_SERVER_URL.replace("turn:", "stun:"))
    # Always include a public STUN server so peers behind different NATs can
    # at least discover their public address even when TURN is not configured.
    if not any(u.startswith("stun:") for u in urls):
        urls.append("stun:stun.l.google.com:19302")
    return TURNCredentials(
        urls=urls,
        username=settings.TURN_USERNAME,
        credential=settings.TURN_PASSWORD,
    )
