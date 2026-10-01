from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, desc, func, or_, cast, String
from sqlalchemy.orm import selectinload
import uuid
import logging
from datetime import datetime, timedelta

from app.database import get_db
from app.models.chat import (
    Conversation, ConversationParticipant, Message, MessageStatus,
    ConversationType, MessageType, MessageStatusType, ParticipantRole, MessageReaction,
)
from app.models.user import User
from app.schemas.chat import (
    ConversationCreate, ConversationResponse, ConversationUpdate,
    MessageCreate, MessageResponse, PaginatedMessages, AddParticipantRequest,
    MessageEdit, ReactionCreate,
)
from app.services.translation_service import translate_message_for_all_languages, detect_language
from app.services.file_service import FileService
from app.services.notification_service import notification_service
from app.websocket.manager import manager
from app.middleware.auth_middleware import get_current_user

router = APIRouter(prefix="/conversations", tags=["Conversations"])
file_service = FileService()


async def _get_message_full(
    db: AsyncSession,
    message_id: uuid.UUID,
) -> Message:
    """Re-fetch a message with relationships eagerly loaded, so Pydantic
    serialization never triggers lazy IO (MissingGreenlet) after commit."""
    result = await db.execute(
        select(Message)
        .where(Message.id == message_id)
        .options(
            selectinload(Message.reactions),
            selectinload(Message.sender),
            selectinload(Message.statuses),
        )
    )
    return result.scalar_one()


@router.get("", response_model=List[ConversationResponse])
async def list_conversations(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Conversation)
        .join(ConversationParticipant, ConversationParticipant.conversation_id == Conversation.id)
        .where(ConversationParticipant.user_id == current_user.id)
        .options(selectinload(Conversation.participants).selectinload(ConversationParticipant.user))
        .order_by(desc(Conversation.updated_at))
    )
    conversations = result.scalars().unique().all()

    # Compute unread counts (messages after this user's last_read_at, not their own)
    conv_ids = [c.id for c in conversations]
    unread_by_conv: dict = {}
    if conv_ids:
        unread_rows = await db.execute(
            select(Message.conversation_id, func.count(Message.id))
            .join(
                ConversationParticipant,
                (ConversationParticipant.conversation_id == Message.conversation_id)
                & (ConversationParticipant.user_id == current_user.id),
            )
            .where(
                Message.conversation_id.in_(conv_ids),
                Message.is_deleted == False,
                Message.sender_id != current_user.id,
                or_(
                    ConversationParticipant.last_read_at == None,  # noqa: E711
                    Message.created_at > ConversationParticipant.last_read_at,
                ),
            )
            .group_by(Message.conversation_id)
        )
        unread_by_conv = {row[0]: row[1] for row in unread_rows.all()}

    responses = []
    for c in conversations:
        resp = ConversationResponse.model_validate(c)
        resp.unread_count = unread_by_conv.get(c.id, 0)
        responses.append(resp)
    return responses


