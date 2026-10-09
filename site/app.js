// @ts-check
import { heroArmy, comicScene, soldier, memeSvg, recruits } from './art.js';

/** @template {HTMLElement} T @param {string} selector @returns {T} */
const $ = (selector) => /** @type {T} */ (document.querySelector(selector));
/** @param {string} selector */
const all = (selector) =>
  /** @type {HTMLElement[]} */ (Array.from(document.querySelectorAll(selector)));
const localLogo = new URL('./assets/logo.png', import.meta.url).href;
const suppliedLogo =
  'https://fxumiqjngmabtgvruvka.supabase.co/storage/v1/object/public/forum-attachments/posts/mv1jblgp-o6my9g.png';
/** @param {string} key @param {string} [value] */
function preference(key, value) {
  try {
    if (value !== undefined) localStorage.setItem(key, value);
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}
let lang = preference('swarm-language') === 'es' ? 'es' : 'en';
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
let effects = !reduced.matches && preference('swarm-effects') !== 'off';
let logoUrl = localLogo;
let logoData = '';
let fallbackArt = false;
let logoVersion = 0;
/** @type {Record<string, unknown> | null} */
let coin = null;
let refreshBusy = false;
let lastSuccessful = 0;
let feedError = false;
let toastTimer = 0;
let renderVersion = 0;
let generatorReady = false;
let lastTop = '';
let lastBottom = '';
let logoClicks = 0;
let morale = 0;
let pumpCount = 0;
const initialText = new WeakMap();
/** @param {string} en @param {string} es */
const tr = (en, es) => (lang === 'es' ? es : en);
/** @param {string} message */
function toast(message) {
  const el = $('#toast');
  if (!el) return;
  el.textContent = message;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => (el.hidden = true), 3200);
}

/** @param {unknown} value @returns {string | null} */
export function safeHttps(value) {
  if (typeof value !== 'string' || value.length > 2048) return null;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password ? url.href : null;
  } catch {
    return null;
  }
}
/** @param {unknown} value */
export function validToken(value) {
  return typeof value === 'string' && /^0x[0-9a-fA-F]{40}$/.test(value) && !/^0x0{40}$/i.test(value)
    ? value
    : null;
}
/** @param {string} value */
export function chartEmbed(value) {
  const safe = safeHttps(value);
  if (!safe) return null;
  const url = new URL(safe);
  if (
    !['dexscreener.com', 'www.dexscreener.com'].includes(url.hostname) ||
    url.pathname.split('/').filter(Boolean).length < 2
  )
    return null;
  url.searchParams.set('embed', '1');
  url.searchParams.set('theme', 'dark');
  url.searchParams.set('info', '0');
  url.searchParams.set('trades', '0');
  return url.href;
}

/** @param {string} language */
export function setLanguage(language) {
  lang = language === 'es' ? 'es' : 'en';
  document.documentElement.lang = lang;
  preference('swarm-language', lang);
  all('[data-es]').forEach((el) => {
    if (!initialText.has(el)) initialText.set(el, el.textContent);
    el.textContent = lang === 'es' ? el.dataset.es || '' : initialText.get(el);
  });
  for (const [dataKey, attribute] of [
    ['esLabel', 'aria-label'],
    ['esAlt', 'alt'],
  ])
    all(`[data-${dataKey === 'esLabel' ? 'es-label' : 'es-alt'}]`).forEach((el) => {
      const originalKey = attribute === 'alt' ? 'enAlt' : 'enLabel';
      if (!el.dataset[originalKey]) el.dataset[originalKey] = el.getAttribute(attribute) || '';
      el.setAttribute(
        attribute,
        lang === 'es' ? el.dataset[dataKey] || '' : el.dataset[originalKey] || '',
      );
    });
  all('[data-lang]').forEach((el) =>
    el.setAttribute('aria-pressed', String(el.dataset.lang === lang)),
  );
  document.title = $('.error-card')
    ? tr('Lost frog · Third Swarm', 'Rana perdida · Third Swarm')
    : tr('Third Swarm · $SWARMLER · Fall in, ser.', 'Third Swarm · $SWARMLER · ¡A formar, ser!');
  if ($('#meme-wall')) {
    const top = /** @type {HTMLInputElement} */ ($('#top-text'));
    const bottom = /** @type {HTMLInputElement} */ ($('#bottom-text'));
    if (!lastTop || top.value === lastTop) top.value = tr('WHEN THE GROUP CHAT', 'CUANDO EL GRUPO');
    if (!lastBottom || bottom.value === lastBottom)
      bottom.value = tr('BECOMES AN ARMY', 'SE CONVIERTE EN EJÉRCITO');
    lastTop = tr('WHEN THE GROUP CHAT', 'CUANDO EL GRUPO');
    lastBottom = tr('BECOMES AN ARMY', 'SE CONVIERTE EN EJÉRCITO');
    renderWall();
    renderCoin();
    renderFeedState();
    renderMeme();
    const menu = $('#menu-toggle');
    menu.setAttribute(
      'aria-label',
      menu.getAttribute('aria-expanded') === 'true'
        ? tr('Close menu', 'Cerrar menú')
        : tr('Open menu', 'Abrir menú'),
    );
  }
  all('[aria-description]').forEach((el) =>
    el.setAttribute(
      'aria-description',
      tr(
        'Drag this sticker, or use arrow keys. Escape resets its position.',
        'Arrastra la pegatina o usa las flechas. Escape restablece su posición.',
      ),
    ),
  );
  updateMotionLabel();
}

