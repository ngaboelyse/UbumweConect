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


# call_id -> {"receiver": ..., "speaker": ..., "source_language": ..., "target_language": ..., "voice": ...}
# Lets us transparently re-open a Gemini session if it dies mid-call.
_translation_requests: dict = {}


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

    print(f"[voice-translation] start request from receiver {user_id} for call {call_id} (speaker={speaker_id})")

    async def push_audio(b64_pcm: str):
        await manager.send_personal_message(
            user_id,
            {"event": "voice_translation", "data": {"call_id": call_id, "audio": b64_pcm}},
        )
        if not getattr(handle_voice_translation_start, "_audio_logged", False):
            handle_voice_translation_start._audio_logged = True
            print(f"[voice-translation] sending translated audio to receiver (len={len(b64_pcm)})")

    async def push_text(text):
        # text: transcript chunk, "" = interrupted (stop playback), None = utterance end
        await manager.send_personal_message(
            user_id,
            {"event": "voice_translation_status", "data": {"call_id": call_id, "text": text}},
        )

    print(f"[voice-translation] opening Gemini session for call {call_id} ...")
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
    print(f"[voice-translation] session open for call {call_id} (gemini_available={getattr(session, 'gemini_available', False)})")
    _translation_requests[call_id] = {
        "receiver": user_id,
        "speaker": speaker_id,
        "source_language": data.get("source_language", "kinyarwanda"),
        "target_language": data.get("target_language", "english"),
        "voice": data.get("voice") or DEFAULT_VOICE,
    }
    # Tell the SPEAKER's app to start streaming its mic PCM into the session.
    if getattr(session, "gemini_available", False):
        print(f"[voice-translation] asking speaker {speaker_id} to stream mic for call {call_id}")
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
    else:
        print(f"[voice-translation] Gemini unavailable for call {call_id} — speaker {speaker_id} will NOT stream mic")
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
        _translation_requests.pop(call_id, None)
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
    if session and getattr(session, "gemini_available", False):
        await session.send_audio_chunk(audio)
        return

    # No live session: the Gemini session died (backend restart, Gemini
    # disconnect, ...) while the speaker kept streaming. If a translation was
    # requested for this call, transparently re-open it — no UI action needed.
    req = _translation_requests.get(call_id)
    if req and req["speaker"] == user_id:
        print(f"[voice-translation] session missing for call {call_id} — re-opening automatically")
        await handle_voice_translation_start(req["receiver"], {
            "call_id": call_id,
            "speaker_id": req["speaker"],
            "source_language": req["source_language"],
            "target_language": req["target_language"],
            "voice": req["voice"],
        })
        session = live_translation_manager.get_session(call_id, user_id)
        if session and getattr(session, "gemini_available", False):
            await session.send_audio_chunk(audio)
            return
    # Nothing we can do (no request or Gemini still failing): stop the
    # speaker's mic so it isn't streaming into the void.
    print(f"[voice-translation] cannot re-open session for call {call_id} — stopping mic")
    await manager.send_personal_message(
        user_id,
        {"event": "voice_translation_stream_stop", "data": {"call_id": call_id}},
    )
