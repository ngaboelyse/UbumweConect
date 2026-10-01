""""
Tests for messaging features: send, edit, delete, reactions, search,
mark-read, attachments and unread counts.
"""
import pytest

from app.services import translation_service

pytestmark = pytest.mark.asyncio


@pytest.fixture(autouse=True)
def mock_translation(monkeypatch):
    """Avoid real OpenAI calls in messaging tests."""
    async def fake_translate_for_all(text, source_language, db=None):
        return {lang: f"[{lang}] {text}" for lang in translation_service.SUPPORTED_LANGUAGES}

    async def fake_translate(text, source_language, target_language, db=None):
        return {
            "translated_text": f"[{target_language}] {text}",
            "source_language": source_language,
            "target_language": target_language,
            "cached": False,
        }

    monkeypatch.setattr(
        "app.routers.conversations.translate_message_for_all_languages",
        fake_translate_for_all,
    )
    monkeypatch.setattr(
        "app.routers.conversations.translate",
        fake_translate,
        raising=False,
    )


async def _send_message(client, headers, conversation_id, content="Muraho!"):
    resp = await client.post(
        f"/api/v1/conversations/{conversation_id}/messages",
        json={"content": content, "message_type": "text"},
        headers=headers,
    )
    return resp


async def test_send_message(async_client, auth_headers, conversation):
    resp = await _send_message(async_client, auth_headers, conversation["id"])
    assert resp.status_code == 201
    data = resp.json()
    assert data["original_content"] == "Muraho!"
    assert data["is_deleted"] is False
    assert data["is_edited"] is False


async def test_edit_message_within_window(async_client, auth_headers, conversation):
    conv_id = conversation["id"]
    msg = (await _send_message(async_client, auth_headers, conv_id)).json()

    resp = await async_client.put(
        f"/api/v1/conversations/{conv_id}/messages/{msg['id']}",
        json={"content": "Edited content"},
        headers=auth_headers,
    )
    assert resp.status_code == 200
    assert resp.json()["is_edited"] is True
    assert resp.json()["original_content"] == "Edited content"


async def test_cannot_edit_others_message(async_client, auth_headers, second_user_headers, conversation):
    conv_id = conversation["id"]
    # second_user sends a message, first user tries to edit
    resp = await _send_message(async_client, second_user_headers, conv_id)
    msg = resp.json()
    # test_user (auth_headers) is a participant but not the sender -> 403
    resp = await async_client.put(
        f"/api/v1/conversations/{conv_id}/messages/{msg['id']}",
        json={"content": "hijack"},
        headers=auth_headers,
    )
    assert resp.status_code == 403


async def test_delete_message(async_client, auth_headers, conversation):
    conv_id = conversation["id"]
    msg = (await _send_message(async_client, auth_headers, conv_id)).json()
    resp = await async_client.delete(
        f"/api/v1/conversations/{conv_id}/messages/{msg['id']}",
        headers=auth_headers,
    )
    assert resp.status_code == 204


async def test_react_and_toggle(async_client, auth_headers, conversation):
    conv_id = conversation["id"]
    msg = (await _send_message(async_client, auth_headers, conv_id)).json()

    # Add reaction
    resp = await async_client.post(
        f"/api/v1/conversations/{conv_id}/messages/{msg['id']}/reactions",
        json={"emoji": "👍"},
        headers=auth_headers,
    )
    assert resp.status_code == 200
    reactions = resp.json()["reactions"]
    assert len(reactions) == 1
    assert reactions[0]["emoji"] == "👍"

    # Toggle again -> removed
    resp = await async_client.post(
        f"/api/v1/conversations/{conv_id}/messages/{msg['id']}/reactions",
        json={"emoji": "👍"},
        headers=auth_headers,
    )
    assert resp.status_code == 200
    assert resp.json()["reactions"] == []


async def test_replace_reaction(async_client, auth_headers, conversation):
    conv_id = conversation["id"]
    msg = (await _send_message(async_client, auth_headers, conv_id)).json()

    await async_client.post(
        f"/api/v1/conversations/{conv_id}/messages/{msg['id']}/reactions",
        json={"emoji": "👍"},
        headers=auth_headers,
    )
    resp = await async_client.post(
        f"/api/v1/conversations/{conv_id}/messages/{msg['id']}/reactions",
        json={"emoji": "❤️"},
        headers=auth_headers,
    )
    reactions = resp.json()["reactions"]
    assert len(reactions) == 1
    assert reactions[0]["emoji"] == "❤️"


async def test_search_messages(async_client, auth_headers, conversation):
    conv_id = conversation["id"]
    await _send_message(async_client, auth_headers, conv_id, content="UniqueSearchTerm123")
    resp = await async_client.get(
        f"/api/v1/conversations/{conv_id}/messages/search",
        params={"q": "UniqueSearchTerm123"},
        headers=auth_headers,
    )
    assert resp.status_code == 200
    results = resp.json()
    assert len(results) == 1
    assert results[0]["original_content"] == "UniqueSearchTerm123"


async def test_search_requires_min_length(async_client, auth_headers, conversation):
    resp = await async_client.get(
        f"/api/v1/conversations/{conversation['id']}/messages/search",
        params={"q": "a"},
        headers=auth_headers,
    )
    assert resp.status_code == 422


async def test_mark_conversation_read(async_client, auth_headers, second_user_headers, conversation):
    conv_id = conversation["id"]
    # Other user sends messages
    await _send_message(async_client, second_user_headers, conv_id, content="msg 1")
    await _send_message(async_client, second_user_headers, conv_id, content="msg 2")

    # Unread count should be 2 for first user
    resp = await async_client.get("/api/v1/conversations", headers=auth_headers)
    convs = resp.json()
    target = next(c for c in convs if c["id"] == conv_id)
    assert target["unread_count"] == 2

    # Mark read
    resp = await async_client.post(
        f"/api/v1/conversations/{conv_id}/read", headers=auth_headers
    )
    assert resp.status_code == 204

    resp = await async_client.get("/api/v1/conversations", headers=auth_headers)
    target = next(c for c in resp.json() if c["id"] == conv_id)
    assert target["unread_count"] == 0


async def test_send_nonexistent_conversation(async_client, auth_headers):
    resp = await async_client.post(
        "/api/v1/conversations/00000000-0000-0000-0000-000000000000/messages",
        json={"content": "hello", "message_type": "text"},
        headers=auth_headers,
    )
    assert resp.status_code == 404


async def test_message_with_media_fields(async_client, auth_headers, conversation):
    conv_id = conversation["id"]
    resp = await async_client.post(
        f"/api/v1/conversations/{conv_id}/messages",
        json={
            "content": "Photo",
            "message_type": "image",
            "media_url": "https://example.com/photo.jpg",
            "file_name": "photo.jpg",
            "file_size": 12345,
        },
        headers=auth_headers,
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["message_type"] == "image"
    assert data["file_url"] == "https://example.com/photo.jpg"
    assert data["file_name"] == "photo.jpg"