function updateMotionLabel() {
  const button = $('#motion-toggle');
  if (!button) return;
  button.setAttribute('aria-pressed', String(effects));
  button.setAttribute(
    'aria-label',
    effects
      ? tr('Effects on; pause effects', 'Efectos activados; pausar efectos')
      : tr('Effects off; enable effects', 'Efectos desactivados; activar efectos'),
  );
  button.title = button.getAttribute('aria-label') || '';
}
function applyMotion() {
  document.body.classList.toggle('motion-off', !effects);
  document.documentElement.style.scrollBehavior = effects ? 'smooth' : 'auto';
  updateMotionLabel();
  if (!effects) {
    document.getAnimations().forEach((animation) => animation.cancel());
    particles.length = 0;
    fxContext?.clearRect(0, 0, innerWidth, innerHeight);
    $('#roaming-tank').hidden = true;
    $('#retro-popup').hidden = true;
    endIntro();
  }
  syncHeroLoop();
}

function renderFeedState() {
  if (!$('#feed-status')) return;
  const state = $('#feed-status');
  const detail = $('#feed-detail');
  if (feedError) {
    state.textContent = lastSuccessful
      ? tr('Signal lost · stale data', 'Sin señal · datos anteriores')
      : tr('Signal unavailable', 'Señal no disponible');
    detail.textContent = lastSuccessful
      ? tr(
          'Showing the last received data. Retry now or wait for the next 30s refresh.',
          'Se muestran los últimos datos recibidos. Reintenta o espera la actualización de 30 s.',
        )
      : tr(
          'Launch data could not be loaded. Retry the signal; nothing here is a live quote.',
          'No se pudieron cargar los datos. Reintenta; ninguna cifra aquí es una cotización en directo.',
        );
    return;
  }
  if (!coin) {
    state.textContent = tr('Connecting…', 'Conectando…');
    return;
  }
  const market = coin.market && typeof coin.market === 'object' ? coin.market : {};
  const hasMarket = Object.values(market).some(
    (v) => typeof v === 'number' && Number.isFinite(v) && v >= 0,
  );
  state.textContent = hasMarket
    ? tr('Live feed · 30s', 'En directo · 30 s')
    : tr('Awaiting launch data', 'Esperando datos del lanzamiento');
  detail.textContent = hasMarket
    ? tr(
        `Last received ${new Date(lastSuccessful).toLocaleTimeString('en-US')}. Refreshes every 30s.`,
        `Última recepción: ${new Date(lastSuccessful).toLocaleTimeString('es-ES')}. Se actualiza cada 30 s.`,
      )
    : tr(
        'Numbers arrive with the launch. Refreshes every 30s.',
        'Las cifras llegarán con el lanzamiento. Actualización cada 30 s.',
      );
}

/** @param {number} value @param {string} key */
function money(value, key) {
  return new Intl.NumberFormat(lang === 'es' ? 'es-ES' : 'en-US', {
    style: 'currency',
    currency: 'USD',
    notation: key === 'priceUsd' ? 'standard' : 'compact',
    maximumFractionDigits: key === 'priceUsd' ? (value < 0.01 ? 8 : 4) : 2,
  }).format(value);
}
const numberVersions = new WeakMap();
/** @param {HTMLElement} el @param {number | null} value @param {string} key */
function showNumber(el, value, key) {
  const version = (numberVersions.get(el) || 0) + 1;
  numberVersions.set(el, version);
  if (value === null) {
    el.textContent = '—';
    delete el.dataset.value;
    return;
  }
  const previous = Number(el.dataset.value);
  const start = performance.now();
  el.dataset.value = String(value);
  if (
    !effects ||
    !Number.isFinite(previous) ||
    !el.textContent?.includes('$') ||
    previous === value
  ) {
    el.textContent = money(value, key);
    return;
  }
  function step(now) {
    if (numberVersions.get(el) !== version) return;
    const t = Math.min((now - start) / 650, 1);
    el.textContent = money(previous + (value - previous) * (1 - (1 - t) ** 3), key);
    if (t < 1) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
}

/** Apply only validated, public launch fields. Exported for reproducible browser fixtures.
 * @param {Record<string, unknown>} data */
export function applyCoinData(data) {
  coin = data;
  feedError = false;
  lastSuccessful = Date.now();
  renderCoin();
  renderFeedState();
  const url = safeHttps(data.logo);
  if (url && (url === suppliedLogo ? localLogo : url) !== logoUrl)
    void setLogo(url === suppliedLogo ? localLogo : url);
}

function renderCoin() {
  const token = validToken(coin?.token);
  $('#contract-address').textContent = token || tr('launching…', 'lanzando…');
  /** @type {HTMLButtonElement} */ ($('#copy-contract')).disabled = !token;
  $('#contract-hint').textContent = token
    ? tr(
        'Verify this address on the launch page before swapping.',
        'Comprueba esta dirección en la página del lanzamiento antes de intercambiar.',
      )
    : tr(
        "No deployed address yet. Don't copy a look-alike.",
        'Aún no existe una dirección desplegada. No copies imitaciones.',
      );
  $('#hero-status').textContent = token
    ? tr(
        'Token deployed. Verify the launch before swapping.',
        'Token desplegado. Comprueba el lanzamiento antes de intercambiar.',
      )
    : tr('Launch in progress. Follow the signal.', 'Lanzamiento en preparación. Sigue la señal.');
  for (const kind of ['coin', 'chart'])
    all(`[data-link="${kind}"]`).forEach((el) => {
      const link = /** @type {HTMLAnchorElement} */ (el);
      const url = safeHttps(coin?.[kind + 'Url']);
      link.href = url || (kind === 'coin' ? '#enlist' : '#war-room');
      if (url) {
        link.target = '_blank';
        link.rel = 'noopener noreferrer';
        link.removeAttribute('data-pending');
      } else {
        link.removeAttribute('target');
        link.removeAttribute('rel');
        link.dataset.pending = 'true';
      }
    });
  const market = /** @type {Record<string,unknown>} */ (
    coin?.market && typeof coin.market === 'object' ? coin.market : {}
  );
  all('[data-market]').forEach((el) => {
    const key = el.dataset.market || '';
    const v = market[key];
    showNumber(el, typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : null, key);
  });
  const chart = safeHttps(coin?.chartUrl);
  const embed = chart ? chartEmbed(chart) : null;
  const host = $('#chart-host');
  if (embed) {
    let iframe = host.querySelector('iframe');
    if (!iframe) {
      iframe = document.createElement('iframe');
      iframe.loading = 'lazy';
      iframe.referrerPolicy = 'no-referrer';
      iframe.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-popups');
      host.append(iframe);
    }
    if (iframe.src !== embed) iframe.src = embed;
    iframe.title = tr('SWARMLER market chart on DexScreener', 'Gráfico de SWARMLER en DexScreener');
  } else host.replaceChildren();
  $('.chart-empty').hidden = !!embed;
  $('#chart-actions').hidden = !embed;
  const x = safeHttps(coin?.x);
  const isX =
    x && ['x.com', 'www.x.com', 'twitter.com', 'www.twitter.com'].includes(new URL(x).hostname);
  const xLink = /** @type {HTMLAnchorElement} */ ($('#x-link'));
  xLink.href = isX
    ? x
    : 'https://x.com/intent/post?text=' +
      encodeURIComponent(
        tr(
          'Fall in, ser. $SWARMLER https://thirdswarm.si-md.xyz',
          '¡A formar, ser! $SWARMLER https://thirdswarm.si-md.xyz',
        ),
      );
  $('#x-link-label').textContent = isX
    ? tr('Join the swarm on X', 'Únete al enjambre en X')
    : tr('Share on X', 'Compartir en X');
}

/** @returns {Promise<void>} */
export async function refreshCoin() {
  if (refreshBusy) return;
  refreshBusy = true;
  /** @type {HTMLButtonElement} */ ($('#refresh-data')).disabled = true;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 9000);
  try {
    const response = await fetch('/simd-coin.json', {
      cache: 'no-store',
      signal: controller.signal,
      credentials: 'same-origin',
    });
    if (!response.ok) throw Error('Launch feed unavailable');
    const data = await response.json();
    if (!data || typeof data !== 'object' || Array.isArray(data) || typeof data.name !== 'string')
      throw Error('Invalid launch data');
    applyCoinData(data);
  } catch {
    feedError = true;
    renderFeedState();
  } finally {
    clearTimeout(timeout);
    refreshBusy = false;
    /** @type {HTMLButtonElement} */ ($('#refresh-data')).disabled = false;
  }
}

