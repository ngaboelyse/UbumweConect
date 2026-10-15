"""gemini-3.8-live long-wait probe: is the model just slow, or silent forever?"""
import asyncio, base64, io, json, os, subprocess, websockets
from gtts import gTTS

URL = ("wss://generativelanguage.googleapis.com/ws/"
       "google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")

buf = io.BytesIO()
gTTS("Bonjour, comment allez-vous? Je suis tres content de vous parler aujourd'hui.", lang="fr").write_to_fp(buf)
p = subprocess.run(["ffmpeg", "-v", "error", "-i", "pipe:0", "-f", "s16le",
                    "-ar", "16000", "-ac", "1", "pipe:1"],
                   input=buf.getvalue(), capture_output=True)
PCM = p.stdout
print("pcm", len(PCM), flush=True)


async def main():
    ws = await websockets.connect(URL + "?key=" + os.environ["GOOGLE_API_KEY"], max_size=None)
    setup = {
        "setup": {
            "model": "models/gemini-3.8-live",
            "generationConfig": {
                "responseModalities": ["AUDIO"],
                "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": "Kore"}}},
            },
            "systemInstruction": {"parts": [{"text": (
                "You are a real-time speech interpreter. The user speaks French. "
                "Immediately repeat everything they say, translated into English, spoken aloud. "
                "Do not add anything else.")}]},
        }
    }
    await ws.send(json.dumps(setup))
    print("setup:", await ws.recv(), flush=True)
    for i in range(0, len(PCM), 3200):
        await ws.send(json.dumps({"realtimeInput": {"audio": {
            "mimeType": "audio/pcm;rate=16000",
            "data": base64.b64encode(PCM[i:i+3200]).decode()}}}))
    print("all audio sent", flush=True)
    n_audio = 0
    try:
        while True:
            raw = await asyncio.wait_for(ws.recv(), 90)
            msg = json.loads(raw)
            sc = msg.get("serverContent", {})
            for part in sc.get("modelTurn", {}).get("parts", []):
                if part.get("inlineData"):
                    n_audio += len(part["inlineData"].get("data", ""))
                if part.get("text"):
                    print("TEXT:", part["text"][:100], flush=True)
            if msg.get("voiceActivity"):
                print("VAD:", msg["voiceActivity"], flush=True)
            if sc:
                print("SC keys:", {k: (v if not isinstance(v, (dict, list)) else '...') for k, v in sc.items()}, flush=True)
            if sc.get("turnComplete"):
                print("TURN COMPLETE; audio bytes:", n_audio, flush=True)
                break
    except asyncio.TimeoutError:
        print("TIMEOUT after 90s; audio bytes so far:", n_audio, flush=True)
    await ws.close()


asyncio.run(main())
