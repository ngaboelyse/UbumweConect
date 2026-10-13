"""
Gemini Live API integration for real-time translated voice playback during calls.

A `LiveTranslationSession` wraps one Gemini Live WebSocket session for a single
(directional) speaker. The speaker's WebRTC mic audio is streamed in as 16-bit
PCM frames; Gemini transcribes it, translates it into the receiver's language,
and returns translated speech audio in the receiver's chosen Gemini voice.

The translated audio frames are forwarded to the receiver's app over the main
WebSocket (base64-encoded "voice_translation" events) where Flutter plays them.

Free-tier note: the Gemini Live API free tier is sufficient for capstone demos
(a few sessions/day, ~10 min session limit). The integration code is identical
for the paid tier — only quotas differ.

Setup: get a key at https://aistudio.google.com/apikey and set GOOGLE_API_KEY.
"""

import asyncio
import base64
import json
from typing import Optional, Callable, Dict

import websockets

from app.config import settings


GEMINI_LIVE_URL = (
    "wss://generativelanguage.googleapis.com/ws/"
    "google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
)

# Gemini built-in voices the receiver can pick from (subset of the Live API catalog).
GEMINI_VOICES = [
    "Zephyr", "Puck", "Charon", "Kore", "Fenrir", "Aoede",
    "Leda", "Orus", "Fenix", "Nova", "Angus", "Alume",
]

DEFAULT_VOICE = "Kore"

# 16-bit PCM mono @16 kHz in, 24 kHz out — Live API native audio rates.
INPUT_SAMPLE_RATE = 16000
OUTPUT_SAMPLE_RATE = 24000

# Supported spoken languages (Live API audio output). Kinyarwanda is handled
# via text TTS fallback only if Gemini's speech covers it; otherwise the
# receiver still gets the spoken translation in the configured output voice
# for supported languages and text subtitles for unsupported pairs.
SPOKEN_LANGUAGES = {
    "english": "en-US",
    "french": "fr-FR",
    "swahili": "sw-KE",
    "spanish": "es-ES",
    "arabic": "ar-EG",
    "portuguese": "pt-BR",
    "german": "de-DE",
    "chinese": "zh-CN",
    # Kinyarwanda speech output is not yet offered by the Live API; we still
    # request it by name in the system instruction — Gemini will speak the
    # closest supported variant or fall back to the text channel.
    "kinyarwanda": "rw-RW",
}

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


def _has_gemini_key() -> bool:
    key = (settings.GOOGLE_API_KEY or "").strip()
    return bool(key) and not key.startswith("placeholder")


def _session_config(source_language: str, target_language: str, voice: str) -> dict:
    """System instruction + audio config for one translation session."""
    src = LANGUAGE_NAMES.get(source_language, source_language)
    tgt = LANGUAGE_NAMES.get(target_language, target_language)
    return {
        "setup": {
            "model": "models/gemini-2.5-flash-native-audio-preview-09-2025",
            "generationConfig": {
                "responseModalities": ["AUDIO"],
                "speechConfig": {
                    "voiceConfig": {"prebuiltVoiceConfig": {"voiceName": voice}}
                },
            },
            "systemInstruction": {
                "parts": [{
                    "text": (
                        f"You are a real-time speech interpreter. The user speaks {src}. "
                        f"Immediately repeat everything they say, translated naturally into {tgt}, "
                        f"spoken aloud. Do not answer, comment, or add anything — only the "
                        f"translation of what was said, in a neutral conversational tone. "
                        f"Preserve meaning, tone and cultural nuance."
                    )
                }]
            },
        }
    }