/** @param {string} url */
async function imageData(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 7000);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      mode: 'cors',
      credentials: 'omit',
    });
    if (!response.ok) throw Error('Image unavailable');
    const blob = await response.blob();
    if (!blob.type.startsWith('image/') || blob.size > 4 * 1024 * 1024)
      throw Error('Invalid image');
    return await new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  } finally {
    clearTimeout(timeout);
  }
}
/** @param {string} url */
async function setLogo(url) {
  const version = ++logoVersion;
  let data = '';
  fallbackArt = false;
  try {
    data = /** @type {string} */ (await imageData(url));
    await loadImage(data);
  } catch {
    fallbackArt = url !== localLogo;
    data = /** @type {string} */ (await imageData(localLogo));
  }
  if (version !== logoVersion) return;
  logoUrl = url;
  logoData = data;
  all('[data-logo]').forEach((el) => {
    const image = /** @type {HTMLImageElement} */ (el);
    image.src = url;
    image.onerror = () => {
      image.onerror = null;
      image.src = localLogo;
    };
  });
  renderArt();
  renderWall();
  await renderMeme();
}

function renderArt() {
  $('#hero-army').innerHTML = heroArmy(logoData || logoUrl);
  all('[data-scene]').forEach(
    (el) => (el.innerHTML = comicScene(Number(el.dataset.scene), logoData || logoUrl)),
  );
  $('#salute-army').innerHTML = Array.from(
    { length: 5 },
    (_, i) =>
      `<svg viewBox="0 0 265 330"><g>${soldier(logoData || logoUrl, `salute${i}`, i === 2 ? 10 : i)}</g></svg>`,
  ).join('');
}

function renderWall() {
  const wall = $('#meme-wall');
  if (!wall) return;
  wall.replaceChildren();
  recruits.forEach((r, i) => {
    const card = document.createElement('article');
    card.className = 'meme-card tilt';
    const art = document.createElement('div');
    art.className = 'meme-art';
    art.innerHTML = memeSvg(i, logoData || logoUrl, lang);
    const footer = document.createElement('div');
    footer.className = 'meme-card-footer';
    const copy = document.createElement('div');
    const id = document.createElement('p');
    id.textContent = tr('RECRUIT ', 'RECLUTA ') + String(i + 1).padStart(2, '0');
    const name = document.createElement('h3');
    name.textContent = lang === 'es' ? r.es : r.en;
    copy.append(id, name);
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = '↓';
    button.setAttribute('aria-label', tr(`Download ${r.en} as PNG`, `Descargar ${r.es} como PNG`));
    button.addEventListener('click', async () => {
      button.disabled = true;
      try {
        const blob = await renderDownload(i);
        saveBlob(blob, `SWARMLER-${i + 1}-${lang}.png`);
        toast(tr('Meme deployed. Your group chat awaits.', 'Meme listo. Tu grupo te espera.'));
      } catch {
        toast(
          tr(
            'Could not create the PNG. Try again.',
            'No se pudo crear el PNG. Inténtalo de nuevo.',
          ),
        );
      } finally {
        button.disabled = false;
      }
    });
    footer.append(copy, button);
    card.append(art, footer);
    wall.append(card);
  });
  const select = /** @type {HTMLSelectElement} */ ($('#meme-template'));
  const selected = select.value;
  select.replaceChildren();
  recruits.forEach((r, i) => {
    const option = document.createElement('option');
    option.value = String(i);
    option.textContent = lang === 'es' ? r.es : r.en;
    select.append(option);
  });
  select.value = selected || '0';
  setupTilt();
}

