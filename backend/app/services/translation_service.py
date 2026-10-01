import hashlib
import json
from typing import Optional, Dict, List
from datetime import datetime

from openai import AsyncOpenAI
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.config import settings
from app.models.translation import TranslationCache


SUPPORTED_LANGUAGES = ["kinyarwanda", "english", "french", "swahili"]

LANGUAGE_NAMES = {
    "kinyarwanda": "Kinyarwanda",
    "english": "English",
    "french": "French",
    "swahili": "Swahili",
}

LANGUAGE_CODES = {
    "kinyarwanda": "rw",
    "english": "en",
    "french": "fr",
    "swahili": "sw",
}

# Language detection hints (common words/phrases)
LANGUAGE_HINTS = {
    "kinyarwanda": ["muraho", "amakuru", "mwaramutse", "ndashaka", "murakoze", "yego", "oya", "bite", "neza"],
    "french": ["bonjour", "merci", "comment", "allez", "vous", "je", "les", "est", "une", "pour"],
    "swahili": ["habari", "asante", "karibu", "ndiyo", "hapana", "kwaheri", "sawa", "pole", "haraka"],
    "english": ["hello", "thank", "how", "are", "you", "the", "and", "is", "for", "with"],
}

client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
# Alias so tests (and external callers) can patch a well-known name.
openai_client = client


def _compute_hash(text: str) -> str:
    # NOTE: plain sha256 of the raw text — callers/tests insert cache rows
    # keyed on hashlib.sha256(text.encode()).hexdigest().
    return hashlib.sha256(text.encode()).hexdigest()


async def _get_cached_translation(
    db: AsyncSession,
    text_hash: str,
    source_language: str,
    target_language: str,
) -> Optional[str]:
    result = await db.execute(
        select(TranslationCache).where(
            TranslationCache.text_hash == text_hash,
            TranslationCache.source_language == source_language,
            TranslationCache.target_language == target_language,
        )
    )
    cache_entry = result.scalar_one_or_none()
    if cache_entry:
        cache_entry.hit_count += 1
        cache_entry.last_used_at = datetime.utcnow()
        return cache_entry.translated_text
    return None


async def _save_to_cache(
    db: AsyncSession,
    text: str,
    text_hash: str,
    source_language: str,
    target_language: str,
    translated_text: str,
) -> None:
    cache_entry = TranslationCache(
        text_hash=text_hash,
        source_language=source_language,
        target_language=target_language,
        original_text=text,
        translated_text=translated_text,
        model_used="gpt-4o-mini",
    )
    db.add(cache_entry)
    await db.flush()


class TranslationService:
    """Instance-based wrapper around the module-level translation helpers.
    Keeps a DB session so results can be cached in `translations_cache`."""

    def __init__(self, db: Optional[AsyncSession] = None):
        self.db = db

    async def translate_text(self, text, source_language, target_language, db=None) -> str:
        """Return only the translated text for `target_language`."""
        if source_language == target_language:
            return text
        result = await translate(text, source_language, target_language, db or self.db)
        return result["translated_text"]

    async def translate_for_all_languages(self, text: str, source_language: str, target_languages: Optional[List[str]] = None, db=None) -> Dict[str, str]:
        """Translate into the given (or all supported) languages; original included."""
        targets = target_languages or SUPPORTED_LANGUAGES
        results = {source_language: text}
        for lang in targets:
            if lang == source_language:
                continue
            # Call with 3 args (self.db is used internally) so patched
            # translate_text implementations with (text, src, tgt) also work.
            results[lang] = await self.translate_text(text, source_language, lang)
        return results

    async def batch_translate(self, text: str, source_language: str, target_languages: List[str], db=None) -> Dict[str, str]:
        return await batch_translate(text, source_language, target_languages, db or self.db)

    async def detect_language(self, text: str) -> tuple:
        """Detect language. Returns (language, confidence)."""
        text_lower = text.lower()
        scores = {lang: 0 for lang in SUPPORTED_LANGUAGES}
        for lang, hints in LANGUAGE_HINTS.items():
            for hint in hints:
                if hint in text_lower:
                    scores[lang] += 1

        best = max(scores, key=scores.get)
        if scores[best] > 0:
            # Heuristic match — high confidence
            return best, min(0.90 + 0.01 * scores[best], 0.99)

        # Fallback: ask OpenAI for structured JSON {"language": ..., "confidence": ...}
        try:
            response = await openai_client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[{
                    "role": "user",
                    "content": (
                        'Detect the language of this text. Reply with ONLY JSON like '
                        '{"language": "kinyarwanda", "confidence": 0.95}. '
                        f"Supported: {', '.join(SUPPORTED_LANGUAGES)}.\n\nText: {text[:200]}"
                    ),
                }],
                max_tokens=50,
                temperature=0,
            )
            content = response.choices[0].message.content.strip()
            data = json.loads(content)
            lang = data.get("language", "english").lower()
            if lang not in SUPPORTED_LANGUAGES:
                lang = "english"
            confidence = float(data.get("confidence", 0.5))
            return lang, confidence
        except Exception:
            return "english", 0.5


