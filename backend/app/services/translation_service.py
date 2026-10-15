import hashlib
import json
from typing import Optional, Dict, List
from datetime import datetime

import httpx
from openai import AsyncOpenAI
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.config import settings
from app.models.translation import TranslationCache


SUPPORTED_LANGUAGES = ["kinyarwanda", "english", "french", "swahili", "spanish", "arabic", "portuguese", "german", "chinese"]

LANGUAGE_NAMES = {
    "kinyarwanda": "Kinyarwanda",
    "english": "English",
    "french": "French",
    "swahili": "Swahili",
    "spanish": "Spanish",
    "arabic": "Arabic",
    "portuguese": "Portuguese",
    "german": "German",
    "chinese": "Chinese",
}

LANGUAGE_CODES = {
    "kinyarwanda": "rw",
    "english": "en",
    "french": "fr",
    "swahili": "sw",
    "spanish": "es",
    "arabic": "ar",
    "portuguese": "pt",
    "german": "de",
    "chinese": "zh",
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


def _has_openai_key() -> bool:
    """True when a real OpenAI key is configured (not the placeholder)."""
    key = (settings.OPENAI_API_KEY or "").strip()
    return bool(key) and not key.startswith("sk-placeholder")


async def _google_fallback_translate(text: str, source_language: str, target_language: str) -> str:
    """Free fallback using Google's public translate endpoints (no API key).
    Supports Kinyarwanda. Tries clients5.google.com first, then MyMemory."""
    src = LANGUAGE_CODES.get(source_language, "auto")
    tgt = LANGUAGE_CODES.get(target_language, target_language)
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
    async with httpx.AsyncClient(timeout=15, headers=headers) as http:
        # Primary: clients5 translate endpoint (less rate-limited)
        try:
            resp = await http.get(
                "https://clients5.google.com/translate_a/t",
                params={"client": "dict-chrome-ex", "sl": src, "tl": tgt, "q": text},
            )
            resp.raise_for_status()
            data = resp.json()
            # Response: ["translated text"] or [["translated"],...]
            if isinstance(data, list):
                if data and isinstance(data[0], str):
                    return " ".join(part for part in data if isinstance(part, str))
                if data and isinstance(data[0], list) and data[0] and isinstance(data[0][0], str):
                    return data[0][0]
            return str(data)
        except Exception:
            pass
        # Secondary: MyMemory (lower quality for Kinyarwanda, but works)
        try:
            resp = await http.get(
                "https://api.mymemory.translated.net/get",
                params={"q": text, "langpair": f"{src}|{tgt}"},
            )
            resp.raise_for_status()
            return resp.json().get("responseData", {}).get("translatedText", "") or ""
        except Exception:
            pass
    raise RuntimeError("All free translation providers failed")


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

    if not _has_openai_key():
        # No OpenAI key configured: use the free Google fallback + still cache the result.
        translated_text = await _google_fallback_translate(text, source_language, target_language)
        if db:
            await _save_to_cache(db, text, text_hash, source_language, target_language, translated_text)
        return {
            "translated_text": translated_text,
            "source_language": source_language,
            "target_language": target_language,
            "cached": False,
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

    try:
        response = await openai_client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[{"role": "user", "content": prompt}],
            max_tokens=1000,
            temperature=0.3,
        )
        translated_text = response.choices[0].message.content.strip()
    except Exception as e:
        # OpenAI failed (bad key, quota, outage): fall back to the free translator
        # so messages always get translated rather than being delivered as-is.
        try:
            translated_text = await _google_fallback_translate(text, source_language, target_language)
        except Exception:
            raise RuntimeError(f"Translation failed (OpenAI: {e}; fallback also failed)")

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

# ─── Voice message transcription (Whisper + Gemini fallback) ──────

_GEMINI_STT_MODELS = ["gemini-3.5-flash", "gemini-3.1-flash-lite", "gemini-3.8-flash"]
_GEMINI_STT_MIME = {
    "m4a": "audio/mp4", "mp3": "audio/mpeg", "aac": "audio/aac",
    "ogg": "audio/ogg", "wav": "audio/wav", "webm": "audio/webm",
}


async def _gemini_fallback_transcribe(
    audio_bytes: bytes,
    filename: str = "voice.webm",
    hint_language: Optional[str] = None,
) -> Dict:
    """Transcribe audio with Google Gemini (uses the configured GOOGLE_API_KEY).
    Works even when the OpenAI account has no credits."""
    import base64
    key = (getattr(settings, "GOOGLE_API_KEY", "") or "").strip()
    if not key:
        raise RuntimeError("Transcription unavailable: no GOOGLE_API_KEY configured")

    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else "webm"
    mime = _GEMINI_STT_MIME.get(ext, "audio/webm")

    prompt = (
        "Transcribe this audio exactly as spoken. "
        + (f"The speaker most likely speaks {hint_language}. " if hint_language else "")
        + "Reply ONLY with a JSON object: {\"text\": \"<transcript>\", \"language_code\": \"<ISO 639-1 code of the spoken language>\"}"
    )
    payload = {
        "contents": [
            {
                "parts": [
                    {"text": prompt},
                    {"inline_data": {"mime_type": mime, "data": base64.b64encode(audio_bytes).decode("ascii")}},
                ]
            }
        ]
    }
    try:
        last_err = None
        data = None
        async with httpx.AsyncClient(timeout=60) as http:
            # Try each model in turn; retry transient failures (429/5xx) once
            # per model. Gemini flash models are intermittently overloaded.
            for model in _GEMINI_STT_MODELS:
                for attempt in range(2):
                    try:
                        resp = await http.post(
                            f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
                            params={"key": key},
                            json=payload,
                        )
                        if resp.status_code in (429, 500, 502, 503, 504) and attempt < 1:
                            last_err = f"{model}: HTTP {resp.status_code}"
                            import asyncio as _asyncio
                            await _asyncio.sleep(2)
                            continue
                        resp.raise_for_status()
                        data = resp.json()
                        break
                    except httpx.HTTPStatusError as e:
                        last_err = f"{model}: {e}"
                        break
                    except Exception as e:
                        last_err = f"{model}: {e}"
                        if attempt < 1:
                            import asyncio as _asyncio
                            await _asyncio.sleep(2)
                            continue
                if data is not None:
                    break
        if data is None:
            raise RuntimeError(f"Gemini transcription failed: {last_err}")
    except Exception as e:
        raise RuntimeError(f"Gemini transcription failed: {e}")

    try:
        text_out = data["candidates"][0]["content"]["parts"][0]["text"].strip()
        # Strip markdown fences if the model wraps the JSON.
        if text_out.startswith("```"):
            text_out = text_out.strip("`")
            if text_out.startswith("json"):
                text_out = text_out[4:]
            text_out = text_out.strip()
        parsed = json.loads(text_out)
    except Exception as e:
        raise RuntimeError(f"Gemini transcription returned unexpected format: {e}")

    raw_lang = (parsed.get("language_code") or "").lower()
    iso_to_name = {v: k for k, v in LANGUAGE_CODES.items()}
    lang = iso_to_name.get(raw_lang, hint_language or "english")
    return {
        "text": (parsed.get("text") or "").strip(),
        "language": lang,
        "raw_language": raw_lang,
    }


async def transcribe_audio(
    audio_bytes: bytes,
    filename: str = "voice.webm",
    hint_language: Optional[str] = None,
) -> Dict:
    """Transcribe a voice-note audio blob.

    Tries OpenAI Whisper first; on any failure falls back to Google Gemini.
    Returns a dict:
        {
            "text": "<transcript>",
            "language": "english",       # nearest supported language
            "raw_language": "en",        # ISO-639-1 code
        }

    Raises RuntimeError when every provider fails — callers treat
    transcription as best-effort and must never block message delivery on it.
    """
    errors = []
    if _has_openai_key():
        kwargs = {"model": "whisper-1", "response_format": "verbose_json"}
        if hint_language:
            # Whisper understands ISO codes; passing the hint improves accuracy.
            iso = LANGUAGE_CODES.get(hint_language)
            if iso:
                kwargs["language"] = iso
        try:
            response = await openai_client.audio.transcriptions.create(
                file=(filename, audio_bytes),
                **kwargs,
            )
            raw_lang = getattr(response, "language", "") or ""
            iso_to_name = {v: k for k, v in LANGUAGE_CODES.items()}
            lang = iso_to_name.get(raw_lang, hint_language or "english")
            return {
                "text": (response.text or "").strip(),
                "language": lang,
                "raw_language": raw_lang,
                "provider": "openai",
            }
        except Exception as e:
            errors.append(f"Whisper: {e}")
    else:
        errors.append("Whisper: no OpenAI key")

    try:
        result = await _gemini_fallback_transcribe(audio_bytes, filename, hint_language)
        result["provider"] = "gemini"
        return result
    except Exception as e:
        errors.append(str(e))

    raise RuntimeError("Transcription failed — " + " | ".join(errors))


async def transcribe_and_translate_voice(
    audio_bytes: bytes,
    filename: str = "voice.webm",
    hint_language: Optional[str] = None,
    db: Optional[AsyncSession] = None,
) -> Dict:
    """Full voice-note pipeline: transcribe, then translate into all languages.

    Returns:
        {
            "transcript": "<original-language transcript>",
            "language": "<detected language>",
            "translations": {"english": "...", "french": "...", ...},
        }
    """
    result = await transcribe_audio(audio_bytes, filename, hint_language)
    transcript = result["text"]
    if not transcript:
        raise RuntimeError("Transcription produced no text")

    detected = result["language"]
    try:
        translations = await translate_message_for_all_languages(
            transcript, detected, db
        )
    except Exception as e:
        raise RuntimeError(f"Voice translation failed: {e}")

    return {
        "transcript": transcript,
        "language": detected,
        "translations": translations,
    }