/** @param {string} src @returns {Promise<HTMLImageElement>} */
function loadImage(src) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = reject;
    image.src = src;
  });
}
/** @param {string} svg */
async function svgImage(svg) {
  const url = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }));
  try {
    return await loadImage(url);
  } finally {
    URL.revokeObjectURL(url);
  }
}
/** @param {HTMLCanvasElement} canvas @returns {Promise<Blob>} */
function canvasBlob(canvas) {
  return new Promise((resolve, reject) =>
    canvas.toBlob(
      (blob) => (blob ? resolve(blob) : reject(Error('Could not export PNG'))),
      'image/png',
    ),
  );
}
/** @param {Blob} blob @param {string} name */
function saveBlob(blob, name) {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = name;
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
/** @param {number} index @returns {Promise<Blob>} */
export async function renderDownload(index) {
  if (!Number.isInteger(index) || index < 0 || index >= recruits.length)
    throw Error('Unknown recruit');
  if (!logoData) logoData = /** @type {string} */ (await imageData(localLogo));
  const canvas = document.createElement('canvas');
  canvas.width = 1080;
  canvas.height = 1080;
  const ctx = canvas.getContext('2d');
  if (!ctx) throw Error('Canvas unavailable');
  ctx.drawImage(await svgImage(memeSvg(index, logoData, lang)), 0, 0, 1080, 1080);
  return canvasBlob(canvas);
}

/** @param {CanvasRenderingContext2D} ctx @param {string} text @param {number} y */
function memeText(ctx, text, y) {
  const clean = text.trim().toLocaleUpperCase(lang);
  let size = 68;
  ctx.font = `900 ${size}px Barlow, Impact, sans-serif`;
  while (ctx.measureText(clean).width > 990 && size > 29) {
    size -= 2;
    ctx.font = `900 ${size}px Barlow, Impact, sans-serif`;
  }
  // Split long unbroken input too, so 64 wide glyphs never clip.
  const lines = [];
  let line = '';
  for (const char of clean) {
    if (ctx.measureText(line + char).width > 980) {
      lines.push(line);
      line = char;
    } else line += char;
  }
  if (line) lines.push(line);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = '#f2efda';
  ctx.strokeStyle = '#11160f';
  ctx.lineWidth = 9;
  ctx.lineJoin = 'round';
  lines.slice(0, 3).forEach((l, i) => {
    const py = y + (i - (lines.length - 1) / 2) * (size + 5);
    ctx.strokeText(l, 540, py);
    ctx.fillText(l, 540, py);
  });
}

export async function renderMeme() {
  const canvas = /** @type {HTMLCanvasElement} */ ($('#meme-canvas'));
  if (!canvas || !logoData) return;
  const version = ++renderVersion;
  const index = Number(/** @type {HTMLSelectElement} */ ($('#meme-template')).value) || 0;
  const top = /** @type {HTMLInputElement} */ ($('#top-text')).value;
  const bottom = /** @type {HTMLInputElement} */ ($('#bottom-text')).value;
  const image = await svgImage(memeSvg(index, logoData, lang));
  if (version !== renderVersion) return;
  await document.fonts.ready;
  if (version !== renderVersion) return;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  ctx.drawImage(image, 0, 0, 1080, 1080);
  ctx.fillStyle = '#11160f';
  ctx.fillRect(0, 0, 1080, 220);
  ctx.fillRect(0, 865, 1080, 215);
  memeText(ctx, top, 112);
  memeText(ctx, bottom, 967);
  canvas.setAttribute(
    'aria-label',
    tr(`Meme preview: ${top}. ${bottom}.`, `Vista previa del meme: ${top}. ${bottom}.`),
  );
  if (!generatorReady) {
    generatorReady = true;
    /** @type {HTMLButtonElement} */ ($('#download-meme')).disabled = false;
  }
  $('#generator-status').textContent = fallbackArt
    ? tr(
        'The updated logo cannot be exported from this host. Downloads use the bundled frog.',
        'Este servidor no permite exportar el logo actualizado. Las descargas usan la rana incluida.',
      )
    : tr('Ready to download · 1080 × 1080 PNG', 'Listo para descargar · PNG de 1080 × 1080');
}

// One bounded particle loop, dormant while idle, off-screen or in reduced motion.
/** @type {{x:number,y:number,vx:number,vy:number,life:number,color:string,kind:number,size:number}[]} */
const particles = [];
const fx = /** @type {HTMLCanvasElement | null} */ (document.querySelector('#confetti-canvas'));
const fxContext = fx?.getContext('2d');
let fxFrame = 0;
let fxLast = 0;
function resizeFx() {
  if (!fx) return;
  const d = Math.min(devicePixelRatio || 1, 2);
  fx.width = innerWidth * d;
  fx.height = innerHeight * d;
  fxContext?.setTransform(d, 0, 0, d, 0, 0);
}
/** @param {number} x @param {number} y @param {number} [count] @param {number} [kind] */
function burst(x, y, count = 22, kind = 0) {
  if (!effects || document.hidden) return;
  for (let i = 0; i < count && particles.length < 180; i++)
    particles.push({
      x,
      y,
      vx: (Math.random() - 0.5) * 9,
      vy: -Math.random() * 7 - 2,
      life: 70 + Math.random() * 20,
      color: ['#c8f45b', '#ef786d', '#e6c66e'][i % 3],
      kind,
      size: kind ? 10 + Math.random() * 8 : 3 + Math.random() * 4,
    });
  if (!fxFrame) {
    fxLast = performance.now();
    fxFrame = requestAnimationFrame(drawFx);
  }
}
/** @param {number} now */
function drawFx(now) {
  fxFrame = 0;
  if (!fxContext || !effects || document.hidden) {
    particles.length = 0;
    return;
  }
  const delta = Math.min((now - fxLast) / 16.67, 2);
  fxLast = now;
  fxContext.clearRect(0, 0, innerWidth, innerHeight);
  for (let i = particles.length - 1; i >= 0; i--) {
    const p = particles[i];
    p.x += p.vx * delta;
    p.y += p.vy * delta;
    p.vy += 0.15 * delta;
    p.life -= delta;
    if (p.life <= 0 || p.y > innerHeight + 40) {
      particles.splice(i, 1);
      continue;
    }
    fxContext.globalAlpha = Math.min(p.life / 20, 1);
    fxContext.fillStyle = p.color;
    fxContext.save();
    fxContext.translate(p.x, p.y);
    if (p.kind === 1) {
      fxContext.beginPath();
      fxContext.ellipse(0, 0, p.size, p.size * 0.7, 0, 0, Math.PI * 2);
      fxContext.fill();
      fxContext.fillStyle = '#11160f';
      fxContext.fillRect(-p.size * 0.5, -3, 3, 4);
      fxContext.fillRect(p.size * 0.35, -3, 3, 4);
    } else if (p.kind === 2) {
      fxContext.fillRect(-p.size, 0, p.size * 2, p.size);
      fxContext.fillRect(-p.size * 0.4, -p.size * 0.5, p.size, p.size);
      fxContext.fillStyle = '#11160f';
      fxContext.fillRect(-p.size, p.size * 0.7, p.size * 2, 4);
    } else {
      fxContext.rotate(p.life * 0.1);
      fxContext.fillRect(0, 0, p.size, p.size * 0.5);
    }
    fxContext.restore();
  }
  fxContext.globalAlpha = 1;
  if (particles.length) fxFrame = requestAnimationFrame(drawFx);
}

const heroCanvas = /** @type {HTMLCanvasElement | null} */ (document.querySelector('#hero-canvas'));
const heroCtx = heroCanvas?.getContext('2d');
let heroVisible = true;
let heroFrame = 0;
let heroWidth = 0;
let heroHeight = 0;
const pointer = { x: -1000, y: -1000 };
let heroLast = 0;
const motes = Array.from({ length: 36 }, (_, i) => ({
  x: Math.random(),
  y: Math.random(),
  s: (i % 3) + 1,
}));
function sizeHero() {
  if (!heroCanvas) return;
  const rect = heroCanvas.getBoundingClientRect();
  heroWidth = rect.width;
  heroHeight = rect.height;
  const d = Math.min(devicePixelRatio || 1, 2);
  heroCanvas.width = rect.width * d;
  heroCanvas.height = rect.height * d;
  heroCtx?.setTransform(d, 0, 0, d, 0, 0);
}
function syncHeroLoop() {
  if (effects && heroVisible && !document.hidden) {
    if (!heroFrame) heroFrame = requestAnimationFrame(drawHero);
  } else {
    cancelAnimationFrame(heroFrame);
    heroFrame = 0;
    heroCtx?.clearRect(0, 0, heroWidth, heroHeight);
  }
}
/** @param {number} time */
function drawHero(time) {
  heroFrame = 0;
  if (!heroCtx || !heroVisible || !effects || document.hidden) return;
  const dt = Math.min((time - heroLast) / 1000, 0.05);
  heroLast = time;
  heroCtx.clearRect(0, 0, heroWidth, heroHeight);
  for (const m of motes) {
    m.y = (m.y - dt * 0.008 + 1) % 1;
    let x = m.x * heroWidth;
    let y = m.y * heroHeight;
    const dx = x - pointer.x,
      dy = y - pointer.y;
    const distance = Math.hypot(dx, dy);
    if (distance < 140) {
      x += dx * 0.12;
      y += dy * 0.12;
    }
    heroCtx.fillStyle = '#c8f45b';
    heroCtx.globalAlpha = 0.18;
    heroCtx.fillRect(x, y, m.s, m.s);
  }
  heroCtx.globalAlpha = 1;
  heroFrame = requestAnimationFrame(drawHero);
}

function setupTilt() {
  all('.tilt').forEach((card) => {
    if (card.dataset.tiltReady) return;
    card.dataset.tiltReady = 'true';
    card.addEventListener('pointermove', (e) => {
      if (!effects || e.pointerType !== 'mouse') return;
      const r = card.getBoundingClientRect();
      card.style.transform = `perspective(700px) rotateY(${((e.clientX - r.left - r.width / 2) / r.width) * 5}deg) rotateX(${(-(e.clientY - r.top - r.height / 2) / r.height) * 5}deg)`;
    });
    card.addEventListener('pointerleave', () => (card.style.transform = ''));
  });
}

/** @param {HTMLElement} el */
function draggable(el) {
  let x = 0,
    y = 0,
    px = 0,
    py = 0,
    active = false,
    moved = false;
  el.setAttribute(
    'aria-description',
    tr(
      'Drag this sticker, or use arrow keys. Escape resets its position.',
      'Arrastra la pegatina o usa las flechas. Escape restablece su posición.',
    ),
  );
  el.addEventListener('pointerdown', (e) => {
    if (e.button !== 0) return;
    active = true;
    moved = false;
    px = e.clientX;
    py = e.clientY;
    el.setPointerCapture(e.pointerId);
  });
  el.addEventListener('pointermove', (e) => {
    if (!active) return;
    const dx = e.clientX - px,
      dy = e.clientY - py;
    if (Math.abs(dx) + Math.abs(dy) > 2) moved = true;
    const parent = el.parentElement?.getBoundingClientRect();
    const rect = el.getBoundingClientRect();
    if (parent) {
      x += Math.max(parent.left - rect.left, Math.min(dx, parent.right - rect.right));
      y += Math.max(parent.top - rect.top, Math.min(dy, parent.bottom - rect.bottom));
    }
    px = e.clientX;
    py = e.clientY;
    el.style.transform = `translate(${x}px,${y}px)`;
  });
  el.addEventListener('pointerup', () => (active = false));
  el.addEventListener('pointercancel', () => (active = false));
  el.addEventListener('click', (e) => {
    if (moved) {
      e.stopImmediatePropagation();
      e.preventDefault();
      moved = false;
    }
  });
  el.addEventListener('keydown', (e) => {
    const moves = { ArrowLeft: [-8, 0], ArrowRight: [8, 0], ArrowUp: [0, -8], ArrowDown: [0, 8] };
    if (e.key === 'Escape') {
      x = 0;
      y = 0;
    } else if (moves[e.key]) {
      e.preventDefault();
      const r = el.getBoundingClientRect(),
        p = el.parentElement?.getBoundingClientRect();
      if (p) {
        x += Math.max(p.left - r.left, Math.min(moves[e.key][0], p.right - r.right));
        y += Math.max(p.top - r.top, Math.min(moves[e.key][1], p.bottom - r.bottom));
      }
    } else return;
    el.style.transform = `translate(${x}px,${y}px)`;
  });
}

function salute() {
  document.body.classList.remove('saluting');
  requestAnimationFrame(() => document.body.classList.add('saluting'));
  setTimeout(() => document.body.classList.remove('saluting'), 1200);
  toast(
    tr(
      'Salute received. Welcome to the swarm, ser.',
      'Saludo recibido. Bienvenido al enjambre, ser.',
    ),
  );
  burst(innerWidth / 2, innerHeight * 0.6, 65, 1);
}
let introTimer = 0;
let introFocus = null;
function endIntro() {
  const intro = $('#intro');
  if (!intro || intro.hidden) return;
  clearTimeout(introTimer);
  intro.hidden = true;
  all('[data-intro-inert]').forEach((el) => {
    el.inert = false;
    delete el.dataset.introInert;
  });
  if (document.activeElement === $('#skip-intro')) {
    /** @type {HTMLElement} */ (introFocus || $('.brand'))?.focus();
  }
  burst(innerWidth / 2, innerHeight * 0.4, 55);
}
function startIntro() {
  if (!effects) return;
  try {
    if (sessionStorage.getItem('swarm-intro')) return;
    sessionStorage.setItem('swarm-intro', 'seen');
  } catch {}
  introFocus = document.activeElement;
  $('#intro').hidden = false;
  for (const el of all('body > *')) {
    if (!['intro', 'confetti-canvas'].includes(el.id) && el.tagName !== 'SCRIPT' && !el.inert) {
      el.inert = true;
      el.dataset.introInert = 'true';
    }
  }
  $('#skip-intro').focus();
  introTimer = window.setTimeout(endIntro, 1600);
}

/** @type {AudioContext | null} */
let audioContext = null;
/** @param {string} sound */
async function playSound(sound) {
  try {
    audioContext ||= new AudioContext();
    await audioContext.resume();
    const start = audioContext.currentTime;
    const sequences = {
      honk: [164, 207],
      march: [80, 0, 80, 80, 0, 80],
      salute: [392, 523, 659],
      wagmi: [262, 330, 392, 523],
    };
    const notes = sequences[sound] || sequences.honk;
    notes.forEach((frequency, i) => {
      if (!frequency) return;
      const osc = audioContext.createOscillator(),
        gain = audioContext.createGain();
      osc.type = sound === 'march' ? 'triangle' : sound === 'honk' ? 'sawtooth' : 'square';
      osc.frequency.setValueAtTime(frequency, start + i * 0.14);
      gain.gain.setValueAtTime(0, start + i * 0.14);
      gain.gain.linearRampToValueAtTime(0.055, start + i * 0.14 + 0.015);
      gain.gain.exponentialRampToValueAtTime(0.001, start + i * 0.14 + 0.2);
      osc.connect(gain);
      gain.connect(audioContext.destination);
      osc.start(start + i * 0.14);
      osc.stop(start + i * 0.14 + 0.22);
      osc.onended = () => {
        osc.disconnect();
        gain.disconnect();
      };
    });
    $('#sound-status').textContent = tr(
      'Played locally. No audio leaves your browser.',
      'Sonido reproducido en tu navegador. No se envía audio.',
    );
  } catch {
    $('#sound-status').textContent = tr(
      'Sound is unavailable in this browser. Try another browser or check audio permissions.',
      'Este navegador no permite reproducir sonido. Prueba otro o revisa los permisos de audio.',
    );
  }
}

function init() {
  all('[data-lang]').forEach((button) =>
    button.addEventListener('click', () => setLanguage(button.dataset.lang || 'en')),
  );
  if (!$('#hero-canvas')) {
    setLanguage(lang);
    return;
  }
  setLanguage(lang);
  renderArt();
  resizeFx();
  sizeHero();
  void setLogo(localLogo).catch(() => {
    $('#generator-status').textContent = tr(
      'Artwork could not load. Reload to retry.',
      'No se pudo cargar la ilustración. Recarga para reintentar.',
    );
  });
  $('#motion-toggle').addEventListener('click', () => {
    effects = !effects && !reduced.matches;
    preference('swarm-effects', effects ? 'on' : 'off');
    applyMotion();
    toast(
      effects
        ? tr('Effects on. Maximum frog energy.', 'Efectos activados. Máxima energía de rana.')
        : tr(
            'Effects paused. The frogs are taking five.',
            'Efectos pausados. Las ranas descansan.',
          ),
    );
  });
  reduced.addEventListener('change', () => {
    effects = !reduced.matches && preference('swarm-effects') !== 'off';
    applyMotion();
  });
  const menu = $('#menu-toggle');
  function closeMenu() {
    menu.setAttribute('aria-expanded', 'false');
    menu.setAttribute('aria-label', tr('Open menu', 'Abrir menú'));
    $('#navigation').classList.remove('open');
  }
  menu.addEventListener('click', () => {
    const open = menu.getAttribute('aria-expanded') !== 'true';
    menu.setAttribute('aria-expanded', String(open));
    menu.setAttribute(
      'aria-label',
      open ? tr('Close menu', 'Cerrar menú') : tr('Open menu', 'Abrir menú'),
    );
    $('#navigation').classList.toggle('open', open);
  });
  all('#navigation a').forEach((a) => a.addEventListener('click', closeMenu));
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      if (menu.getAttribute('aria-expanded') === 'true') {
        closeMenu();
        menu.focus();
      }
      $('#retro-popup').hidden = true;
      endIntro();
    }
  });
  document.addEventListener('click', (e) => {
    if (!effects) return;
    const p = /** @type {MouseEvent} */ (e);
    burst(p.clientX || innerWidth / 2, p.clientY || innerHeight / 2, 12);
    const honk = $('#click-honk');
    honk.style.transform = `translate(${Math.min(innerWidth - 110, Math.max(10, p.clientX))}px,${Math.max(20, p.clientY - 35)}px) rotate(-12deg)`;
    honk.animate([{ opacity: 1 }, { opacity: 0, translate: '0 -20px' }], { duration: 650 });
  });
  all('.buy-button').forEach((button) =>
    button.addEventListener('click', () => {
      if (effects) {
        document.body.classList.remove('buy-flash');
        requestAnimationFrame(() => document.body.classList.add('buy-flash'));
        setTimeout(() => document.body.classList.remove('buy-flash'), 600);
        burst(innerWidth / 2, innerHeight / 2, 60);
      }
      if (button.dataset.pending)
        toast(
          tr(
            'Launch link unavailable. Check the signal below.',
            'El enlace no está disponible. Revisa la señal más abajo.',
          ),
        );
    }),
  );
  all('[data-link="chart"]').forEach((link) =>
    link.addEventListener('click', () => {
      if (link.dataset.pending)
        toast(
          tr(
            'The chart link is not available yet. Refresh the signal to try again.',
            'El enlace del gráfico aún no está disponible. Actualiza la señal para reintentar.',
          ),
        );
    }),
  );
  $('#refresh-data').addEventListener('click', () => void refreshCoin());
  $('#copy-contract').addEventListener('click', async () => {
    const address = validToken(coin?.token);
    if (!address) return;
    try {
      await navigator.clipboard.writeText(address);
      toast(
        tr(
          'Contract address copied. Verify before swapping.',
          'Dirección copiada. Compruébala antes de intercambiar.',
        ),
      );
    } catch {
      const range = document.createRange();
      range.selectNodeContents($('#contract-address'));
      const selection = getSelection();
      selection?.removeAllRanges();
      selection?.addRange(range);
      toast(
        tr(
          'Clipboard unavailable. Address selected; copy it manually.',
          'No se puede acceder al portapapeles. Dirección seleccionada; cópiala manualmente.',
        ),
      );
    }
  });
  all('.draggable').forEach(draggable);
  draggable($('#hero-logo'));
  $('#hero-logo').addEventListener('click', () => {
    logoClicks++;
    if (logoClicks % 7 === 0) {
      document.body.classList.toggle('war-mode');
      toast(
        document.body.classList.contains('war-mode')
          ? tr(
              'WAR MODE: activated. Still only confetti.',
              'MODO GUERRA: activado. Sigue siendo confeti.',
            )
          : tr('Normal frog operations resumed.', 'Las ranas vuelven a la normalidad.'),
      );
    } else
      toast(
        tr(
          `${7 - (logoClicks % 7)} more salutes. Something silly awaits.`,
          `Faltan ${7 - (logoClicks % 7)} saludos. Se viene una tontería.`,
        ),
      );
  });
  $('#pump').addEventListener('click', () => {
    pumpCount++;
    morale = Math.min(100, morale + 10);
    $('#vibe-fill').style.width = morale + '%';
    $('#vibe-value').textContent = morale + '%';
    $('#vibe-value').setAttribute(
      'aria-label',
      tr(
        `${pumpCount} clicks. Fake morale: ${morale} percent.`,
        `${pumpCount} clics. Moral de broma: ${morale} por ciento.`,
      ),
    );
    burst(innerWidth / 2, 30, 45, 1);
    toast(
      morale === 100
        ? tr('Maximum morale. Minimum brain cells.', 'Ánimo al máximo. Neuronas al mínimo.')
        : tr(
            `Honk #${pumpCount}. Morale rising. Only the fake kind.`,
            `Cuac n.º ${pumpCount}. Sube el ánimo. Solo el de broma.`,
          ),
    );
  });
  $('#salute-button').addEventListener('click', salute);
  for (const id of ['top-text', 'bottom-text', 'meme-template'])
    $('#' + id).addEventListener(
      id === 'meme-template' ? 'change' : 'input',
      () =>
        void renderMeme().catch(() =>
          toast(
            tr(
              'Preview failed. Try another template.',
              'La vista previa falló. Prueba otra plantilla.',
            ),
          ),
        ),
    );
  $('#download-meme').addEventListener('click', async () => {
    const button = /** @type {HTMLButtonElement} */ ($('#download-meme'));
    button.disabled = true;
    try {
      await renderMeme();
      saveBlob(
        await canvasBlob(/** @type {HTMLCanvasElement} */ ($('#meme-canvas'))),
        'SWARMLER-my-meme.png',
      );
      toast(tr('Your meme is ready. March on.', 'Tu meme está listo. Sigue la marcha.'));
    } catch {
      toast(
        tr(
          'Could not export the meme. Reload and try again.',
          'No se pudo exportar el meme. Recarga y reintenta.',
        ),
      );
    } finally {
      button.disabled = false;
    }
  });
  all('[data-sound]').forEach((button) =>
    button.addEventListener('click', () => void playSound(button.dataset.sound || 'honk')),
  );
  for (const id of ['close-popup', 'dismiss-popup'])
    $('#' + id).addEventListener('click', () => ($('#retro-popup').hidden = true));
  let popupCount = 0;
  const popupObserver = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        if (e.isIntersecting && effects && popupCount < 2) {
          $('#popup-copy').textContent =
            popupCount === 0
              ? tr('Warning: army incoming.', 'Aviso: se acerca el enjambre.')
              : tr(
                  'Error: too bullish. Please touch grass.',
                  'Error: demasiado entusiasmo. Sal a tomar el aire.',
                );
          $('#retro-popup').hidden = false;
          popupCount++;
          popupObserver.unobserve(e.target);
        }
      }
    },
    { threshold: 0.6 },
  );
  popupObserver.observe($('#lore'));
  popupObserver.observe($('#soundboard'));
  const heroObserver = new IntersectionObserver((entries) => {
    heroVisible = entries[0].isIntersecting;
    syncHeroLoop();
  });
  heroObserver.observe($('#home'));
  document.addEventListener('visibilitychange', () => {
    syncHeroLoop();
    if (document.hidden) {
      particles.length = 0;
      fxContext?.clearRect(0, 0, innerWidth, innerHeight);
    } else if (Date.now() - lastSuccessful > 30000) void refreshCoin();
  });
  let lastTrail = 0;
  document.addEventListener('pointermove', (e) => {
    const rect = heroCanvas?.getBoundingClientRect();
    if (rect) {
      pointer.x = e.clientX - rect.left;
      pointer.y = e.clientY - rect.top;
    }
    if (!effects || e.pointerType !== 'mouse' || !matchMedia('(pointer:fine)').matches) return;
    const cursor = $('#tank-cursor');
    cursor.style.display = 'block';
    cursor.style.transform = `translate(${Math.min(innerWidth - 30, e.clientX + 13)}px,${Math.min(innerHeight - 30, e.clientY + 17)}px)`;
    if (performance.now() - lastTrail > 160) {
      burst(e.clientX, e.clientY, 1, 1);
      lastTrail = performance.now();
    }
  });
  document.documentElement.addEventListener(
    'pointerleave',
    () => ($('#tank-cursor').style.display = 'none'),
  );
  const scenes = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        const target = /** @type {HTMLElement} */ (entry.target);
        if (effects) {
          target.animate(
            [
              { opacity: 0.4, transform: 'translateY(24px)' },
              { opacity: 1, transform: 'translateY(0)' },
            ],
            { duration: 650, easing: 'cubic-bezier(.2,0,0,1)' },
          );
          if (target.classList.contains('donut-wrap')) {
            $('.donut-segment').animate([{ strokeDashoffset: '526' }, { strokeDashoffset: '0' }], {
              duration: 1300,
              easing: 'cubic-bezier(.2,0,0,1)',
            });
          }
        }
        scenes.unobserve(target);
      }
    },
    { threshold: 0.16 },
  );
  all('.section-heading,.crate,.donut-wrap').forEach((el) => scenes.observe(el));
  let scrollFrame = 0;
  window.addEventListener(
    'scroll',
    () => {
      if (scrollFrame || !effects || !heroVisible) return;
      scrollFrame = requestAnimationFrame(() => {
        scrollFrame = 0;
        $('.art-backtype').style.translate = `0 ${Math.min(scrollY * 0.14, 70)}px`;
        $('.ring-two').style.translate = `0 ${Math.min(scrollY * 0.06, 30)}px`;
      });
    },
    { passive: true },
  );
  window.addEventListener('resize', () => {
    resizeFx();
    sizeHero();
    if (innerWidth > 850) closeMenu();
  });
  let typed = '';
  let sequence = [];
  const konami = [
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
  ];
  document.addEventListener('keydown', (e) => {
    if (
      ['INPUT', 'SELECT', 'TEXTAREA'].includes(/** @type {HTMLElement} */ (e.target).tagName) ||
      e.ctrlKey ||
      e.metaKey ||
      e.altKey
    )
      return;
    typed = (typed + e.key.toLowerCase()).slice(-6);
    if (typed === 'salute') salute();
    sequence.push(e.key.length === 1 ? e.key.toLowerCase() : e.key);
    sequence = sequence.slice(-10);
    if (sequence.join(',') === konami.join(',')) {
      burst(innerWidth / 2, 20, 90, 2);
      toast(tr('Secret convoy unlocked. HONK HONK.', 'Convoy secreto desbloqueado. CUAC CUAC.'));
    }
  });
  $('#roaming-tank').addEventListener('click', () => {
    const r = $('#roaming-tank').getBoundingClientRect();
    burst(r.x + 30, r.y + 20, 40, 1);
    $('#roaming-tank').hidden = true;
    toast(tr('Tank popped. Contents: 100% memes.', 'Tanque abierto. Contenido: 100% memes.'));
  });
  let tankX = 0,
    tankY = 180,
    tankVx = 1,
    tankVy = 0.6,
    tankFrame = 0,
    tankLast = 0;
  function moveTank(now) {
    tankFrame = 0;
    const el = $('#roaming-tank');
    if (el.hidden || !effects || document.hidden) return;
    const dt = Math.min((now - tankLast) / 16.67, 2);
    tankLast = now;
    tankX += tankVx * dt;
    tankY += tankVy * dt;
    if (tankX < 0 || tankX > innerWidth - 76) tankVx *= -1;
    if (tankY < 120 || tankY > innerHeight - 95) tankVy *= -1;
    tankX = Math.max(0, Math.min(innerWidth - 76, tankX));
    tankY = Math.max(120, Math.min(innerHeight - 95, tankY));
    el.style.transform = `translate(${tankX}px,${tankY}px)`;
    tankFrame = requestAnimationFrame(moveTank);
  }
  setInterval(() => {
    if (!effects || document.hidden || innerWidth < 620) return;
    const el = $('#roaming-tank');
    if (!el.hidden && tankFrame) return;
    tankX = Math.random() * Math.max(0, innerWidth - 80);
    tankY = 150 + Math.random() * Math.max(0, innerHeight - 270);
    el.hidden = false;
    tankLast = performance.now();
    tankFrame = requestAnimationFrame(moveTank);
    setTimeout(() => (el.hidden = true), 11000);
  }, 30000);
  $('#skip-intro').addEventListener('click', endIntro);
  applyMotion();
  startIntro();
  void refreshCoin();
  setInterval(() => {
    if (!document.hidden) void refreshCoin();
  }, 30000);
}
init();
