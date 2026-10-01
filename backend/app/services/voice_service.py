import io
from typing import Optional
from openai import AsyncOpenAI
from app.config import settings
from app.services.translation_service import translate, detect_language
from app.services.file_service import FileService


client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)

VOICE_MAP = {
    "english": "alloy",
    "french": "nova",
    "swahili": "shimmer",
    "kinyarwanda": "onyx",  # Best available for African languages
}


class VoiceService:
    def __init__(self):
        self.file_service = FileService()

    async def transcribe_audio(self, audio_bytes: bytes, filename: str = "audio.webm") -> dict:
        """Transcribe audio using OpenAI Whisper."""
        audio_file = io.BytesIO(audio_bytes)
        audio_file.name = filename

        transcript = await client.audio.transcriptions.create(
            model="whisper-1",
            file=audio_file,
            response_format="verbose_json",
        )

        return {
            "text": transcript.text,
            "language": transcript.language or "english",
            "duration": getattr(transcript, "duration", None),
            "segments": getattr(transcript, "segments", []),
        }

    async def text_to_speech(self, text: str, language: str = "english") -> bytes:
        """Convert text to speech using OpenAI TTS."""
        voice = VOICE_MAP.get(language, "alloy")

        response = await client.audio.speech.create(
            model="tts-1",
            voice=voice,
            input=text,
            response_format="mp3",
        )

        return response.content

    async def process_voice_message(
        self,
        audio_bytes: bytes,
        filename: str,
        sender_language: str,
        recipient_language: str,
        user_id: str,
        db=None,
    ) -> dict:
        """
        Full voice message pipeline:
        1. Transcribe audio (Whisper)
        2. Detect language
        3. Translate to recipient language
        4. Generate TTS audio in recipient language
        5. Upload both audio files and return URLs
        """
        # Step 1: Transcribe
        transcription = await self.transcribe_audio(audio_bytes, filename)
        original_text = transcription["text"]
        detected_language = transcription.get("language", sender_language)

        # Normalize detected language
        lang_map = {"rw": "kinyarwanda", "en": "english", "fr": "french", "sw": "swahili"}
        detected_language = lang_map.get(detected_language, sender_language)

        # Step 2 & 3: Translate
        translation_result = await translate(
            text=original_text,
            source_language=detected_language,
            target_language=recipient_language,
            db=db,
        )
        translated_text = translation_result["translated_text"]

        # Step 4: Generate TTS audio
        tts_audio = await self.text_to_speech(translated_text, recipient_language)

        # Step 5: Upload TTS audio
        tts_url = None
        if self.file_service.is_configured():
            tts_url = await self.file_service.upload_bytes(
                data=tts_audio,
                filename=f"tts_{user_id}_{detected_language}_{recipient_language}.mp3",
                folder="voice_translations",
                content_type="audio/mpeg",
            )

        return {
            "original_text": original_text,
            "translated_text": translated_text,
            "source_language": detected_language,
            "target_language": recipient_language,
            "tts_audio_url": tts_url,
            "tts_audio_bytes": tts_audio if not tts_url else None,
        }

    async def generate_live_subtitle(
        self,
        audio_bytes: bytes,
        target_language: str,
        db=None,
    ) -> dict:
        """Real-time subtitle generation for voice/video calls."""
        transcription = await self.transcribe_audio(audio_bytes)
        original_text = transcription["text"]

        lang_map = {"rw": "kinyarwanda", "en": "english", "fr": "french", "sw": "swahili"}
        source_language = lang_map.get(transcription.get("language", "en"), "english")

        translated_text = original_text
        if source_language != target_language:
            result = await translate(original_text, source_language, target_language, db)
            translated_text = result["translated_text"]

        return {
            "original_text": original_text,
            "translated_text": translated_text,
            "source_language": source_language,
            "target_language": target_language,
        }
