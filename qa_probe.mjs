export default async function run(page, ui) {
  await new Promise(r => setTimeout(r, 10000));
  const result = await page.evaluate(async () => {
    // Probe the API the same way the app does, from the page origin.
    try {
      const r = await fetch('http://localhost:8080/api/v1/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: 'x@x.com', password: 'x' }),
      });
      return { sameOriginApi: r.status, detail: (await r.text()).slice(0, 120) };
    } catch (e) {
      return { sameOriginApi: 'error', msg: String(e) };
    }
  });
  return result;
}