@router.post("", response_model=ConversationResponse, status_code=201)
async def create_conversation(
    data: ConversationCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    conv_type = ConversationType(data.type)

    if conv_type == ConversationType.DIRECT and len(data.participant_ids) != 1:
        raise HTTPException(status_code=400, detail="Direct conversation requires exactly 1 participant")

    conversation = Conversation(
        type=conv_type,
        name=data.name,
        description=data.description,
        created_by=current_user.id,
    )
    db.add(conversation)
    await db.flush()

    # Add creator as admin
    creator_participant = ConversationParticipant(
        conversation_id=conversation.id,
        user_id=current_user.id,
        role=ParticipantRole.ADMIN,
    )
    db.add(creator_participant)

    # Add other participants
    for participant_id in data.participant_ids:
        if participant_id == current_user.id:
            continue
        p = ConversationParticipant(
            conversation_id=conversation.id,
            user_id=participant_id,
            role=ParticipantRole.MEMBER,
        )
        db.add(p)

    await db.commit()
    await db.refresh(conversation)

    result = await db.execute(
        select(Conversation)
        .where(Conversation.id == conversation.id)
        .options(selectinload(Conversation.participants).selectinload(ConversationParticipant.user))
    )
    conv = result.scalar_one()
    return ConversationResponse.model_validate(conv)


@router.get("/search", response_model=List[ConversationResponse])
async def search_conversations(
    q: str = Query(..., min_length=1),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Search the user's conversations by name or message content."""
    result = await db.execute(
        select(Conversation)
        .join(ConversationParticipant, ConversationParticipant.conversation_id == Conversation.id)
        .outerjoin(Message, Message.conversation_id == Conversation.id)
        .where(
            ConversationParticipant.user_id == current_user.id,
            or_(
                Conversation.name.ilike(f"%{q}%"),
                Message.original_content.ilike(f"%{q}%"),
            ),
        )
        .distinct()
        .options(selectinload(Conversation.participants).selectinload(ConversationParticipant.user))
        .order_by(desc(Conversation.updated_at))
        .limit(20)
    )
    conversations = result.scalars().unique().all()
    return [ConversationResponse.model_validate(c) for c in conversations]


@router.get("/{conversation_id}", response_model=ConversationResponse)
async def get_conversation(
    conversation_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Conversation)
        .where(Conversation.id == conversation_id)
        .options(selectinload(Conversation.participants).selectinload(ConversationParticipant.user))
    )
    conv = result.scalar_one_or_none()
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found")

    # Check access
    participant_ids = [p.user_id for p in conv.participants]
    if current_user.id not in participant_ids:
        raise HTTPException(status_code=403, detail="Access denied")

    return ConversationResponse.model_validate(conv)


@router.get("/{conversation_id}/messages", response_model=PaginatedMessages)
async def list_messages(
    conversation_id: uuid.UUID,
    cursor: Optional[str] = None,
    limit: int = Query(default=50, le=100),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Verify access
    result = await db.execute(
        select(ConversationParticipant).where(
            ConversationParticipant.conversation_id == conversation_id,
            ConversationParticipant.user_id == current_user.id,
        )
    )
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=403, detail="Access denied")

    query = select(Message).where(
        Message.conversation_id == conversation_id,
        Message.is_deleted == False,
    )

    if cursor:
        try:
            cursor_dt = datetime.fromisoformat(cursor)
            query = query.where(Message.created_at < cursor_dt)
        except ValueError:
            pass

    query = query.order_by(desc(Message.created_at)).limit(limit + 1)
    result = await db.execute(query.options(
        selectinload(Message.sender),
        selectinload(Message.reactions),
        selectinload(Message.statuses),
    ))
    messages = result.scalars().all()

    has_more = len(messages) > limit
    if has_more:
        messages = messages[:limit]

    next_cursor = None
    if has_more and messages:
        next_cursor = messages[-1].created_at.isoformat()

    return PaginatedMessages(
        messages=[MessageResponse.model_validate(m) for m in messages],
        next_cursor=next_cursor,
        has_more=has_more,
        total=len(messages),
    )


@router.post("/{conversation_id}/messages", response_model=MessageResponse, status_code=201)
async def send_message(
    conversation_id: uuid.UUID,
    data: MessageCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Verify access
    result = await db.execute(
        select(Conversation)
        .where(Conversation.id == conversation_id)
        .options(selectinload(Conversation.participants).selectinload(ConversationParticipant.user))
    )
    conversation = result.scalar_one_or_none()
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")

    participant_ids = [p.user_id for p in conversation.participants]
    if current_user.id not in participant_ids:
        raise HTTPException(status_code=403, detail="Access denied")

    # Detect language (use user's preferred language as source)
    source_language = current_user.preferred_language.value

    # Create message
    message = Message(
        conversation_id=conversation_id,
        sender_id=current_user.id,
        message_type=MessageType(data.message_type),
        original_content=data.content,
        original_language=source_language,
        reply_to_id=data.reply_to_id,
        file_url=data.media_url if data.message_type in ("image", "file", "voice") else None,
        audio_url=data.media_url if data.message_type == "voice" else None,
        file_name=data.file_name,
        file_size=data.file_size,
        duration_seconds=data.duration_seconds,
    )
    db.add(message)
    await db.flush()

    # Translate to all participant languages (text messages only).
    # A translation outage must never block the message itself.
    if data.message_type == "text":
        try:
            translations = await translate_message_for_all_languages(
                data.content,
                source_language,
                db,
            )
        except Exception as e:
            logging.getLogger("app").warning("Translation failed, delivering untranslated: %s", e)
            translations = {source_language: data.content}
        message.translated_contents = translations

    # Update conversation timestamp
    conversation.updated_at = datetime.utcnow()

    await db.commit()
    message = await _get_message_full(db, message.id)

    message_response = MessageResponse.model_validate(message)
    message_dict = message_response.model_dump(mode="json")

    # Broadcast via WebSocket
    await manager.send_new_message(
        str(conversation_id),
        message_dict,
        exclude_user=str(current_user.id),
    )

    # Push notification for participants who are offline or not in the room
    for participant in conversation.participants:
        if participant.user_id == current_user.id or not participant.user:
            continue
        delivered = manager.is_connected(str(participant.user_id))
        if delivered and participant.user.push_token:
            # Online user may still want a push if app is backgrounded;
            # only send when they are not in the conversation room
            in_room = str(conversation_id) in manager.get_user_rooms(str(participant.user_id))
            if in_room:
                continue
        translated = (message.translated_contents or {}).get(
            participant.user.preferred_language.value, data.content
        )
        if participant.user.push_token:
            await notification_service.send_message_notification(
                sender_name=current_user.display_name,
                sender_avatar=current_user.avatar_url,
                recipient_push_token=participant.user.push_token,
                translated_message=translated,
                conversation_id=str(conversation_id),
            )

    return message_response


@router.delete("/{conversation_id}/messages/{message_id}", status_code=204)
async def delete_message(
    conversation_id: uuid.UUID,
    message_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Message).where(
            Message.id == message_id,
            Message.conversation_id == conversation_id,
        )
    )
    message = result.scalar_one_or_none()
    if not message:
        raise HTTPException(status_code=404, detail="Message not found")
    if message.sender_id != current_user.id:
        raise HTTPException(status_code=403, detail="Cannot delete another user's message")

    message.is_deleted = True
    message.original_content = None
    await db.commit()


@router.post("/{conversation_id}/messages/{message_id}/read", status_code=204)
async def mark_as_read(
    conversation_id: uuid.UUID,
    message_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(MessageStatus).where(
            MessageStatus.message_id == message_id,
            MessageStatus.user_id == current_user.id,
        )
    )
    status_record = result.scalar_one_or_none()
    if status_record:
        status_record.status = MessageStatusType.READ
    else:
        status_record = MessageStatus(
            message_id=message_id,
            user_id=current_user.id,
            status=MessageStatusType.READ,
        )
        db.add(status_record)

    await db.commit()

    # Notify sender via WebSocket
    msg_result = await db.execute(select(Message).where(Message.id == message_id))
    message = msg_result.scalar_one_or_none()
    if message:
        await manager.send_message_status(
            str(message.sender_id), str(message_id), "read"
        )


@router.put("/{conversation_id}/messages/{message_id}", response_model=MessageResponse)
async def edit_message(
    conversation_id: uuid.UUID,
    message_id: uuid.UUID,
    data: MessageEdit,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Edit a text message. Only the sender can edit, within 15 minutes."""
    result = await db.execute(
        select(Message).where(
            Message.id == message_id,
            Message.conversation_id == conversation_id,
            Message.is_deleted == False,
        )
    )
    message = result.scalar_one_or_none()
    if not message:
        raise HTTPException(status_code=404, detail="Message not found")
    if message.sender_id != current_user.id:
        raise HTTPException(status_code=403, detail="Cannot edit another user's message")
    if message.message_type != MessageType.TEXT:
        raise HTTPException(status_code=400, detail="Only text messages can be edited")

    EDIT_WINDOW = timedelta(minutes=15)
    message_created = message.created_at
    if message_created.tzinfo is not None:
        message_created = message_created.replace(tzinfo=None)
    if datetime.utcnow() - message_created > EDIT_WINDOW:
        raise HTTPException(status_code=400, detail="Edit window (15 minutes) has expired")

    message.original_content = data.content
    message.is_edited = True

    # Re-translate with the new content (non-fatal on failure)
    try:
        translations = await translate_message_for_all_languages(
            data.content,
            message.original_language or current_user.preferred_language.value,
            db,
        )
        message.translated_contents = translations
    except Exception as e:
        logging.getLogger("app").warning("Translation on edit failed: %s", e)

    await db.commit()
    db.expire(message, attribute_names=["reactions"])
    message = await _get_message_full(db, message.id)

    message_dict = MessageResponse.model_validate(message).model_dump(mode="json")
    await manager.broadcast_to_conversation(
        str(conversation_id),
        {"event": "message_updated", "data": message_dict},
        exclude_user=str(current_user.id),
    )
    return MessageResponse.model_validate(message)


@router.get("/{conversation_id}/messages/search", response_model=List[MessageResponse])
async def search_messages(
    conversation_id: uuid.UUID,
    q: str = Query(..., min_length=2),
    limit: int = Query(default=20, le=50),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Search messages in a conversation (content + translated contents)."""
    await _require_participant(conversation_id, db, current_user)

    result = await db.execute(
        select(Message)
        .where(
            Message.conversation_id == conversation_id,
            Message.is_deleted == False,
            or_(
                Message.original_content.ilike(f"%{q}%"),
                # Search inside translated JSON contents (works on PG & SQLite)
                cast(Message.translated_contents, String).ilike(f"%{q}%"),
            ),
        )
        .order_by(desc(Message.created_at))
        .limit(limit)
        .options(
            selectinload(Message.sender),
            selectinload(Message.reactions),
            selectinload(Message.statuses),
        )
    )
    messages = result.scalars().unique().all()
    return [MessageResponse.model_validate(m) for m in messages]


@router.post("/{conversation_id}/read", status_code=204)
async def mark_conversation_read(
    conversation_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Mark all messages in a conversation as read for the current user."""
    participant = await _require_participant(conversation_id, db, current_user)
    now = datetime.utcnow()
    participant.last_read_at = now

    # Mark every message (up to now) as READ for this user
    result = await db.execute(
        select(Message.id).where(
            Message.conversation_id == conversation_id,
            Message.is_deleted == False,
            Message.created_at <= now,
        )
    )
    message_ids = [row[0] for row in result.all()]

    if message_ids:
        existing = await db.execute(
            select(MessageStatus.message_id).where(
                MessageStatus.user_id == current_user.id,
                MessageStatus.message_id.in_(message_ids),
                MessageStatus.status == MessageStatusType.READ,
            )
        )
        already_read = {row[0] for row in existing.all()}

        for mid in message_ids:
            if mid in already_read:
                continue
            existing_status = await db.execute(
                select(MessageStatus).where(
                    MessageStatus.message_id == mid,
                    MessageStatus.user_id == current_user.id,
                )
            )
            record = existing_status.scalar_one_or_none()
            if record:
                record.status = MessageStatusType.READ
            else:
                db.add(MessageStatus(message_id=mid, user_id=current_user.id, status=MessageStatusType.READ))

    await db.commit()

    # Notify conversation room that this user read up to `now`
    await manager.broadcast_to_conversation(
        str(conversation_id),
        {"event": "messages_read", "data": {"conversation_id": str(conversation_id), "user_id": str(current_user.id), "read_at": now.isoformat()}},
        exclude_user=str(current_user.id),
    )


# ─── Attachments ───────────────────────────────────────────────

ALLOWED_ATTACHMENT_TYPES = {
    "image": ["jpg", "jpeg", "png", "webp", "gif"],
    "file": ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "csv", "zip"],
    "voice": ["m4a", "mp3", "aac", "ogg", "wav", "webm"],
}


@router.post("/{conversation_id}/attachments")
async def upload_attachment(
    conversation_id: uuid.UUID,
    file: UploadFile = File(...),
    kind: str = Query(default="file", pattern=r"^(image|file|voice)$"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Upload a media attachment for a message. Returns the URL to send
    as `media_url` in POST /{id}/messages."""
    await _require_participant(conversation_id, db, current_user)

    filename = file.filename or "upload.bin"
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    allowed = ALLOWED_ATTACHMENT_TYPES.get(kind, [])

    if ext not in allowed:
        raise HTTPException(status_code=400, detail=f"Invalid {kind} type. Allowed: {', '.join(allowed)}")

    max_mb = {"image": 10, "file": 25, "voice": 15}.get(kind, 25)
    data = await file.read()
    if len(data) > max_mb * 1024 * 1024:
        raise HTTPException(status_code=400, detail=f"File too large. Max {max_mb}MB")

    try:
        url = await file_service.upload_bytes(
            data=data,
            filename=f"{uuid.uuid4()}_{filename}",
            folder=f"attachments/{kind}",
            content_type=file.content_type or "application/octet-stream",
        )
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))

    return {"url": url, "file_name": filename, "file_size": len(data), "kind": kind}


# ─── Reactions ──────────────────────────────────────────────────


@router.post("/{conversation_id}/messages/{message_id}/reactions", response_model=MessageResponse)
async def react_to_message(
    conversation_id: uuid.UUID,
    message_id: uuid.UUID,
    data: ReactionCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Add or replace the current user's reaction on a message."""
    await _require_participant(conversation_id, db, current_user)

    result = await db.execute(
        select(Message).where(
            Message.id == message_id,
            Message.conversation_id == conversation_id,
            Message.is_deleted == False,
        ).options(selectinload(Message.reactions))
    )
    message = result.scalar_one_or_none()
    if not message:
        raise HTTPException(status_code=404, detail="Message not found")

    existing = next(
        (r for r in message.reactions if r.user_id == current_user.id and r.emoji == data.emoji),
        None,
    )
    if existing:
        # Toggling the same emoji removes it
        await db.delete(existing)
        action = "removed"
    else:
        # Replace any previous reaction by this user with the new emoji
        for r in [r for r in message.reactions if r.user_id == current_user.id]:
            await db.delete(r)
        db.add(MessageReaction(message_id=message.id, user_id=current_user.id, emoji=data.emoji))
        action = "added"

    await db.commit()
    db.expire(message, attribute_names=["reactions"])
    message = await _get_message_full(db, message.id)

    payload = MessageResponse.model_validate(message).model_dump(mode="json")
    await manager.broadcast_to_conversation(
        str(conversation_id),
        {"event": "message_updated", "data": payload},
    )
    return MessageResponse.model_validate(message)


# ─── Shared helpers ─────────────────────────────────────────────


async def _require_participant(
    conversation_id: uuid.UUID,
    db: AsyncSession,
    current_user: User,
) -> ConversationParticipant:
    result = await db.execute(
        select(ConversationParticipant).where(
            ConversationParticipant.conversation_id == conversation_id,
            ConversationParticipant.user_id == current_user.id,
        )
    )
    participant = result.scalar_one_or_none()
    if not participant:
        raise HTTPException(status_code=403, detail="Access denied")
    return participant
