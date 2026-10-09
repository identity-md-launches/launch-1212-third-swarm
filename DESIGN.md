# Third Swarm website design

## Overview

The site is a dark, loud cartoon field manual for Third Swarm ($SWARMLER). Large condensed headlines lead into a relatively quiet reading layer. Comic panels, angled stickers, confetti vehicles and the supplied frog make the page specific to the coin. The authoritative ticker is SWARMLER; SARMY in the creator's preset was treated as stale placeholder branding.

The authored site is plain HTML, CSS, SVG and JavaScript in `site/`. `dist/` is an identical static runtime export. `site/styles.css` is the visual source of truth; `site/art.js` draws the original soldiers, tanks and twelve meme compositions. The supplied logo is retained locally and displayed through face masks that exclude the original insignia. The uniforms use a red football captain's armband with a white C. Vehicles have confetti funnels, not weapons.

## Colors

All primary colors are defined in `site/styles.css :root`.

| Token | Value | Implemented role |
| --- | --- | --- |
| `--ink` | `#11160f` | Page background, dark outlines, text on bright buttons |
| `--surface` | `#1b2217` | Panels, cards and alternate sections |
| `--surface-raised` | `#242e20` | Hovered soundboard panels |
| `--paper` | `#f2efda` | Main text, comic speech bubbles, recruitment poster |
| `--muted` | `#b6bca8` | Supporting copy and metadata |
| `--green` | `#c8f45b` | Primary actions, ticker, live indicators and allocation arc |
| `--olive` | `#647b48` | Frog art, uniforms and radar structure |
| `--coral` | `#ef786d` | Stickers, top/bottom tickers, 10% allocation and morale action |
| `--gold` | `#e6c66e` | Cartoon decorations and pending-launch indicator |
| `--line` | `#49533b` | Panel boundaries and dividers, not body text |
| `--focus` | `#ffffff` | Focus ring, backed by a dark outer shadow |

War Mode changes the page/surface/border/accent tokens to `#21110f`, `#2c1916`, `#412722`, `#71524b` and `#ffbd87`; it also adds a red camouflage background. It is cosmetic. No market data changes when it is enabled. Status indicators always have accompanying text. Measured opaque color-pair ratios and the limits of that measurement are recorded in `docs/site-validation.md`.

## Typography

Three Google Fonts are bundled as WOFF2 files in `site/assets/fonts/`, with their OFL licenses. There are no font CDN requests at runtime.

| Role | Family and fallback | Size / weight / line height |
| --- | --- | --- |
| Display | Barlow Condensed (`Barlow`), Impact, Arial Narrow, sans-serif | Weight 900; hero `clamp(90px, 10.7vw, 154px)` before breakpoint adjustments; line-height .78 for its two fixed lines |
| Section headings | Same display family | `clamp(42px, 5.4vw, 76px)`, weight 900, line-height 1.02; typically 46px on phones |
| Body | DM Sans (`DM`), Arial, sans-serif | 16px base, 1.6 line height; component copy 12–16px; weights 400, 600 and 700 |
| Labels / metadata | Space Mono (`Space`), Courier New, monospace | Usually 10–12px, weight 400, .035em tracking |
| Market values | Display family | 34–62px depending on width; tabular numerals; long values wrap |
| Editable fields | Body family | 16px minimum, including phones, to avoid mobile input zoom |

Headings use balanced wrapping, paragraphs use pretty wrapping. Prose is constrained to a useful reading measure. All-caps is applied in CSS where possible; names and ticker remain unchanged between languages. The caption art uses system display fallbacks inside standalone SVG so exported PNGs do not depend on remote fonts. The custom meme canvas waits for local fonts to load.

## Layout

The spacing scale is `--s1` through `--s9`: 4, 8, 12, 16, 24, 32, 48, 64 and 96px. These serve repeated padding, gaps and margins; small optical offsets and control sizes have explicit values.

`.section-wrap` is at most 1280px wide, initially inset by 56px per side. Insets shrink to 32px at 1150px, 20px at 620px, and 16px at 370px. Text/control layouts stay inside these margins. Only decorative tickers and backgrounds extend to the viewport edge; the document clips their rotated edges. Browser checks separately assert that actual text does not overflow.

- Above 850px the sticky header has four anchor links. At 850px and below they become a button-operated menu. Escape closes it and restores focus; choosing a link closes it.
- The hero has two columns, then becomes stacked at 620px. The image always reserves its layout area. The morale console becomes a two-row layout on phones.
- Lore panels use three columns, then one at 620px. The four-column meme wall becomes three columns at 850px and two at 620px.
- Recruitment and the generator use two columns. Their artwork/preview sticks at 115px while its section scrolls, then returns to normal flow at 620px.
- Stats retain three compact columns on phones; the radar moves above them. Supply and generator content stack below 620px. Sound controls go from four to two columns.
- Extra large screens receive a 163px hero heading at 1500px. At 370px and below the Spanish poster heading reduces to 59px.

