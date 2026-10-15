"""One-off probe: feed real French speech into a LiveTranslationSession and see
whether Gemini returns translated audio/text."""
import asyncio
import base64
import io
import subprocess
import sys

sys.path.insert(0, ".")

from app.services.gemini_live_service import LiveTranslationSession  # noqa: E402


async def main():
    got_audio, got_text = [], []

    def on_audio(b):
        got_audio.append(len(b))

    def on_text(x):
        got_text.append(x)
        print("TEXT:", repr(x)[:150])

    s = LiveTranslationSession("probe", "a", "b", "french", "english",
                               on_audio=on_audio, on_text=on_text)
    ok = await s.start()
    print("session started:", ok)
    if not ok:
        return

    from gtts import gTTS
    buf = io.BytesIO()
    gTTS("Bonjour, comment allez-vous?", lang="fr").write_to_fp(buf)
    p = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", "pipe:0", "-f", "s16le", "-ar", "16000", "-ac", "1", "pipe:1"],
        input=buf.getvalue(), capture_output=True,
    )
    pcm = p.stdout
    print("pcm bytes:", len(pcm))
    for i in range(0, len(pcm), 3200):
        await s.send_audio_chunk(base64.b64encode(pcm[i:i + 3200]).decode())

    # wait up to 30s for any audio
    for _ in range(15):
        await asyncio.sleep(2)
        if got_audio:
            break
    await asyncio.sleep(10)
    print("audio frames:", len(got_audio), "total bytes:", sum(got_audio))
    await s.close()


asyncio.run(main())
