from typing import Optional
import firebase_admin
from firebase_admin import messaging
from app.config import settings


class NotificationService:
    async def send_push_notification(
        self,
        push_token: str,
        title: str,
        body: str,
        data: Optional[dict] = None,
        image_url: Optional[str] = None,
    ) -> bool:
        """Send FCM push notification."""
        try:
            message = messaging.Message(
                notification=messaging.Notification(
                    title=title,
                    body=body,
                    image=image_url,
                ),
                data={k: str(v) for k, v in (data or {}).items()},
                token=push_token,
                android=messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(
                        sound="default",
                        channel_id="ubumwe_messages",
                    ),
                ),
                apns=messaging.APNSConfig(
                    payload=messaging.APNSPayload(
                        aps=messaging.Aps(sound="default", badge=1),
                    ),
                ),
            )
            messaging.send(message)
            return True
        except Exception as e:
            print(f"Push notification failed: {e}")
            return False

    async def send_message_notification(
        self,
        sender_name: str,
        sender_avatar: Optional[str],
        recipient_push_token: str,
        translated_message: str,
        conversation_id: str,
    ) -> bool:
        return await self.send_push_notification(
            push_token=recipient_push_token,
            title=sender_name,
            body=translated_message[:100] + ("..." if len(translated_message) > 100 else ""),
            data={
                "type": "new_message",
                "conversation_id": conversation_id,
                "sender_name": sender_name,
            },
            image_url=sender_avatar,
        )

    async def send_call_notification(
        self,
        caller_name: str,
        caller_avatar: Optional[str],
        recipient_push_token: str,
        call_type: str,
        call_id: str,
    ) -> bool:
        return await self.send_push_notification(
            push_token=recipient_push_token,
            title=f"Incoming {call_type.capitalize()} Call",
            body=f"{caller_name} is calling you",
            data={
                "type": "incoming_call",
                "call_id": call_id,
                "caller_name": caller_name,
                "call_type": call_type,
            },
            image_url=caller_avatar,
        )


notification_service = NotificationService()