Reflow was checked at 320, 360, 375, 620, 768, 850, 1024, 1440 and 1920 CSS pixels in both languages. Native browser zoom and physical devices were not tested.

## Elevation & Depth

The comic style uses thin olive boundaries for ordinary content and thick near-black outlines for illustrations and stickers. Primary buttons cast a 4px hard shadow; hovering moves the button 2px and increases the shadow to 6px. The preview and recruitment poster have larger hard offset shadows. Halftone dots, faint grid lines, a low-opacity grain overlay and radar scanlines add texture without carrying information.

The header sits at z-index 40, the nonmodal joke notice at 50, decorative cursor at 80, confetti at 90, and intro/toast at 100. Decorations have `pointer-events: none`; the roaming tank is a real labeled button.

## Shapes

The normal control radius is `--radius: 4px`. Ordinary panels remain square. Circular radar rings, a 90/10 supply donut and the mascot face soften the otherwise rectangular structure. Stickers use intentional rotations and polygon edges. SVG masks are part of the mascot treatment; preserve the face-only crop when using the supplied reference.

## Components

- **Actions:** `.button.primary` for the main section action; `.secondary` for secondary navigation. `.dark-button` and `.outline-dark` work on the green community section. Press scale is .96. Focus is a 3px white ring with a dark separating shadow. Real navigation is an anchor; local actions are buttons.
- **Navigation and language:** header anchors match existing section IDs. `setLanguage()` in `site/app.js` translates `data-es`, accessible labels, dynamic controls and meme art, updates `html[lang]`, and stores only the language preference. EN/ES use `aria-pressed`.
- **Live feed:** `refreshCoin()` requests same-origin `/simd-coin.json` every 30 seconds while visible, with a 9-second timeout and manual retry. The status distinguishes pending, live, stale and unavailable data. Unavailable market values are em dashes, never zero guesses. Token copying is disabled until a valid nonzero address arrives. Buy and Chart destinations come from the feed. DexScreener embeds have a separate full-chart link.
- **Morale and mascot:** the meter is explicitly fictitious. Pump counts clicks and rains cartoon frogs. Stickers and the captain support pointer dragging and keyboard arrows; Escape resets their position. Seven captain clicks toggle War Mode. The community button makes the SVG army salute.
- **Meme cards:** `memeSvg()` draws twelve original compositions, using a local or updated feed logo. Each native download button exports a 1080-square PNG. Accessible descriptions include the recruit and its caption.
- **Meme generator:** a labeled native select, two labeled 64-character fields, live canvas preview and PNG download. Text is local only. Download stays disabled until artwork has rendered. Long strings are fitted/wrapped; asynchronous renders use a version guard so old renders cannot replace newer input. A cross-origin logo that cannot be exported falls back to the bundled art with an explanation.
- **Soundboard:** four labeled buttons synthesize short sounds through Web Audio only after a click. They do not use a microphone or load sound files.
- **Motion:** one bounded confetti canvas (maximum 180 particles), one 36-particle hero layer, CSS ticker/logo/radar motion, short scroll entrances and hero parallax. The hero canvas stops off-screen and on hidden tabs. Effects can be paused from the header. Reduced motion disables the intro, moving decorations, particles and transitions. The brief's cinematic effects are decorative, never required to operate the page.
- **Notices:** the toast is a polite status region. The retro joke popups explicitly identify themselves as jokes, have close buttons, never steal focus, and are suppressed when effects are off. The skippable intro temporarily makes other content inert and restores it on dismissal.
- **404:** `site/404.html` reuses the type, palette, logo, language controls and primary button. Its return link is relative.

## Do's and Don'ts

Use `.section-wrap`, the existing token scale, short coin-specific copy and actual button/link semantics when extending the page. Keep error and financial-data language literal even when surrounding copy is playful. Add an English default and Spanish equivalent together, including accessible labels. Reserve space for media and test both languages at the smallest width.

Keep the supplied logo local as a fallback and accept the feed's replacement. Preserve the C armband and nonviolent confetti vehicles. Never introduce real insignia, invented market figures, wallet connections, data-collection forms, tracking scripts, guaranteed returns or a guessed X account. The current absent X field deliberately produces a **Share on X** link.

For an additional page, create its own folder under `site/`, use relative `../assets/` and shared CSS/module URLs, provide full metadata and a route back, and extend the explicit export file list and browser checks. Do not rely on a server-side SPA rewrite.

Design guidance: Jakub Krehel's Better Interface (MIT); documentation method: Paul Bakaus's Impeccable (Apache-2.0), at the task's pinned revisions. Notices are retained in `docs/design-guide-LICENSE.txt`.