class LiveTranslationSession:
    """One speaker -> one Gemini Live session -> translated audio for the receiver."""

    def __init__(
        self,
        call_id: str,
        speaker_user_id: str,
        receiver_user_id: str,
        source_language: str,
        target_language: str,
        voice: str = DEFAULT_VOICE,
        on_audio: Optional[Callable[[str], None]] = None,
        on_text: Optional[Callable[[str], None]] = None,
    ):
        self.call_id = call_id
        self.speaker_user_id = speaker_user_id
        self.receiver_user_id = receiver_user_id
        self.source_language = source_language
        self.target_language = target_language
        self.voice = voice if voice in GEMINI_VOICES else DEFAULT_VOICE
        self._on_audio = on_audio        # called with base64 PCM chunks for the receiver
        self._on_text = on_text          # called with interim transcript (optional UI)
        self._ws: Optional[websockets.WebSocketClientProtocol] = None
        self._receiver_task: Optional[asyncio.Task] = None
        self.closed = False

    async def start(self) -> bool:
        """Open the Gemini Live session. Returns False if unavailable (no key etc.)."""
        if not _has_gemini_key():
            print("[gemini-live] GOOGLE_API_KEY not configured — voice translation disabled")
            return False
        url = f"{GEMINI_LIVE_URL}?key={settings.GOOGLE_API_KEY}"
        try:
            self._ws = await websockets.connect(url, max_size=None)
        except Exception as e:
            print(f"[gemini-live] connect failed: {e}")
            return False

        await self._ws.send(json.dumps(_session_config(
            self.source_language, self.target_language, self.voice
        )))
        self._receiver_task = asyncio.create_task(self._receive_loop())
        return True

    async def send_audio_chunk(self, pcm_base64: str) -> None:
        """Feed one base64-encoded 16-bit PCM chunk (16 kHz mono) from the speaker."""
        if self.closed or not self._ws:
            return
        message = {
            "realtimeInput": {
                "audio": {
                    "mimeType": f"audio/pcm;rate={INPUT_SAMPLE_RATE}",
                    "data": pcm_base64,
                }
            }
        }
        try:
            await self._ws.send(json.dumps(message))
        except Exception as e:
            print(f"[gemini-live] send failed: {e}")

    async def _receive_loop(self) -> None:
        """Read Gemini responses; forward translated audio/transcript to the receiver."""
        try:
            async for raw in self._ws:
                msg = json.loads(raw)
                sc = msg.get("serverContent", {})

                turn = sc.get("modelTurn", {})
                for part in turn.get("parts", []):
                    inline = part.get("inlineData") or {}
                    b64 = inline.get("data")
                    if b64 and self._on_audio:
                        self._on_audio(b64)
                    text = part.get("text")
                    if text and self._on_text:
                        self._on_text(text)

                if sc.get("interrupted") and self._on_text:
                    self._on_text("")  # signal receiver to stop playback (barge-in)

                if sc.get("turnComplete") and self._on_text:
                    self._on_text(None)  # end-of-utterance marker
        except Exception as e:
            if not self.closed:
                print(f"[gemini-live] receive loop ended: {e}")

    async def close(self) -> None:
        if self.closed:
            return
        self.closed = True
        if self._receiver_task:
            self._receiver_task.cancel()
        if self._ws:
            try:
                await self._ws.close()
            except Exception:
                pass


class LiveTranslationManager:
    """Tracks active sessions per call: one speaker session per (call, speaker)."""

    def __init__(self):
        # call_id -> {speaker_user_id: LiveTranslationSession}
        self.sessions: Dict[str, Dict[str, LiveTranslationSession]] = {}

    def get_session(self, call_id: str, speaker_user_id: str) -> Optional[LiveTranslationSession]:
        return self.sessions.get(call_id, {}).get(speaker_user_id)

    async def start_session(
        self,
        call_id: str,
        speaker_user_id: str,
        receiver_user_id: str,
        source_language: str,
        target_language: str,
        voice: str,
        on_audio=None,
        on_text=None,
    ) -> LiveTranslationSession:
        await self.stop_session(call_id, speaker_user_id)
        session = LiveTranslationSession(
            call_id, speaker_user_id, receiver_user_id,
            source_language, target_language, voice, on_audio, on_text,
        )
        started = await session.start()
        self.sessions.setdefault(call_id, {})[speaker_user_id] = session
        # Even if Gemini is unavailable, keep the session object so the
        # pipeline degrades to text-only (subtitles) instead of erroring.
        session.gemini_available = started
        return session

    async def stop_session(self, call_id: str, speaker_user_id: str) -> None:
        by_speaker = self.sessions.get(call_id)
        if by_speaker and speaker_user_id in by_speaker:
            await by_speaker.pop(speaker_user_id).close()

    async def stop_call(self, call_id: str) -> None:
        for session in self.sessions.pop(call_id, {}).values():
            await session.close()


live_translation_manager = LiveTranslationManager()
