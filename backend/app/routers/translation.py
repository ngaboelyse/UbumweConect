from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.schemas.translation import (
    TranslationRequest, TranslationResponse,
    BatchTranslationRequest, BatchTranslationResponse,
    LanguageDetectionRequest, LanguageDetectionResponse,
    AITranslationImprovementRequest, AITranslationImprovementResponse,
)
from app.services.translation_service import TranslationService
from app.services import translation_service
from app.middleware.auth_middleware import get_current_user
from app.models.user import User

router = APIRouter(prefix="/translation", tags=["Translation"])


def get_translation_service(db: AsyncSession | None = None) -> TranslationService:
    """Factory indirection so callers/tests can patch the service source."""
    return TranslationService(db)


@router.post("/translate", response_model=TranslationResponse)
async def translate_text(
    data: TranslationRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    source_lang = data.source_language
    if not source_lang:
        source_lang = await translation_service.detect_language(data.text)

    service = get_translation_service(db)
    result = await service.translate_text(data.text, source_lang, data.target_language)

    return TranslationResponse(
        original_text=data.text,
        translated_text=result,
        source_language=source_lang,
        target_language=data.target_language,
        detected_language=source_lang if not data.source_language else None,
        cached=False,
    )


@router.post("/detect", response_model=LanguageDetectionResponse)
async def detect_language(
    data: LanguageDetectionRequest,
    current_user: User = Depends(get_current_user),
):
    service = get_translation_service()
    detected, confidence = await service.detect_language(data.text)
    return LanguageDetectionResponse(
        text=data.text,
        language=detected,
        confidence=confidence,
    )


@router.post("/batch", response_model=BatchTranslationResponse)
async def batch_translate(
    data: BatchTranslationRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    source_lang = data.source_language
    if not source_lang:
        source_lang = await translation_service.detect_language(data.text)

    target_languages = data.target_languages or translation_service.SUPPORTED_LANGUAGES
    service = get_translation_service(db)
    translations = await service.translate_for_all_languages(data.text, source_lang, target_languages=target_languages)

    return BatchTranslationResponse(
        original_text=data.text,
        source_language=source_lang,
        translations=translations,
    )


@router.post("/improve", response_model=AITranslationImprovementResponse)
async def improve_translation(
    data: AITranslationImprovementRequest,
    current_user: User = Depends(get_current_user),
):
    result = await translation_service.improve_translation(
        original_text=data.original_text,
        current_translation=data.current_translation,
        source_language=data.source_language,
        target_language=data.target_language,
        context=data.context,
    )
    return AITranslationImprovementResponse(**result)
