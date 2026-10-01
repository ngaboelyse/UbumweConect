"""
Tests for the translation service and endpoints.
"""
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient

from tests.conftest import MockCompletion


# ---------------------------------------------------------------------------
# Service-level unit tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_translate_same_language(db_session):
    """Translating to the same source language returns original text unchanged."""
    from app.services.translation_service import TranslationService
    service = TranslationService(db_session)
    result = await service.translate_text("Hello!", "english", "english")
    assert result == "Hello!"


@pytest.mark.asyncio
async def test_translate_cache_miss_calls_openai(db_session):
    """Cache miss should call OpenAI API exactly once."""
    from app.services.translation_service import TranslationService
    with patch("app.services.translation_service.openai_client") as mock_client:
        mock_client.chat.completions.create = AsyncMock(
            return_value=MockCompletion("Muraho!")
        )
        service = TranslationService(db_session)
        result = await service.translate_text("Hello!", "english", "kinyarwanda")
        assert result == "Muraho!"
        mock_client.chat.completions.create.assert_called_once()


@pytest.mark.asyncio
async def test_translate_cache_hit_no_openai_call(db_session):
    """Cache hit should return result without calling OpenAI."""
    from app.services.translation_service import TranslationService
    from app.models.translation import TranslationCache
    import hashlib

    # Manually insert cache entry
    text = "Good morning!"
    text_hash = hashlib.sha256(text.encode()).hexdigest()
    cache_entry = TranslationCache(
        text_hash=text_hash,
        source_text=text,
        source_language="english",
        target_language="kinyarwanda",
        translated_text="Mwaramutse!"
    )
    db_session.add(cache_entry)
    await db_session.flush()

    with patch("app.services.translation_service.openai_client") as mock_client:
        service = TranslationService(db_session)
        result = await service.translate_text(text, "english", "kinyarwanda")
        assert result == "Mwaramutse!"
        mock_client.chat.completions.create.assert_not_called()


@pytest.mark.asyncio
async def test_translate_stores_result_in_cache(db_session):
    """After a cache miss, the result should be saved to translation_cache."""
    from app.services.translation_service import TranslationService
    from app.models.translation import TranslationCache
    from sqlalchemy import select

    with patch("app.services.translation_service.openai_client") as mock_client:
        mock_client.chat.completions.create = AsyncMock(
            return_value=MockCompletion("Bonjour!")
        )
        service = TranslationService(db_session)
        await service.translate_text("Hello!", "english", "french")

        # Verify cache entry was created
        result = await db_session.execute(
            select(TranslationCache).where(
                TranslationCache.source_language == "english",
                TranslationCache.target_language == "french"
            )
        )
        cache_entry = result.scalar_one_or_none()
        assert cache_entry is not None
        assert cache_entry.translated_text == "Bonjour!"


@pytest.mark.asyncio
async def test_batch_translate_all_languages(db_session):
    """Batch translate returns dict with all 4 language keys."""
    from app.services.translation_service import TranslationService

    translations = {
        "kinyarwanda": "Muraho!",
        "french": "Bonjour!",
        "swahili": "Habari!",
    }

    async def mock_translate(text, source, target):
        if target == source:
            return text
        return translations.get(target, "")

    with patch("app.services.translation_service.TranslationService.translate_text",
               side_effect=mock_translate):
        service = TranslationService(db_session)
        result = await service.translate_for_all_languages("Hello!", "english")

        assert "english" in result
        assert "kinyarwanda" in result
        assert "french" in result
        assert "swahili" in result
        assert result["english"] == "Hello!"
        assert result["kinyarwanda"] == "Muraho!"


