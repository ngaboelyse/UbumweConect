"""Translate-model probe WITHOUT systemInstruction (setup mirrors what the service sends)."""
import asyncio
import base64
import io
import json
import os
import subprocess
import websockets

from gtts import gTTS

URL = ("wss://generativelanguage.googleapis.com/ws/"
       "google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")

buf = io.BytesIO()
gTTS("Bonjour, comment allez-vous?", lang="fr").write_to_fp(buf)
p = subprocess.run(["ffmpeg", "-v", "error", "-i", "pipe:0", "-f", "s16le",
                    "-ar", "16000", "-ac", "1", "pipe:1"],
                   input=buf.getvalue(), capture_output=True)
PCM = p.stdout
print("pcm", len(PCM), flush=True)


async def main():
    ws = await websockets.connect(URL + "?key=" + os.environ["GOOGLE_API_KEY"], max_size=None)
    setup = {
        "setup": {
            "model": "models/gemini-3.5-live-translate-preview",
            "generationConfig": {
                "responseModalities": ["AUDIO"],
                "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": "Kore"}}},
            },
        }
    }
    await ws.send(json.dumps(setup))
    print("setup:", await ws.recv(), flush=True)
    for i in range(0, len(PCM), 3200):
        await ws.send(json.dumps({"realtimeInput": {"audio": {
            "mimeType": "audio/pcm;rate=16000",
            "data": base64.b64encode(PCM[i:i + 3200]).decode()}}}))
    n_audio, texts = 0, []
    try:
        for _ in range(200):
            raw = await asyncio.wait_for(ws.recv(), 30)
            msg = json.loads(raw)
            sc = msg.get("serverContent", {})
            it = sc.get("inputTranscription")
            ot = sc.get("outputTranscription")
            if it:
                print("IN :", it.get("text", "")[:80], flush=True)
            if ot:
                print("OUT:", ot.get("text", "")[:80], flush=True)
            for part in sc.get("modelTurn", {}).get("parts", []):
                d = (part.get("inlineData") or {}).get("data")
                if d:
                    n_audio += len(d)
            if sc.get("turnComplete"):
                print("TURN COMPLETE", flush=True)
                break
    except asyncio.TimeoutError:
        print("recv timeout", flush=True)
    print("audio bytes:", n_audio, flush=True)
    await ws.close()


asyncio.run(main())
