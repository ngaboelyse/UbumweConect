import json
from datetime import datetime
from fastapi import WebSocket, WebSocketDisconnect
from sqlalchemy.ext.asyncio import AsyncSession

from app.websocket.manager import manager
from app.services.auth_service import update_online_status, decode_token, get_user_by_id
from app.database import AsyncSessionLocal


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
