"""End-to-end test of the voice/call translation pipeline against the live server.

1. Registers/logs in two users (A = kinyarwanda speaker, B = english speaker)
2. Creates a direct conversation
3. Opens WS for B, then:
   a. sends a `call_subtitle` audio chunk (French TTS sample) as A
   b. expects B to receive a `call_subtitle` event with translated text
4. Uploads a voice note as A and checks the returned translations

Run: python e2e_translation_check.py
"""
import asyncio
import base64
import io
import json
import sys

import httpx

BASE = "http://localhost:8000/api/v1"


async def register_or_login(client: httpx.AsyncClient, email: str, password: str, username: str, lang: str) -> dict:
    r = await client.post(f"{BASE}/auth/register", json={
        "email": email, "password": password, "username": username,
        "display_name": username.capitalize(), "preferred_language": lang,
    })
    if r.status_code in (200, 201):
        return r.json()
    r = await client.post(f"{BASE}/auth/login", json={"email": email, "password": password})
    r.raise_for_status()
    return r.json()


async def main() -> None:
    ok = True
    async with httpx.AsyncClient(timeout=60) as client:
        A = await register_or_login(client, "e2e-speaker@example.com", "Passw0rd!123", "e2e_speaker", "kinyarwanda")
        B = await register_or_login(client, "e2e-listener@example.com", "Passw0rd!123", "e2e_listener", "english")
        tok_a = A["access_token"]; tok_b = B["access_token"]
        uid_a = A["user"]["id"]; uid_b = B["user"]["id"]
        ha = {"Authorization": f"Bearer {tok_a}"}

        # 1. Create direct conversation A<->B
        r = await client.post(f"{BASE}/conversations", json={"participant_ids": [uid_b], "type": "direct"}, headers=ha)
        r.raise_for_status()
        conv = r.json()["id"]

        # 2. Generate a French speech sample (gTTS, same engine the server uses)
        from gtts import gTTS
        buf = io.BytesIO()
        gTTS("Bonjour, comment allez-vous? Je suis tres bien.", lang="fr").write_to_fp(buf)
        wav = buf.getvalue()
        print(f"[+] sample audio: {len(wav)} bytes (French)")

        # 3. Open WS for B and for A
        import websockets
        ws_b = await websockets.connect(f"ws://localhost:8000/ws/{uid_b}?token={tok_b}")
        ws_a = await websockets.connect(f"ws://localhost:8000/ws/{uid_a}?token={tok_a}")
        print("[+] websockets connected")

        # 4. A streams a call_subtitle chunk
        await ws_a.send(json.dumps({
            "event": "call_subtitle",
            "data": {
                "call_id": "e2e",
                "conversation_id": conv,
                "audio": base64.b64encode(wav).decode(),
            },
        }))
        print("[+] chunk sent; waiting for B's caption (Whisper + GPT, up to 60s)...")

        caption = None
        try:
            for _ in range(60):
                msg = json.loads(await asyncio.wait_for(ws_b.recv(), timeout=60))
                if msg.get("event") == "call_subtitle":
                    caption = msg["data"]
                    break
        except asyncio.TimeoutError:
            pass

        if caption:
            print(f"[✓] CALL CAPTION ARRIVED")
            print(f"    original  ({caption['source_language']}): {caption['original_text']}")
            print(f"    translated ({caption['target_language']}): {caption['translated_text']}")
        else:
            ok = False
            print("[✗] NO call_subtitle received within 60s — check server logs")

        # 5. Voice note: upload + send, expect translations in the response
        r = await client.post(
            f"{BASE}/conversations/{conv}/attachments",
            files={"file": ("voice.mp3", wav, "audio/mpeg")},
            data={"kind": "voice"},
            headers=ha,
        )
        if r.status_code in (200, 201):
            up = r.json()
            r = await client.post(
                f"{BASE}/conversations/{conv}/messages",
                json={"content": "Voice message", "message_type": "voice", "media_url": up["url"]},
                headers=ha,
            )
            if r.status_code == 201:
                m = r.json()
                tc = m.get("translated_contents") or {}
                print(f"[✓] VOICE NOTE: transcript='{m.get('original_content')}'")
                print(f"    translations: {json.dumps(tc, ensure_ascii=False)[:300]}")
                if "english" not in tc:
                    ok = False
                    print("[✗] no english translation on the voice note")
            else:
                ok = False
                print(f"[✗] send message failed: {r.status_code} {r.text[:200]}")
        else:
            ok = False
            print(f"[✗] upload failed: {r.status_code} {r.text[:200]}")

        await ws_a.close(); await ws_b.close()

    print("\n=== RESULT:", "PASS" if ok else "FAIL", "===")
    sys.exit(0 if ok else 1)


asyncio.run(main())
