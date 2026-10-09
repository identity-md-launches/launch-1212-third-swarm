// Original code-native illustrations. The supplied logo is cropped to its face;
// uniforms and confetti vehicles are drawn here without real-world insignia.
/** @param {string} value */
export function xml(value) {
  return value.replace(
    /[&<>"']/g,
    (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[c] || c,
  );
}

export const recruits = [
  {
    en: 'The General',
    es: 'El general',
    top: ['TRUST ME, SER', 'CONFÍA EN MÍ, SER'],
    bottom: ['I READ HALF THE BRIEF', 'LEÍ MEDIO INFORME'],
    tone: 0,
  },
  {
    en: 'Tank Commander',
    es: 'Comandante',
    top: ['FULL SPEED AHEAD', 'A TODA MÁQUINA'],
    bottom: ['WE HAVE NO MAP', 'NO TENEMOS MAPA'],
    tone: 1,
  },
  {
    en: 'Drill Sergeant',
    es: 'El sargento',
    top: ['DROP AND GIVE ME', 'AL SUELO Y DAME'],
    bottom: ['TWENTY GOOD MEMES', 'VEINTE BUENOS MEMES'],
    tone: 2,
  },
  {
    en: 'The Rookie',
    es: 'El novato',
    top: ['FIRST DAY HERE', 'MI PRIMER DÍA'],
    bottom: ['ALREADY A GENERAL', 'YA SOY GENERAL'],
    tone: 3,
  },
  {
    en: 'The Cook',
    es: 'El cocinero',
    top: ['LET HIM COOK', 'DÉJALO COCINAR'],
    bottom: ['IT IS JUST MORE MEMES', 'SOLO SON MÁS MEMES'],
    tone: 4,
  },
  {
    en: 'The Bugler',
    es: 'El corneta',
    top: ['IMPORTANT ANNOUNCEMENT', 'COMUNICADO IMPORTANTE'],
    bottom: ['HONK', 'CUAC'],
    tone: 5,
  },
  {
    en: 'The Scout',
    es: 'El explorador',
    top: ['SCANNING THE HORIZON', 'MIRANDO AL HORIZONTE'],
    bottom: ['FOUND ANOTHER FROG', 'OTRA RANA MÁS'],
    tone: 0,
  },
  {
    en: 'The Mechanic',
    es: 'El mecánico',
    top: ['ENGINE STATUS', 'ESTADO DEL MOTOR'],
    bottom: ['POWERED BY VIBES', 'FUNCIONA CON GANAS'],
    tone: 1,
  },
  {
    en: 'The Night Shift',
    es: 'Turno de noche',
    top: ['ONE LAST MEME', 'UN ÚLTIMO MEME'],
    bottom: ['IT IS 4 AM', 'SON LAS 4 AM'],
    tone: 2,
  },
  {
    en: 'The Strategist',
    es: 'El estratega',
    top: ['THE PLAN IS SIMPLE', 'EL PLAN ES SENCILLO'],
    bottom: ['THERE IS NO PLAN', 'NO HAY PLAN'],
    tone: 3,
  },
  {
    en: 'The Captain',
    es: 'El capitán',
    top: ['HOLD THE LINE', 'MANTÉN LA LÍNEA'],
    bottom: ['I AM GETTING SNACKS', 'VOY A POR ALGO DE COMER'],
    tone: 4,
  },
  {
    en: 'The Whole Squad',
    es: 'El pelotón',
    top: ['TOGETHER WE HAVE', 'ENTRE TODOS TENEMOS'],
    bottom: ['ONE BRAIN CELL', 'UNA SOLA NEURONA'],
    tone: 5,
  },
];

/** @param {string} logo @param {string} id @param {number} [pose] @param {boolean} [face] */
export function soldier(logo, id, pose = 0, face = true) {
  const cap = pose === 4 ? '#f2efda' : '#637a46';
  return `<g stroke="#11160f" stroke-width="5" stroke-linejoin="round">
    <path fill="#11160f" d="M88 272h39v54H75q-5-18 13-23zM158 272h37l13 33q20 9 13 22h-62z"/>
    <path fill="#64784a" d="M79 132q50-26 106 0l30 149-73 10-12-42-10 42-61-7z"/>
    <path fill="#425633" d="m107 132 22 109 27-109 30 19-25 19 17 19-33 61-38-59 10-19-28-16z"/>
    <path fill="#687c4a" d="M79 136q-19-2-31 20L29 229q3 14 20 15l34-70M179 136q19-2 28 19l30 65q4 23-13 27l-42-66"/>
    <path fill="#ef786d" d="m49 159 30 9-10 30-31-8z"/><text x="58" y="188" fill="#fff" stroke="none" font-family="Arial,sans-serif" font-size="23" font-weight="bold" text-anchor="middle" transform="rotate(16 58 188)">C</text>
    <path fill="#809d5e" d="M32 218q17-1 18 14 0 17-15 18-18-9-3-32M217 218q16-9 23 7 10 17-3 23-15 8-20-30"/>
    <path stroke="#11160f" d="m78 224 106 1"/><rect x="120" y="216" width="20" height="16" fill="#e6c66e" stroke-width="3"/>
    <path d="M83 246h27m43 0h30" stroke="#3b4b2e" stroke-width="3"/>
    ${face ? `<defs><clipPath id="face-${xml(id)}"><path transform="translate(30 19) scale(.79)" d="M132 8 105 12 91 16 82 20 73 24 69 28 65 32 62 36 59 40 57 44 54 48 51 52 48 56 46 60 45 64 43 68 35 72 31 76 29 80 27 84 26 88 24 92 24 96 23 100 22 104 21 108 21 112 21 116 21 120 21 124 21 128 22 132 22 136 23 140 24 144 24 148 25 152 26 156 28 160 31 164 33 168 36 172 41 176 205 176 212 172 215 168 217 164 220 160 232 156 233 152 234 148 236 144 236 140 233 136 231 132 229 128 227 124 222 120 222 116 225 112 226 108 225 104 234 100 235 96 236 92 239 88 239 84 237 80 238 76 236 72 239 68 235 64 230 60 226 56 222 52 218 48 214 44 209 40 205 36 198 32 191 28 185 24 178 20 171 16 161 12 146 8Z"/></clipPath></defs><ellipse cx="133" cy="87" rx="101" ry="67" fill="#647b48"/><image href="${xml(logo)}" x="30" y="19" width="207" height="203" clip-path="url(#face-${xml(id)})"/><path fill="none" d="M44 115q-7 37 80 40 68 3 91-29"/><path fill="${cap}" d="M48 45 55 16q70-32 147 1l17 26z"/><path fill="#35472b" d="M50 41q81-10 172 3l-1 12q-69 12-170-1z"/><text x="139" y="36" fill="#e6c66e" stroke="none" font-family="Arial,sans-serif" font-size="26" text-anchor="middle">✳</text>` : ''}
    ${pose === 4 ? '<path fill="#f2efda" d="M103 144h64l15 99H85z"/><path fill="#e6c66e" d="m226 208 13-52h12l-7 58"/>' : ''}
    ${pose === 6 ? '<g fill="#11160f"><circle cx="119" cy="94" r="18"/><circle cx="162" cy="94" r="18"/><path d="M118 81h46v26h-46z"/></g>' : ''}
    ${pose === 8 ? '<path fill="#11160f" d="M79 79h60v31H79zm66 0h64v31h-64z"/><path d="M132 88h21"/>' : ''}
    ${pose === 10 ? '<path fill="#809d5e" d="m213 193-37-81 40-43 13 8-27 43 36 62z"/>' : ''}
  </g>`;
}

/** @param {string} [color] */
export function tank(color = '#a5c854') {
  return `<g stroke="#11160f" stroke-width="6" stroke-linejoin="round"><rect x="13" y="78" width="246" height="66" rx="32" fill="#344329"/><path d="M35 112h200" stroke="#879c57" stroke-width="36" stroke-linecap="round" stroke-dasharray="1 34"/><path fill="${color}" d="m42 40 161-7 46 56H18z"/><path fill="#728d43" d="m82 42 10-32h86l23 32z"/><path fill="#e6c66e" d="m152 11 12-26 28 18-21 19z"/><path stroke="#ef786d" d="m191-21 12-10m-24 5-2-14m33 29 16 1"/><path stroke="#c8f45b" d="m207-39 2-9m22 26 9-5"/><rect x="66" y="57" width="73" height="16" rx="6" fill="#495f30"/><path stroke="#f2efda" stroke-width="3" d="M167 60v18m-9-9h18"/></g>`;
}

/** @param {string} logo */
export function heroArmy(logo) {
  return `<svg viewBox="0 0 600 600" aria-hidden="true"><ellipse cx="309" cy="489" rx="247" ry="38" fill="#090d08" opacity=".55"/><g transform="translate(16 232) scale(.57)">${soldier(logo, 'wing-a', 0)}</g><g transform="translate(392 225) scale(.59)">${soldier(logo, 'wing-b', 10)}</g><g transform="translate(5 370) scale(.86)">${tank('#819e4b')}</g><g transform="translate(360 386) scale(.87)">${tank('#819e4b')}</g><g transform="translate(173 137) scale(1.03)">${soldier(logo, 'captain', 0, false)}</g><g fill="#ef786d"><path d="m103 202 6-13 8 5-6 13zM454 169l13 8-4 8-13-8z"/></g><g fill="#c8f45b"><path d="m47 299 9-10 7 7-9 10zM555 319l12 3-2 9-12-3z"/></g></svg>`;
}

/** @param {number} scene @param {string} logo */
export function comicScene(scene, logo) {
  const unit = (x, y, s, p = 0) =>
    `<g transform="translate(${x} ${y}) scale(${s})">${soldier(logo, `comic${scene}-${x}`, p)}</g>`;
  return `<svg viewBox="0 0 400 280" aria-hidden="true"><g fill="#c8f45b" opacity=".12"><circle cx="200" cy="147" r="113"/><path d="M0 250 400 90v190H0z"/></g>${scene === 0 ? `${unit(107, 25, 0.78)}<rect x="213" y="158" width="36" height="57" rx="5" fill="#11160f" stroke="#c8f45b" stroke-width="3"/><path d="m226 171 9 0m-9 8h9" stroke="#c8f45b"/>` : scene === 1 ? `${unit(16, 30, 0.73)}${unit(180, 24, 0.76, 10)}` : scene === 2 ? `${unit(106, 12, 0.77)}<g transform="translate(33 195) scale(1.1)">${tank()}</g>` : `${unit(80, 0, 0.99, 10)}`}</svg>`;
}

/** @param {number} index @param {string} logo @param {string} [lang] */
export function memeSvg(index, logo, lang = 'en') {
  const r = recruits[index];
  const es = lang === 'es';
  const palettes = [
    ['#c8f45b', '#647b48'],
    ['#ef786d', '#743e35'],
    ['#242e20', '#647b48'],
    ['#e6c66e', '#aa8643'],
    ['#e2dfc7', '#738050'],
    ['#9daa77', '#4f6537'],
  ];
  const [bg, detail] = palettes[r.tone];
  const rays = Array.from(
    { length: 12 },
    (_, i) =>
      `<path d="M270 280 110 -120 230 -120z" transform="rotate(${i * 30} 270 280)" fill="${detail}" opacity=".23"/>`,
  ).join('');
  const title = r.top[es ? 1 : 0];
  const caption = r.bottom[es ? 1 : 0];
  let artwork = `<g transform="translate(96 118) scale(1.25)">${soldier(logo, `meme${index}`, index)}</g>`;
  if (index === 1 || index === 7)
    artwork = `<g transform="translate(148 95) scale(.9)">${soldier(logo, `meme${index}`, index)}</g><g transform="translate(73 322) scale(1.5)">${tank()}</g>`;
  if (index === 11)
    artwork = [0, 1, 2]
      .map(
        (i) =>
          `<g transform="translate(${i * 135 - 15} ${i === 1 ? 130 : 163}) scale(.85)">${soldier(logo, `squad${i}`, i)}</g>`,
      )
      .join('');
  const decor =
    index === 2
      ? '<path d="M0 450 540 160v70L0 520z" fill="#ef786d" opacity=".65"/>'
      : index === 8
        ? '<g fill="#e6c66e"><path d="m470 129-8 15 5 8-18-5-13 11 2-17-13-11 17-2 9-15z"/><circle cx="90" cy="149" r="18"/></g>'
        : index === 9
          ? '<g fill="none" stroke="#11160f" stroke-width="4" opacity=".3"><path d="M40 160h90v60H40zm360 90h90v70h-90zM120 200l290 87"/><circle cx="390" cy="147" r="40"/></g>'
          : '';
  return `<svg xmlns="http://www.w3.org/2000/svg" width="540" height="540" viewBox="0 0 540 540" role="img" aria-label="${xml((es ? r.es : r.en) + '. ' + title + '. ' + caption)}"><defs><pattern id="dots${index}" width="10" height="10" patternUnits="userSpaceOnUse"><circle cx="2" cy="2" r="1" fill="#11160f" opacity=".2"/></pattern></defs><rect width="540" height="540" fill="${bg}"/>${rays}<rect width="540" height="540" fill="url(#dots${index})"/>${decor}${artwork}<g fill="#f2efda" stroke="#11160f" stroke-width="4"><path d="m17 24 503-5 0 75-494 13z"/><path d="m19 441 503-8-9 86-490 3z"/></g><g fill="#11160f" font-family="Impact,Arial Black,Arial,sans-serif" font-weight="900" text-anchor="middle"><text x="270" y="70" font-size="${title.length > 22 ? 23 : 29}" textLength="${title.length > 22 ? 450 : Math.min(title.length * 16, 450)}" lengthAdjust="spacingAndGlyphs">${xml(title)}</text><text x="270" y="488" font-size="${caption.length > 24 ? 22 : 29}" textLength="${Math.min(caption.length * 15, 450)}" lengthAdjust="spacingAndGlyphs">${xml(caption)}</text></g><text x="23" y="426" fill="${index === 2 ? '#f2efda' : '#11160f'}" font-family="monospace" font-size="12" font-weight="bold">$SWARMLER / UNIT ${String(index + 1).padStart(2, '0')}</text></svg>`;
}
