import json
from typing import Dict, Set
from fastapi import WebSocket
import uuid


class ConnectionManager:
    """Manages WebSocket connections for real-time messaging."""

    def __init__(self):
        # user_id (str) -> WebSocket
        self.active_connections: Dict[str, WebSocket] = {}
        # conversation_id -> set of user_ids
        self.conversation_members: Dict[str, Set[str]] = {}

    async def connect(self, user_id: str, websocket: WebSocket) -> None:
        await websocket.accept()
        self.active_connections[user_id] = websocket
        print(f"User {user_id} connected. Total connections: {len(self.active_connections)}")

    async def disconnect(self, user_id: str) -> None:
        if user_id in self.active_connections:
            del self.active_connections[user_id]
        # Remove from all conversation rooms
        for members in self.conversation_members.values():
            members.discard(user_id)
        print(f"User {user_id} disconnected. Total connections: {len(self.active_connections)}")

    def is_connected(self, user_id: str) -> bool:
        return user_id in self.active_connections

    def get_user_rooms(self, user_id: str) -> Set[str]:
        """Return set of conversation rooms the user has joined."""
        return {
            conv_id for conv_id, members in self.conversation_members.items()
            if user_id in members
        }

    async def send_personal_message(self, user_id: str, message: dict) -> bool:
        """Send a message to a specific user."""
        websocket = self.active_connections.get(user_id)
        if websocket:
            try:
                await websocket.send_json(message)
                return True
            except Exception as e:
                print(f"Error sending to user {user_id}: {e}")
                await self.disconnect(user_id)
        return False

    async def broadcast_to_conversation(
        self,
        conversation_id: str,
        message: dict,
        exclude_user: str = None,
    ) -> None:
        """Broadcast a message to all participants in a conversation."""
        members = self.conversation_members.get(conversation_id, set())
        disconnected = []
        for user_id in members:
            if exclude_user and user_id == exclude_user:
                continue
            websocket = self.active_connections.get(user_id)
            if websocket:
                try:
                    await websocket.send_json(message)
                except Exception:
                    disconnected.append(user_id)
        for user_id in disconnected:
            await self.disconnect(user_id)

    async def send_new_message(
        self,
        conversation_id: str,
        message_data: dict,
        exclude_user: str = None,
    ) -> None:
        await self.broadcast_to_conversation(
            conversation_id,
            {"event": "new_message", "data": message_data},
            exclude_user,
        )

    async def send_typing_indicator(
        self,
        conversation_id: str,
        user_id: str,
        is_typing: bool,
        user_name: str = "",
    ) -> None:
        await self.broadcast_to_conversation(
            conversation_id,
            {
                "event": "typing_indicator",
                "data": {
                    "conversation_id": conversation_id,
                    "user_id": user_id,
                    "user_name": user_name,
                    "is_typing": is_typing,
                },
            },
            exclude_user=user_id,
        )

    async def send_message_status(
        self,
        user_id: str,
        message_id: str,
        status: str,
    ) -> None:
        await self.send_personal_message(
            user_id,
            {
                "event": "message_status",
                "data": {"message_id": message_id, "status": status},
            },
        )

    async def send_call_signal(
        self,
        to_user_id: str,
        signal_data: dict,
    ) -> bool:
        return await self.send_personal_message(
            to_user_id,
            {"event": "call_signal", "data": signal_data},
        )

    async def notify_online_status(
        self,
        user_id: str,
        is_online: bool,
        notify_user_ids: list,
    ) -> None:
        payload = {
            "event": "online_status",
            "data": {"user_id": user_id, "is_online": is_online},
        }
        for uid in notify_user_ids:
            if uid != user_id:
                await self.send_personal_message(uid, payload)

    def join_conversation(self, user_id: str, conversation_id: str) -> None:
        if conversation_id not in self.conversation_members:
            self.conversation_members[conversation_id] = set()
        self.conversation_members[conversation_id].add(user_id)

    def leave_conversation(self, user_id: str, conversation_id: str) -> None:
        if conversation_id in self.conversation_members:
            self.conversation_members[conversation_id].discard(user_id)


manager = ConnectionManager()
