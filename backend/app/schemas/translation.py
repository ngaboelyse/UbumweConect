from pydantic import BaseModel, Field
from typing import Optional, List, Dict


class TranslationRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=5000)
    source_language: Optional[str] = None  # None = auto-detect
    target_language: str = Field(..., pattern=r"^(kinyarwanda|english|french|swahili)$")


class TranslationResponse(BaseModel):
    original_text: str
    translated_text: str
    source_language: str
    target_language: str
    detected_language: Optional[str] = None
    confidence: Optional[float] = None
    cached: bool = False


class BatchTranslationRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=5000)
    source_language: Optional[str] = None
    # Optional — defaults to translating into every supported language
    target_languages: Optional[List[str]] = None


class BatchTranslationResponse(BaseModel):
    original_text: str
    source_language: str
    translations: Dict[str, str]


class LanguageDetectionRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=1000)


class LanguageDetectionResponse(BaseModel):
    text: str
    language: str
    confidence: float
    possible_languages: List[Dict[str, float]] = []


class AITranslationImprovementRequest(BaseModel):
    original_text: str
    current_translation: str
    source_language: str
    target_language: str
    context: Optional[str] = None


class AITranslationImprovementResponse(BaseModel):
    improved_translation: str
    explanation: str
    confidence: float
