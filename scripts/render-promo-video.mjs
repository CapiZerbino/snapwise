// Renders docs/promo/index.html to MP4 by stepping its render(t) function frame by frame in headless Chrome.
// Usage: node scripts/render-promo-video.mjs [lang ...]     (default: en vi)
// Needs Google Chrome and ffmpeg. Writes docs/promo-<lang>.mp4 and docs/promo-<lang>.jpg (poster).
// Set PROMO_STILLS=<dir> to write a few PNG stills there instead, for checking the layout.
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const CHROME = process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PORT = 9347, FPS = 30, DURATION = 30, WIDTH = 1280, HEIGHT = 720, SCALE = 1.5; // 1920×1080 output
const POSTER_AT = 7.4;
const docs = resolve(dirname(fileURLToPath(import.meta.url)), '../docs');
const langs = process.argv.slice(2).length ? process.argv.slice(2) : ['en', 'vi'];
const stillsDir = process.env.PROMO_STILLS;

const profile = mkdtempSync(join(tmpdir(), 'snapwise-promo-'));
const chrome = spawn(CHROME, ['--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
  '--hide-scrollbars', '--no-first-run', 'about:blank'], { stdio: 'ignore' });

/** Minimal Chrome DevTools Protocol client over the page's WebSocket. */
async function connect() {
  let target;
  for (let i = 0; i < 50 && !target; i++) {
    await new Promise(r => setTimeout(r, 200));
    target = await fetch(`http://127.0.0.1:${PORT}/json/list`).then(r => r.json()).then(l => l.find(p => p.type === 'page')).catch(() => null);
  }
  if (!target) throw new Error('Chrome did not start');
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((ok, fail) => { ws.onopen = ok; ws.onerror = fail; });
  let id = 0;
  const pending = new Map(), listeners = new Map();
  ws.onmessage = ({ data }) => {
    const msg = JSON.parse(data);
    if (msg.id) { const p = pending.get(msg.id); pending.delete(msg.id); msg.error ? p.fail(new Error(msg.error.message)) : p.ok(msg.result); }
    else listeners.get(msg.method)?.(msg.params);
  };
  return {
    send: (method, params = {}) => new Promise((ok, fail) => { pending.set(++id, { ok, fail }); ws.send(JSON.stringify({ id, method, params })); }),
    once: method => new Promise(ok => listeners.set(method, p => { listeners.delete(method); ok(p); })),
    close: () => ws.close(),
  };
}

async function shot(cdp, t) {
  await cdp.send('Runtime.evaluate', { expression: `renderAt(${t})` });
  return Buffer.from((await cdp.send('Page.captureScreenshot', { format: 'png' })).data, 'base64');
}

async function renderLanguage(cdp, lang) {
  const loaded = cdp.once('Page.loadEventFired');
  await cdp.send('Page.navigate', { url: `${pathToFileURL(join(docs, 'promo/index.html'))}?capture=1&lang=${lang}` });
  await loaded;

  if (stillsDir) {
    for (const t of [1.8, 5.6, 7.4, 11.0, 12.9, 15.2, 18.9, 19.8, 21.7, 22.5, 24, 28]) writeFileSync(join(stillsDir, `${lang}-${t}.png`), await shot(cdp, t));
    return;
  }

  const output = join(docs, `promo-${lang}.mp4`);
  const ffmpeg = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'png', '-i', '-',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '24', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', output], { stdio: ['pipe', 'inherit', 'inherit'] });
  const done = new Promise((ok, fail) => ffmpeg.on('close', code => code === 0 ? ok() : fail(new Error(`ffmpeg exited with ${code}`))));
  for (let frame = 0; frame < FPS * DURATION; frame++) {
    if (!ffmpeg.stdin.write(await shot(cdp, frame / FPS))) await new Promise(r => ffmpeg.stdin.once('drain', r));
  }
  ffmpeg.stdin.end();
  await done;

  // Poster frame shown before the video loads.
  const poster = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-ss', String(POSTER_AT), '-i', output, '-frames:v', '1', '-vf', 'scale=1280:-2',
    '-q:v', '4', join(docs, `promo-${lang}.jpg`)], { stdio: 'inherit' });
  await new Promise(ok => poster.on('close', ok));
  console.log(`wrote ${output}`);
}

try {
  const cdp = await connect();
  await cdp.send('Page.enable');
  await cdp.send('Emulation.setDeviceMetricsOverride', { width: WIDTH, height: HEIGHT, deviceScaleFactor: SCALE, mobile: false });
  for (const lang of langs) await renderLanguage(cdp, lang);
  cdp.close();
} finally {
  chrome.kill();
  await new Promise(r => setTimeout(r, 300));
  rmSync(profile, { recursive: true, force: true });
}
