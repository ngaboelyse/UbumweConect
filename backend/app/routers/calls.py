from typing import List
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from sqlalchemy.orm import selectinload
import uuid
from datetime import datetime

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

    return CallResponse.model_validate(call)


async def _get_call_for_user(call_id: uuid.UUID, db: AsyncSession, current_user: User) -> Call:
    """Fetch a call and verify current_user is a caller or an existing participant.
    Raises 404/403."""
    result = await db.execute(
        select(Call).where(Call.id == call_id).options(selectinload(Call.participants))
    )
    call = result.scalar_one_or_none()
    if not call:
        raise HTTPException(status_code=404, detail="Call not found")

    is_caller = call.caller_id == current_user.id
    is_participant = any(p.user_id == current_user.id for p in call.participants)
    if not (is_caller or is_participant):
        raise HTTPException(status_code=403, detail="Access denied")
    return call


@router.put("/{call_id}/accept", response_model=CallResponse)
async def accept_call(
    call_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    call = await _get_call_for_user(call_id, db, current_user)

    if call.status not in (CallStatus.RINGING, CallStatus.ACTIVE):
        raise HTTPException(status_code=409, detail="Call is no longer available")

    call.status = CallStatus.ACTIVE
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

    return CallResponse.model_validate(call)


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

    return CallResponse.model_validate(call)


@router.put("/{call_id}/end", response_model=CallResponse)
async def end_call(
    call_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    call = await _get_call_for_user(call_id, db, current_user)

    call.status = CallStatus.ENDED
    call.ended_at = datetime.utcnow()
    if call.started_at:
        call.duration_seconds = int((call.ended_at - call.started_at).total_seconds())

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

    return CallResponse.model_validate(call)


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
    return [CallResponse.model_validate(c) for c in calls]


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
    """Get TURN server credentials for WebRTC."""
    return TURNCredentials(
        urls=[settings.TURN_SERVER_URL, settings.TURN_SERVER_URL.replace("turn:", "stun:")],
        username=settings.TURN_USERNAME,
        credential=settings.TURN_PASSWORD,
    )
