// Verify the live app at :3000 serves the NEW remote-audio player code and
// that the WebRTC pipeline pieces are reachable in the browser.
export default async function run(page, ui) {
  const out = {};
  out.title = await page.title();

  // The Dart code is in the compiled JS bundle; check the new debug strings
  // shipped (watchdog + onTrack logging).
  const html = await page.content();
  // Debug builds inline dart sources into the service worker/main dart js.
  const scripts = await page.evaluate(() =>
    Array.from(document.scripts).map(s => s.src).filter(Boolean)
  );
  out.scriptCount = scripts.length;

  // Probe: does the page's JS contain our new marker strings?
  out.markers = await page.evaluate(async (scripts) => {
    const found = { watchdog: false, onTrackLog: false };
    for (const src of scripts) {
      try {
        const t = await (await fetch(src)).text();
        if (t.includes('remote audio playing')) found.watchdog = true;
        if (t.includes('onTrack: kind=')) found.onTrackLog = true;
      } catch (_) { }
    }
    // Also check inline scripts / dart entrypoint
    const inline = Array.from(document.scripts).map(s => s.textContent || '').join('');
    if (inline.includes('remote audio playing')) found.watchdog = true;
    if (inline.includes('onTrack: kind=')) found.onTrackLog = true;
    return found;
  }, scripts);

  return out;
}
