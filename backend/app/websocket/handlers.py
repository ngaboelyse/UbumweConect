import json
import base64
from fastapi import WebSocket, WebSocketDisconnect
from app.websocket.manager import manager
from app.services.auth_service import update_online_status, decode_token
from app.services.gemini_live_service import (
    live_translation_manager,
    GEMINI_VOICES,
    DEFAULT_VOICE,
)


async def websocket_endpoint(websocket: WebSocket, user_id: str, token: str):
    """Main WebSocket handler for a connected user."""
    # Verify token
    try:
        payload = decode_token(token)
        token_user_id = payload.get("sub")
        if token_user_id != user_id:
            await websocket.close(code=4003, reason="Unauthorized")
            return
    except ValueError:
        await websocket.close(code=4001, reason="Invalid token")
        return

    await manager.connect(user_id, websocket)

    from app.database import AsyncSessionLocal
    async with AsyncSessionLocal() as db:
        await update_online_status(db, user_id, True)
        await db.commit()

    try:
        while True:
            raw_data = await websocket.receive_text()
            try:
                data = json.loads(raw_data)
                event = data.get("event")
                payload = data.get("data", {})

                if event == "join_conversation":
                    await handle_join_conversation(user_id, payload)
                elif event == "leave_conversation":
                    await handle_leave_conversation(user_id, payload)
                elif event == "typing":
                    await handle_typing(user_id, payload)
                elif event == "read_receipt":
                    await handle_read_receipt(user_id, payload)
                elif event == "call_signal":
                    await handle_call_signal(user_id, payload)
                elif event == "voice_translation_start":
                    await handle_voice_translation_start(user_id, payload)
                elif event == "voice_translation_stop":
                    await handle_voice_translation_stop(user_id, payload)
                elif event == "voice_translation_audio":
                    await handle_voice_translation_audio(user_id, payload)
                elif event == "voice_translation_stream_start":
                    await handle_voice_translation_stream_start(user_id, payload)
                elif event == "voice_translation_stream_stop":
                    await handle_voice_translation_stream_stop(user_id, payload)
                elif event == "ping":
                    await manager.send_personal_message(user_id, {"event": "pong", "data": {}})
                else:
                    await manager.send_personal_message(
                        user_id,
                        {"event": "error", "data": {"message": f"Unknown event: {event}"}},
                    )
            except json.JSONDecodeError:
                await manager.send_personal_message(
                    user_id,
                    {"event": "error", "data": {"message": "Invalid JSON"}},
                )
    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"WebSocket error for user {user_id}: {e}")
    finally:
        await manager.disconnect(user_id)
        async with AsyncSessionLocal() as db:
            await update_online_status(db, user_id, False)
            await db.commit()


async def handle_join_conversation(user_id: str, data: dict):
    conversation_id = data.get("conversation_id")
    if conversation_id:
        manager.join_conversation(user_id, conversation_id)
        await manager.send_personal_message(
            user_id,
            {"event": "joined_conversation", "data": {"conversation_id": conversation_id}},
        )


async def handle_leave_conversation(user_id: str, data: dict):
    conversation_id = data.get("conversation_id")
    if conversation_id:
        manager.leave_conversation(user_id, conversation_id)


async def handle_typing(user_id: str, data: dict):
    conversation_id = data.get("conversation_id")
    is_typing = data.get("is_typing", False)
    user_name = data.get("user_name", "")
    if conversation_id:
        await manager.send_typing_indicator(conversation_id, user_id, is_typing, user_name)


async def handle_read_receipt(user_id: str, data: dict):
    message_id = data.get("message_id")
    sender_id = data.get("sender_id")
    if message_id and sender_id:
        await manager.send_message_status(sender_id, message_id, "read")


async def handle_call_signal(user_id: str, data: dict):
    to_user_id = data.get("to_user_id")
    if to_user_id:
        data["from_user_id"] = user_id
        await manager.send_call_signal(to_user_id, data)


async def handle_voice_translation_start(user_id: str, data: dict):
    """Receiver asks to start translated-voice playback for a call.

    Payload: call_id, speaker_id, source_language, target_language, voice.
    Opens a Gemini Live session keyed to the SPEAKER; the speaker's app then
    streams mic PCM via 'voice_translation_audio', and the receiver gets
    'voice_translation' events with base64 PCM audio (24 kHz) to play.
    """
    call_id = data.get("call_id")
    speaker_id = data.get("speaker_id")
    if not call_id or not speaker_id:
        await manager.send_personal_message(
            user_id, {"event": "error", "data": {"message": "call_id and speaker_id required"}}
        )
        return

    async def push_audio(b64_pcm: str):
        await manager.send_personal_message(
            user_id,
            {"event": "voice_translation", "data": {"call_id": call_id, "audio": b64_pcm}},
        )

    async def push_text(text):
        # text: transcript chunk, "" = interrupted (stop playback), None = utterance end
        await manager.send_personal_message(
            user_id,
            {"event": "voice_translation_status", "data": {"call_id": call_id, "text": text}},
        )

    session = await live_translation_manager.start_session(
        call_id=call_id,
        speaker_user_id=speaker_id,
        receiver_user_id=user_id,
        source_language=data.get("source_language", "kinyarwanda"),
        target_language=data.get("target_language", "english"),
        voice=data.get("voice") or DEFAULT_VOICE,
        on_audio=push_audio,
        on_text=push_text,
    )
    # Tell the SPEAKER's app to start streaming its mic PCM into the session.
    if getattr(session, "gemini_available", False):
        await manager.send_personal_message(
            speaker_id,
            {
                "event": "voice_translation_stream_start",
                "data": {
                    "call_id": call_id,
                    "source_language": session.source_language,
                    "target_language": session.target_language,
                },
            },
        )
    await manager.send_personal_message(
        user_id,
        {
            "event": "voice_translation_started",
            "data": {
                "call_id": call_id,
                "gemini_available": getattr(session, "gemini_available", False),
                "voice": session.voice,
                "available_voices": GEMINI_VOICES,
            },
        },
    )


async def handle_voice_translation_stop(user_id: str, data: dict):
    call_id = data.get("call_id")
    speaker_id = data.get("speaker_id")
    if call_id and speaker_id:
        await live_translation_manager.stop_session(call_id, speaker_id)
        # Tell the speaker's app to stop streaming its mic.
        await manager.send_personal_message(
            speaker_id,
            {"event": "voice_translation_stream_stop", "data": {"call_id": call_id}},
        )
        await manager.send_personal_message(
            user_id, {"event": "voice_translation_stopped", "data": {"call_id": call_id}}
        )


async def handle_voice_translation_stream_start(user_id: str, data: dict):
    """Client->backend stream lifecycle (no-ops; the backend drives streaming
    via voice_translation_stream_start sent to the speaker from
    handle_voice_translation_start). Kept for symmetry/robustness."""
    return


async def handle_voice_translation_stream_stop(user_id: str, data: dict):
    """Speaker's app stops streaming (mirrors voice_translation_stop)."""
    await handle_voice_translation_stop(user_id, data)


async def handle_voice_translation_audio(user_id: str, data: dict):
    """Speaker app streams mic PCM chunks (base64, 16-bit mono 16 kHz)."""
    call_id = data.get("call_id")
    audio = data.get("audio")
    if not call_id or not audio:
        return
    session = live_translation_manager.get_session(call_id, user_id)
    if session:
        await session.send_audio_chunk(audio)