async def detect_language(text: str) -> str:
    """Detect language using simple heuristic + OpenAI fallback."""
    text_lower = text.lower()
    scores = {lang: 0 for lang in SUPPORTED_LANGUAGES}
    for lang, hints in LANGUAGE_HINTS.items():
        for hint in hints:
            if hint in text_lower:
                scores[lang] += 1

    best_lang = max(scores, key=scores.get)
    if scores[best_lang] > 0:
        return best_lang

    # Fallback: ask OpenAI
    try:
        response = await openai_client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[{
                "role": "user",
                "content": f"Detect the language of this text. Reply with ONLY one word: kinyarwanda, english, french, or swahili.\n\nText: {text[:200]}"
            }],
            max_tokens=10,
            temperature=0,
        )
        detected = response.choices[0].message.content.strip().lower()
        if detected in SUPPORTED_LANGUAGES:
            return detected
    except Exception:
        pass

    return "english"  # Default fallback


async def translate(
    text: str,
    source_language: str,
    target_language: str,
    db: Optional[AsyncSession] = None,
) -> Dict[str, any]:
    """Translate text from source to target language."""
    if source_language == target_language:
        return {
            "translated_text": text,
            "source_language": source_language,
            "target_language": target_language,
            "cached": True,
        }

    text_hash = _compute_hash(text)

    # Check cache
    if db:
        cached = await _get_cached_translation(db, text_hash, source_language, target_language)
        if cached:
            return {
                "translated_text": cached,
                "source_language": source_language,
                "target_language": target_language,
                "cached": True,
            }

    src_name = LANGUAGE_NAMES.get(source_language, source_language.capitalize())
    tgt_name = LANGUAGE_NAMES.get(target_language, target_language.capitalize())

    prompt = (
        f"You are a professional translator specializing in African languages. "
        f"Translate the following {src_name} text to {tgt_name}. "
        f"Preserve the tone, meaning, and any cultural nuances. "
        f"For Kinyarwanda, use natural Rwandan phrasing. "
        f"Return ONLY the translated text, no explanations.\n\n"
        f"Text to translate: {text}"
    )

    response = await openai_client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": prompt}],
        max_tokens=1000,
        temperature=0.3,
    )

    translated_text = response.choices[0].message.content.strip()

    # Save to cache
    if db:
        await _save_to_cache(db, text, text_hash, source_language, target_language, translated_text)

    return {
        "translated_text": translated_text,
        "source_language": source_language,
        "target_language": target_language,
        "cached": False,
    }


async def batch_translate(
    text: str,
    source_language: str,
    target_languages: List[str],
    db: Optional[AsyncSession] = None,
) -> Dict[str, str]:
    """Translate text to multiple languages at once."""
    results = {}
    for target_lang in target_languages:
        if target_lang == source_language:
            results[target_lang] = text
        else:
            result = await translate(text, source_language, target_lang, db)
            results[target_lang] = result["translated_text"]
    return results


async def translate_message_for_all_languages(
    text: str,
    source_language: str,
    db: Optional[AsyncSession] = None,
) -> Dict[str, str]:
    """Translate a message into all supported languages."""
    target_languages = [lang for lang in SUPPORTED_LANGUAGES if lang != source_language]
    translations = await batch_translate(text, source_language, target_languages, db)
    translations[source_language] = text  # Include original
    return translations


async def improve_translation(
    original_text: str,
    current_translation: str,
    source_language: str,
    target_language: str,
    context: Optional[str] = None,
) -> Dict[str, str]:
    """Use AI to improve an existing translation."""
    src_name = LANGUAGE_NAMES.get(source_language, source_language)
    tgt_name = LANGUAGE_NAMES.get(target_language, target_language)

    context_str = f"\nConversation context: {context}" if context else ""

    prompt = (
        f"You are an expert translator for African languages.\n"
        f"Original {src_name} text: {original_text}\n"
        f"Current {tgt_name} translation: {current_translation}{context_str}\n\n"
        f"Please provide an improved, more natural {tgt_name} translation. "
        f"Also explain briefly what you improved and why. "
        f"Format your response as JSON: {{\"improved_translation\": \"...\", \"explanation\": \"...\", \"confidence\": 0.95}}"
    )

    response = await openai_client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": prompt}],
        max_tokens=500,
        temperature=0.4,
    )

    content = response.choices[0].message.content.strip()
    try:
        result = json.loads(content)
        return result
    except json.JSONDecodeError:
        return {
            "improved_translation": current_translation,
            "explanation": "Could not parse improvement response.",
            "confidence": 0.5,
        }


async def explain_message(
    text: str,
    source_language: str,
    target_language: str,
) -> str:
    """Provide cultural context explanation for a message."""
    src_name = LANGUAGE_NAMES.get(source_language, source_language)
    tgt_name = LANGUAGE_NAMES.get(target_language, target_language)

    prompt = (
        f"Explain this {src_name} message to someone who speaks {tgt_name}. "
        f"Include cultural context, tone, and any idiomatic expressions. "
        f"Keep explanation concise (2-3 sentences).\n\nMessage: {text}"
    )

    response = await openai_client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": prompt}],
        max_tokens=300,
        temperature=0.5,
    )

    return response.choices[0].message.content.strip()
