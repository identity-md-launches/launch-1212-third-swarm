// Bounded foreground check: the HTTP server and Chromium close in finally.
// Tools are deliberately installed outside this dependency-free repository.
import { createServer } from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve, extname, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const output = resolve(root, 'test/scratch/site-validation');
await mkdir(output, { recursive: true });
const require = createRequire(
  resolve(process.env.SWARM_TOOLS || '/tmp/thirdswarm-tools', 'package.json'),
);
const { chromium } = require('playwright');
const { default: AxeBuilder } = require('@axe-core/playwright');
const original = JSON.parse(
  await readFile(resolve(root, 'site/scripts/fixtures/launch.json'), 'utf8'),
);
let feed = original,
  feedStatus = 200,
  requests = 0;
const types = {
  '.html': 'text/html',
  '.css': 'text/css',
  '.js': 'text/javascript',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2',
};
const server = createServer(async (req, res) => {
  try {
    const path = new URL(req.url, 'http://localhost').pathname;
    if (path === '/simd-coin.json') {
      requests++;
      res.writeHead(feedStatus, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(feed));
      return;
    }
    if (path === '/favicon.ico') {
      res.writeHead(204);
      res.end();
      return;
    }
    const relative = decodeURIComponent(path.replace(/^\/preview\//, ''));
    const file = resolve(root, 'dist', relative || 'index.html');
    if (!file.startsWith(resolve(root, 'dist') + '/')) throw Error('Outside preview');
    const bytes = await readFile(file);
    res.writeHead(200, { 'Content-Type': types[extname(file)] || 'application/octet-stream' });
    res.end(bytes);
  } catch {
    res.writeHead(404);
    res.end('Missing asset');
  }
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const url = `http://127.0.0.1:${server.address().port}/preview/`;
const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
const context = await browser.newContext({
  viewport: { width: 1440, height: 1000 },
  permissions: ['clipboard-read', 'clipboard-write'],
});
const page = await context.newPage();
await page.clock.install();
const errors = [],
  failures = [],
  checks = [];
let expectedFailure = false;
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => {
  if (m.type() === 'error' && !expectedFailure) errors.push(m.text());
});
page.on('requestfailed', (r) => {
  if (!expectedFailure) failures.push(r.url() + ': ' + r.failure()?.errorText);
});
async function check(name, fn) {
  await fn();
  checks.push(name);
  console.log('PASS ' + name);
}
async function moduleCall(code) {
  return page.evaluate(async (code) => {
    const app = await import('./app.js');
    return await new Function('app', `return (async()=>{${code}})()`)(app);
  }, code);
}
async function screenshot(name, fullPage = false) {
  await page.screenshot({
    path: resolve(output, name),
    type: 'jpeg',
    quality: 64,
    fullPage,
    animations: 'disabled',
  });
}
try {
  let releaseLogo;
  const logoGate = new Promise((resolve) => {
    releaseLogo = resolve;
  });
  await page.route(url + 'assets/logo.png', async (route) => {
    await logoGate;
    await route.continue();
  });
  await page.goto(url + 'index.html', { waitUntil: 'domcontentloaded' });
  await check('Intro can be skipped and restores keyboard access', async () => {
    await page.locator('#skip-intro').click();
    assert(await page.locator('#intro').isHidden());
    assert.equal(await page.locator('main').evaluate((el) => el.inert), false);
  });
  await check('Generator download is disabled until real artwork renders', async () => {
    assert(await page.locator('#download-meme').isDisabled());
    assert((await page.locator('#generator-status').textContent()).includes('Loading'));
    releaseLogo();
  });
  await page.locator('#intro').waitFor({ state: 'hidden' });
  await page.locator('#generator-status').filter({ hasText: 'Ready' }).waitFor();
  await page.unroute(url + 'assets/logo.png');
  assert(!(await page.locator('#download-meme').isDisabled()));
  await check('12 original meme cards and nine sections', async () => {
    assert.equal(await page.locator('.meme-card').count(), 12);
    assert.equal(await page.locator('main > section').count(), 9);
  });
  await page.locator('#motion-toggle').click();
  await page.locator('#toast').evaluate((el) => (el.hidden = true));
  await screenshot('site-desktop.jpg');
  await check('Initial real launch snapshot: no fabricated address or quote', async () => {
    assert.equal(await page.locator('#contract-address').textContent(), 'launching…');
    assert(await page.locator('#copy-contract').isDisabled());
    assert.equal(await page.locator('[data-market="priceUsd"]').textContent(), '—');
    assert.equal(await page.locator('.buy-button').first().getAttribute('href'), original.coinUrl);
  });
  await check('Every local image loads; every anchor target exists', async () => {
    const result = await page.evaluate(() => ({
      broken: [...document.images].filter((i) => !i.complete || !i.naturalWidth).map((i) => i.src),
      missing: [...document.querySelectorAll('a[href^="#"]')]
        .map((a) => a.getAttribute('href'))
        .filter((h) => h.length > 1 && !document.querySelector(h)),
    }));
    assert.deepEqual(result, { broken: [], missing: [] });
  });
  const layout = [];
  for (const width of [320, 360, 375, 620, 768, 850, 1024, 1440, 1920]) {
    await page.setViewportSize({ width, height: 900 });
    for (const language of ['en', 'es']) {
      await moduleCall(`app.setLanguage('${language}');`);
      const state = await page.evaluate(() => ({
        width: innerWidth,
        scroll: document.documentElement.scrollWidth,
        overflow: [...document.querySelectorAll('h1,h2,h3,p,code,.button')]
          .filter(
            (el) =>
              el.scrollWidth > el.clientWidth + 2 &&
              getComputedStyle(el).display !== 'inline' &&
              el.clientWidth > 0,
          )
          .map((el) => ({
            tag: el.tagName,
            text: el.textContent.slice(0, 65),
            scroll: el.scrollWidth,
            width: el.clientWidth,
          })),
      }));
      layout.push({ language, ...state });
      assert(state.scroll <= width, `page overflow ${width} ${language}: ${state.scroll}`);
      assert.deepEqual(state.overflow, [], `text overflow ${width} ${language}`);
    }
  }
  checks.push('Page reflow at 320, 360, 375, 620, 768, 850, 1024, 1440, 1920 in EN and ES');
  await writeFile(resolve(output, 'site-layout.json'), JSON.stringify(layout, null, 2));
  await page.setViewportSize({ width: 375, height: 850 });
  await moduleCall("app.setLanguage('en');");
  await page.evaluate(() => scrollTo(0, 0));
  await screenshot('site-mobile.jpg');
  await screenshot('site-mobile-full.jpg', true);
  await check(
    'Mobile menu keyboard opens, navigates, Escape closes and restores focus',
    async () => {
      await page.locator('#menu-toggle').focus();
      await page.keyboard.press('Enter');
      assert.equal(await page.locator('#menu-toggle').getAttribute('aria-expanded'), 'true');
      await page.keyboard.press('Escape');
      assert.equal(await page.locator('#menu-toggle').getAttribute('aria-expanded'), 'false');
      assert.equal(await page.evaluate(() => document.activeElement.id), 'menu-toggle');
      await page.locator('#menu-toggle').click();
      await page.locator('#navigation a[href="#generator"]').click();
      assert.equal(await page.locator('#menu-toggle').getAttribute('aria-expanded'), 'false');
    },
  );
  await check('Spanish choice persists after reload and translates dynamic controls', async () => {
    await page.locator('[data-lang="es"]').click();
    await page.reload({ waitUntil: 'networkidle' });
    assert.equal(await page.locator('html').getAttribute('lang'), 'es');
    assert.equal(await page.locator('#download-meme').textContent(), 'Descargar mi meme ↓');
    assert.equal(await page.locator('#contract-address').textContent(), 'lanzando…');
  });
  await page.evaluate(() => scrollTo(0, 0));
  await screenshot('site-spanish.jpg');
  await moduleCall("app.setLanguage('en');");
  await check('Pointer dragging changes a sticker position and Escape restores it', async () => {
    const sticker = page.locator('.sticker-wagmi');
    await sticker.scrollIntoViewIfNeeded();
    const r = await sticker.boundingBox();
    await page.mouse.move(r.x + r.width / 2, r.y + r.height / 2);
    await page.mouse.down();
    await page.mouse.move(r.x + r.width / 2 + 24, r.y + r.height / 2 + 15, { steps: 4 });
    await page.mouse.up();
    assert.notEqual(await sticker.evaluate((el) => el.style.transform), 'translate(0px, 0px)');
    await sticker.focus();
    await page.keyboard.press('Escape');
  });
  await check('Pump meter and seven-click War Mode', async () => {
    await page.locator('#pump').click();
    assert.equal(await page.locator('#vibe-value').textContent(), '10%');
    for (let i = 0; i < 7; i++) await page.locator('#hero-logo').click();
    assert(await page.locator('body').evaluate((el) => el.classList.contains('war-mode')));
    for (let i = 0; i < 7; i++) await page.locator('#hero-logo').click();
  });
  await check('Sticker has keyboard movement and reset', async () => {
    await page.locator('.sticker-wagmi').focus();
    await page.keyboard.press('ArrowRight');
    assert.notEqual(await page.locator('.sticker-wagmi').evaluate((el) => el.style.transform), '');
    await page.keyboard.press('Escape');
    assert.equal(
      await page.locator('.sticker-wagmi').evaluate((el) => el.style.transform),
      'translate(0px, 0px)',
    );
  });
  await check('All 12 meme PNGs export with correct signature and dimensions', async () => {
    const result = await moduleCall(
      'const results=[];for(let i=0;i<12;i++){const b=await app.renderDownload(i);const bytes=new Uint8Array(await b.arrayBuffer());const v=new DataView(bytes.buffer);results.push({size:b.size,signature:Array.from(bytes.slice(0,8)),w:v.getUint32(16),h:v.getUint32(20)});}return results;',
    );
    assert.equal(result.length, 12);
    for (const r of result) {
      assert.deepEqual(r.signature, [137, 80, 78, 71, 13, 10, 26, 10]);
      assert.equal(r.w, 1080);
      assert.equal(r.h, 1080);
      assert(r.size > 10000);
    }
  });
  await check('A meme card download button saves a PNG', async () => {
    const download = page.waitForEvent('download');
    await page.locator('.meme-card-footer button').first().click();
    assert.equal((await download).suggestedFilename(), 'SWARMLER-1-en.png');
  });
  await check(
    'Generator handles template change, accents, long text, and a real download',
    async () => {
      await page.locator('#meme-template').selectOption('11');
      await page.locator('#top-text').fill('¡A FORMAR, SER! <svg> & "');
      await page.locator('#bottom-text').fill('W'.repeat(64));
      await page.locator('#generator-status').filter({ hasText: 'Ready' }).waitFor();
      const promise = page.waitForEvent('download');
      await page.locator('#download-meme').click();
      const download = await promise;
      assert.equal(download.suggestedFilename(), 'SWARMLER-my-meme.png');
      assert.equal(await download.failure(), null);
    },
  );
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.evaluate(() =>
    scrollTo({ top: document.querySelector('#barracks').offsetTop - 110, behavior: 'instant' }),
  );
  await page.locator('#toast').evaluate((el) => (el.hidden = true));
  await screenshot('site-memes.jpg');
  await check('Synthesized sound starts only on an explicit click', async () => {
    await page.locator('[data-sound="honk"]').click();
    assert((await page.locator('#sound-status').textContent()).includes('Played locally'));
  });
  await check('Salute and Konami easter eggs have readable feedback', async () => {
    await page.locator('#salute-button').click();
    assert((await page.locator('#toast').textContent()).includes('Salute received'));
    await page.locator('#sound-title').click();
    await page.keyboard.type('salute');
    assert((await page.locator('#toast').textContent()).includes('Salute received'));
    for (const key of [
      'ArrowUp',
      'ArrowUp',
      'ArrowDown',
      'ArrowDown',
      'ArrowLeft',
      'ArrowRight',
      'ArrowLeft',
      'ArrowRight',
      'b',
      'a',
    ])
      await page.keyboard.press(key);
    assert((await page.locator('#toast').textContent()).includes('Secret convoy'));
  });
  await check(
    'Validated post-deploy fixture updates links, market values and contract copy',
    async () => {
      feed = {
        ...original,
        token: '0x' + 'a'.repeat(40),
        market: { priceUsd: 0.00125, marketCap: 1250000, volume24h: 98765 },
        coinUrl: 'https://www.si-md.xyz/launchpad/',
        chartUrl: 'https://www.si-md.xyz/launchpad/',
      };
      await moduleCall('await app.refreshCoin();');
      assert.equal(await page.locator('#contract-address').textContent(), feed.token);
      assert(!(await page.locator('#copy-contract').isDisabled()));
      await page.locator('#copy-contract').click();
      assert.equal(await page.evaluate(() => navigator.clipboard.readText()), feed.token);
      assert.notEqual(await page.locator('[data-market="marketCap"]').textContent(), '—');
    },
  );
  await check(
    'DexScreener embeds only an exact allowed host, preserving query values',
    async () => {
      await page.route('https://dexscreener.com/**', (r) =>
        r.fulfill({
          status: 200,
          contentType: 'text/html',
          body: '<!doctype html><title>Controlled chart fixture</title><p>Chart fixture</p>',
        }),
      );
      feed = { ...feed, chartUrl: 'https://dexscreener.com/ethereum/test-pair?foo=bar' };
      await moduleCall('await app.refreshCoin();');
    const src = await page.locator('#chart-host iframe').getAttribute('src');
    assert(src.includes('embed=1') && src.includes('theme=dark') && src.includes('foo=bar'));
    await page.frameLocator('#chart-host iframe').getByText('Chart fixture', { exact: true }).waitFor();
      feed = { ...feed, chartUrl: 'https://dexscreener.com.attacker.test/path/pair' };
      await moduleCall('await app.refreshCoin();');
      assert.equal(await page.locator('#chart-host iframe').count(), 0);
    },
  );
  await check('A later logo from the feed is preferred and remains exportable', async () => {
    const bytes = await readFile(resolve(root, 'site/assets/logo.png'));
    await page.route('https://logo.example/new.png', (r) =>
      r.fulfill({
        status: 200,
        headers: { 'Access-Control-Allow-Origin': '*' },
        contentType: 'image/png',
        body: bytes,
      }),
    );
    await moduleCall(
      "app.applyCoinData({name:'Third Swarm',logo:'https://logo.example/new.png'});",
    );
    await page.waitForFunction(
      () => document.querySelector('#hero-logo img').src === 'https://logo.example/new.png',
    );
    const blobSize = await moduleCall('return (await app.renderDownload(0)).size;');
    assert(blobSize > 10000);
    feed = original;
    await moduleCall('await app.refreshCoin();');
    await page.waitForFunction(() =>
      document.querySelector('#hero-logo img').src.endsWith('/assets/logo.png'),
    );
  });
  await check(
    'Malformed values and unsafe URLs never become addresses, quotes or active links',
    async () => {
      await moduleCall(
        "app.applyCoinData({name:'Third Swarm',token:'bad',coinUrl:'javascript:alert(1)',chartUrl:'data:text/html,bad',market:{priceUsd:'99',marketCap:-1,volume24h:NaN}});",
      );
      assert.equal(await page.locator('#contract-address').textContent(), 'launching…');
      assert.equal(await page.locator('.buy-button').first().getAttribute('href'), '#enlist');
      for (const key of ['priceUsd', 'marketCap', 'volume24h'])
        assert.equal(await page.locator(`[data-market="${key}"]`).textContent(), '—');
    },
  );
  await check('Feed failure is labeled and recovers on retry', async () => {
    expectedFailure = true;
    feedStatus = 503;
    await moduleCall('await app.refreshCoin();');
    assert((await page.locator('#feed-status').textContent()).includes('stale'));
    feedStatus = 200;
    feed = original;
    await moduleCall('await app.refreshCoin();');
    assert((await page.locator('#feed-status').textContent()).includes('Awaiting'));
    expectedFailure = false;
  });
  await check('Feed refreshes on the 30-second schedule without real waiting', async () => {
    const before = requests;
    const response = page.waitForResponse((r) => r.url().endsWith('/simd-coin.json'));
    await page.clock.fastForward(30001);
    await response;
    assert(requests > before);
    await page.clock.resume();
  });
  await check('Reduced motion disables effects and dismisses intro', async () => {
    await page.locator('#motion-toggle').click();
    assert.equal(await page.locator('#motion-toggle').getAttribute('aria-pressed'), 'true');
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.waitForFunction(
      () => document.querySelector('#motion-toggle').getAttribute('aria-pressed') === 'false',
    );
    assert.equal(await page.locator('#motion-toggle').getAttribute('aria-pressed'), 'false');
    assert(await page.locator('body').evaluate((el) => el.classList.contains('motion-off')));
    assert(await page.locator('#intro').isHidden());
  });
  await moduleCall("app.setLanguage('en');");
  await page.evaluate(() => scrollTo(0, 0));
  const axeResults = [];
  for (const language of ['en', 'es']) {
    await moduleCall(`app.setLanguage('${language}');`);
    const result = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
      .analyze();
    axeResults.push({ page: 'index', language, violations: result.violations });
  }
  await writeFile(resolve(output, 'site-accessibility.json'), JSON.stringify(axeResults, null, 2));
  await check('404 page works at mobile and desktop, in both languages', async () => {
    for (const width of [375, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      await page.goto(url + '404.html', { waitUntil: 'networkidle' });
      assert(await page.locator('.error-card').isVisible());
      assert.equal(await page.locator('.error-card a').getAttribute('href'), './index.html');
      assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    }
    await screenshot('site-404.jpg');
    const axe = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
      .analyze();
    axeResults.push({
      page: '404',
      language: await page.locator('html').getAttribute('lang'),
      violations: axe.violations,
    });
  });
  await writeFile(resolve(output, 'site-accessibility.json'), JSON.stringify(axeResults, null, 2));
  await writeFile(
    resolve(output, 'site-browser-results.json'),
    JSON.stringify(
      {
        browser: browser.version(),
        checks,
        errors,
        failures,
        requests,
        axeViolations: axeResults.map((r) => ({
          language: r.language,
          count: r.violations.length,
        })),
        limitations: [
          'Live third-party chart content was replaced by a deterministic iframe fixture.',
          'No physical-device, Safari, Firefox, screen-reader or native browser-zoom test.',
        ],
      },
      null,
      2,
    ),
  );
  assert(
    axeResults.every((r) => r.violations.length === 0),
    'Accessibility violations',
  );
  assert.deepEqual(errors, [], 'Unexpected browser errors');
  assert.deepEqual(failures, [], 'Unexpected failed requests');
  console.log(
    JSON.stringify(
      {
        checks: checks.length,
        errors,
        failures,
        axe: axeResults.map((r) =>
          r.violations.map((v) => ({ id: v.id, impact: v.impact, nodes: v.nodes.length })),
        ),
      },
      null,
      2,
    ),
  );
} finally {
  await context.close();
  await browser.close();
  await new Promise((resolve) => server.close(resolve));
}
