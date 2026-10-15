"""Raw Gemini Live probe: send setup + real French speech, print every message."""
import asyncio
import base64
import io
import json
import subprocess

import websockets

URL = ("wss://generativelanguage.googleapis.com/ws/"
       "google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")

MODELS = [
    "models/gemini-2.5-flash-native-audio-preview-09-2025",
    "models/gemini-2.5-flash-live",
    "models/gemini-2.0-flash-live-001",
]

# make French speech PCM (16k mono)
from gtts import gTTS
buf = io.BytesIO()
gTTS("Bonjour, comment allez-vous?", lang="fr").write_to_fp(buf)
p = subprocess.run(["ffmpeg", "-v", "error", "-i", "pipe:0", "-f", "s16le",
                    "-ar", "16000", "-ac", "1", "pipe:1"],
                   input=buf.getvalue(), capture_output=True)
PCM = p.stdout


async def probe(model):
    url = f"{URL}?key={open('/dev/null') and __import__('os').environ['GOOGLE_API_KEY']}"
    try:
        ws = await websockets.connect(url, max_size=None)
    except Exception as e:
        print(model, "CONNECT FAIL:", e)
        return
    setup = {
        "setup": {
            "model": model,
            "generationConfig": {
                "responseModalities": ["AUDIO"],
                "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": "Kore"}}},
            },
            "systemInstruction": {"parts": [{"text": (
                "You are a real-time speech interpreter. The user speaks French. "
                "Immediately repeat everything they say, translated into English, spoken aloud.")}]},
        }
    }
    await ws.send(json.dumps(setup))
    try:
        print(model, "-> setup reply:", (await asyncio.wait_for(ws.recv(), 15))[:200])
    except Exception as e:
        print(model, "-> setup reply FAIL:", type(e).__name__, e)
        await ws.close()
        return
    for i in range(0, len(PCM), 3200):
        await ws.send(json.dumps({"realtimeInput": {"audio": {
            "mimeType": "audio/pcm;rate=16000",
            "data": base64.b64encode(PCM[i:i+3200]).decode()}}}))
    try:
        for _ in range(60):
            msg = json.loads(await asyncio.wait_for(ws.recv(), 45))
            print(model, "->", json.dumps(msg)[:400])
            if msg.get("serverContent", {}).get("turnComplete"):
                break
    except asyncio.TimeoutError:
        # keep reading a bit longer before giving up
        try:
            for _ in range(20):
                msg = json.loads(await asyncio.wait_for(ws.recv(), 15))
                print(model, "->", json.dumps(msg)[:400])
                if msg.get("serverContent", {}).get("turnComplete"):
                    break
        except Exception:
            print(model, "-> still nothing")
    except asyncio.TimeoutError:
        print(model, "-> timeout waiting for responses")
    except Exception as e:
        print(model, "-> recv FAIL:", type(e).__name__, e)
    await ws.close()


async def main():
    for m in MODELS:
        print("=" * 60)
        await probe(m)

asyncio.run(main())
