// Diagnose web remote-audio path: attach probe + autoplay + getUserMedia.
export default async function run(page, ui) {
  const results = {};

  // 1. Does the page see a microphone? (secure-context + permission)
  results.secureContext = await page.evaluate(() => window.isSecureContext);
  results.userAgent = await page.evaluate(() => navigator.userAgent.slice(0, 80));

  // 2. Can the browser enumerate/produce an audio track at all?
  results.micProbe = await page.evaluate(async () => {
    try {
      const s = await navigator.mediaDevices.getUserMedia({ audio: true });
      const tracks = s.getAudioTracks();
      const out = { ok: true, trackCount: tracks.length, label: tracks[0]?.label || '' };
      s.getTracks().forEach(t => t.stop());
      return out;
    } catch (e) {
      return { ok: false, error: String(e && e.name || e).slice(0, 100) };
    }
  });

  // 3. Autoplay policy: would a muted-then-play() <audio> work without a gesture?
  results.autoplay = await page.evaluate(() => {
    const a = new Audio();
    return { autoplayAllowed: !('autoplayPolicy' in navigator) ? 'unknown' : navigator.autoplayPolicy || 'unknown' };
  }).catch(() => null);

  // 4. Probe the exact code path the app uses: create <audio>, attach a dummy
  //    MediaStream, call play(), see if it resolves or rejects.
  results.audioElement = await page.evaluate(async () => {
    try {
      const a = new Audio();
      a.autoplay = true;
      a.muted = false;
      a.volume = 1.0;
      // Attach a silent generated stream so play() has real media.
      const ctx = new AudioContext();
      const dst = ctx.createMediaStreamDestination();
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      gain.gain.value = 0;
      osc.connect(gain).connect(dst);
      osc.start();
      a.srcObject = dst.stream;
      const p = a.play();
      let playResult = 'resolved';
      try { await p; } catch (e) { playResult = 'rejected: ' + String(e && e.name || e); }
      a.pause(); a.srcObject = null;
      osc.stop(); ctx.close();
      return { playResult };
    } catch (e) {
      return { error: String(e).slice(0, 120) };
    }
  });

  // 5. How many <audio> elements exist right now (the app appends one per attach)?
  results.audioElementsInDom = await page.evaluate(() =>
    Array.from(document.querySelectorAll('audio')).map(a => ({
      srcObject: !!a.srcObject,
      paused: a.paused,
      muted: a.muted,
      volume: a.volume,
    }))
  );

  return results;
}