@pytest.mark.asyncio
async def test_detect_language_kinyarwanda(db_session):
    """Language detection for Kinyarwanda text."""
    from app.services.translation_service import TranslationService

    with patch("app.services.translation_service.openai_client") as mock_client:
        mock_client.chat.completions.create = AsyncMock(
            return_value=MockCompletion('{"language": "kinyarwanda", "confidence": 0.97}')
        )
        service = TranslationService(db_session)
        lang, confidence = await service.detect_language("Muraho! Amakuru yawe?")
        assert lang == "kinyarwanda"
        assert confidence >= 0.9


@pytest.mark.asyncio
async def test_detect_language_french(db_session):
    """Language detection for French text."""
    from app.services.translation_service import TranslationService

    with patch("app.services.translation_service.openai_client") as mock_client:
        mock_client.chat.completions.create = AsyncMock(
            return_value=MockCompletion('{"language": "french", "confidence": 0.99}')
        )
        service = TranslationService(db_session)
        lang, confidence = await service.detect_language("Bonjour! Comment ça va?")
        assert lang == "french"


# ---------------------------------------------------------------------------
# API endpoint tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_translate_endpoint_success(async_client: AsyncClient, auth_headers: dict):
    """Test POST /translation/translate returns translated text."""
    with patch("app.routers.translation.get_translation_service") as mock_service:
        mock_service.return_value.translate_text = AsyncMock(return_value="Muraho!")
        response = await async_client.post(
            "/api/v1/translation/translate",
            json={
                "text": "Hello!",
                "source_language": "english",
                "target_language": "kinyarwanda"
            },
            headers=auth_headers
        )
    assert response.status_code == 200
    data = response.json()
    assert "translated_text" in data
    assert data["source_language"] == "english"
    assert data["target_language"] == "kinyarwanda"


@pytest.mark.asyncio
async def test_translate_endpoint_unauthenticated(async_client: AsyncClient):
    """Translation endpoint requires authentication."""
    response = await async_client.post(
        "/api/v1/translation/translate",
        json={
            "text": "Hello!",
            "source_language": "english",
            "target_language": "french"
        }
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_translate_endpoint_empty_text(async_client: AsyncClient, auth_headers: dict):
    """Empty text should be rejected with 422."""
    response = await async_client.post(
        "/api/v1/translation/translate",
        json={
            "text": "",
            "source_language": "english",
            "target_language": "french"
        },
        headers=auth_headers
    )
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_translate_endpoint_invalid_language(async_client: AsyncClient, auth_headers: dict):
    """Unsupported language code should be rejected."""
    response = await async_client.post(
        "/api/v1/translation/translate",
        json={
            "text": "Hello!",
            "source_language": "english",
            "target_language": "mandarin"
        },
        headers=auth_headers
    )
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_detect_language_endpoint(async_client: AsyncClient, auth_headers: dict):
    """Test POST /translation/detect endpoint."""
    with patch("app.routers.translation.get_translation_service") as mock_service:
        mock_service.return_value.detect_language = AsyncMock(
            return_value=("french", 0.98)
        )
        response = await async_client.post(
            "/api/v1/translation/detect",
            json={"text": "Bonjour tout le monde!"},
            headers=auth_headers
        )
    assert response.status_code == 200
    data = response.json()
    assert "language" in data
    assert "confidence" in data


@pytest.mark.asyncio
async def test_batch_translate_endpoint(async_client: AsyncClient, auth_headers: dict):
    """Test POST /translation/batch returns all 4 language translations."""
    with patch("app.routers.translation.get_translation_service") as mock_service:
        mock_service.return_value.translate_for_all_languages = AsyncMock(return_value={
            "english": "Hello!",
            "kinyarwanda": "Muraho!",
            "french": "Bonjour!",
            "swahili": "Habari!"
        })
        response = await async_client.post(
            "/api/v1/translation/batch",
            json={"text": "Hello!", "source_language": "english"},
            headers=auth_headers
        )
    assert response.status_code == 200
    data = response.json()
    assert "translations" in data
    assert len(data["translations"]) == 4
    for lang in ["english", "kinyarwanda", "french", "swahili"]:
        assert lang in data["translations"]
