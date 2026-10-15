"""Quick probe: does the configured GOOGLE_API_KEY + model work on the Live API?"""
import asyncio, json, os, sys, websockets

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), "..", "backend", ".env"))

KEY = os.environ["GOOGLE_API_KEY"]
URL = ("wss://generativelanguage.googleapis.com/ws/"
       "google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=" + KEY)

async def probe(model: str):
    cfg = {"setup": {"model": model, "generationConfig": {"responseModalities": ["AUDIO"]}}}
    try:
        async with websockets.connect(URL, max_size=None) as ws:
            await ws.send(json.dumps(cfg))
            resp = json.loads(await asyncio.wait_for(ws.recv(), 10))
            if resp.get("setupComplete") is None:
                return f"REJECTED: {json.dumps(resp)[:300]}"
            # Stream 1s of (near-)silence and see if the session survives.
            import base64
            silence = base64.b64encode(b"\x00" * 32000).decode()
            for _ in range(5):
                await ws.send(json.dumps({"realtimeInput": {"audio": {
                    "mimeType": "audio/pcm;rate=16000", "data": silence}}}))
            import time
            t0 = time.time()
            try:
                while True:
                    msg = json.loads(await asyncio.wait_for(ws.recv(), 8))
                    sc = msg.get("serverContent")
                    if sc:
                        turn = sc.get("modelTurn", {})
                        audio = any((p.get("inlineData") or {}).get("data")
                                    for p in turn.get("parts", []))
                        if audio:
                            return f"OK ({time.time()-t0:.1f}s, got TRANSLATED AUDIO)"
                        if "interrupted" in sc or "turnComplete" in sc:
                            return f"OK ({time.time()-t0:.1f}s, session alive, no audio)"
            except asyncio.TimeoutError:
                return f"OK ({time.time()-t0:.1f}s, setup accepted, no server content in 8s)"
    except Exception as e:
        return f"FAILED: {type(e).__name__}: {str(e)[:200]}"

async def main():
    for model in ["models/gemini-3.5-live-translate-preview",
                  "models/gemini-2.5-flash-native-audio-preview-09-2025",
                  "models/gemini-2.0-flash-live-001"]:
        print(f"{model:55s} -> {await probe(model)}")

asyncio.run(main())
