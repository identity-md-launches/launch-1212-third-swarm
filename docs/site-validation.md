# Website validation and Better Interface review

Scope: the new Third Swarm static website, `site/index.html`, `site/404.html`, their scripts/assets, and the matching `dist/` export. Reviewed 2026-10-09. This is the implementer's evidence record, not an independent audit or a token/hook certification.

## Inputs and decisions

The complete JSON `brief` was fetched successfully from `https://www.si-md.xyz/api/chat?op=site-brief&label=thirdswarm` before implementation. The live `https://thirdswarm.si-md.xyz/simd-coin.json` response reported **building**, null token, null market, and no X account. Its public launch URL returned HTTP 200. The minimal launch response required for reproducible browser tests is in `site/scripts/fixtures/launch.json`; it is excluded from the production export.

The authoritative Third Swarm / SWARMLER name supersedes the preset's SARMY placeholders. The supplied logo is the default, with a face-only CSS/SVG crop to exclude its original insignia. Newly drawn soldiers have olive coats and football captain's C armbands; vehicles launch confetti. With no supplied X profile, the community link is honestly labeled **Share on X**, not an invented account. No launch address is hardcoded. Market numbers remain unavailable until supplied by the feed. The 90% pool / 10% swarm allocation and stated fees come from the assignment, not from invented live readings.

The explicit static/no-build stack wins over the generic React/Vite suggestion. There are no application package dependencies, package manifests or lockfiles to install. Existing Foundry configuration, sources, tests and required logo assets remain unchanged.

## Six-domain coverage

| Domain | Status | Checks and evidence |
| --- | --- | --- |
| Accessibility | Checked | Native anchors/buttons/fields; labels; skip link; focus treatment; intro inert-state restoration; menu keyboard/Escape; keyboard alternative to dragging; reduced-motion handling; live-region messages; automated axe scans in EN and ES. Zero automated violations. Screen-reader and physical-device sessions were not performed. |
| Layout | Checked | Rendered desktop/mobile pages; nine viewport widths in both languages; separate assertions for document overflow and text overflow; menu breakpoint; stacked lore, recruitment, generator and supply; source DOM order; relative-path hosting under `/preview/`. Native 200% browser zoom was not performed. |
| Writing | Checked | All actionable and dynamic copy has EN/ES equivalents; buttons identify their actions; missing/stale data is explicit; no invented address, X account, market values or price promises; contract copying is gated; local-only meme text is explained. Proper names and WAGMI remain branding. No professional native-speaker review is claimed. |
| Typography | Checked | Local WOFF2 files load without failed requests; three clear type roles; live values use tabular numerals; editable fields are 16px; long 64-character meme text exports; Spanish title reflow corrected. Rendered hero, cards and 404 inspected. |
| Colors | Checked | Actual CSS tokens, solid background pairs calculated below, visual inspection of the dark theme, War Mode toggling, and axe color checks. No claim that every pixel over grain/illustrations was measured. |
| UI details | Checked | Primary/secondary, hover/focus/pressed/disabled, pending/stale/error/retry, intro dismissal, downloads, sound feedback, generation status, language persistence, animation toggle, popup close handlers and external chart fallback. The browser Animations panel at 10% speed was not used. |

Not applicable: wallet connection, transactions, collection forms, authentication, theme selection outside the requested cosmetic War Mode, RTL language layouts, and backend services. These were not added.

## Findings and corrections

| Severity | Source | Evidence, correction, recheck |
| --- | --- | --- |
| Medium | `site/styles.css:382`, `.hero::before`; `site/styles.css:50`, `html` | At 320px the first render had document width 360px. A decorative hero background extended by 56px on a 16px margin. The background now stays inside its container; only decorative ticker edges are clipped at the document. The final suite reports no page or text overflow at all 18 width/language combinations. |
| Medium | `site/styles.css`, `@media (max-width:370px) .recruit-poster h2` | Spanish “NECESITA” had 245px of text in a 233px container. The narrow poster heading now uses 59px. The 320px Spanish recheck has no text overflow. |
| Low | `site/styles.css:415`, `.title-asterisk`, and its 1150px override | The rotated decorative asterisk extended the hero title's measured content by 7–8px at intermediate widths. The small-screen override now leaves 12px at its trailing edge. Rechecked at 768, 850 and 1024px in both languages. |
| Medium | `site/art.js`, `soldier()`; `site/styles.css:580`, `.logo-face img` | Initial rendered crop showed white image-background corners and multiply blending obscured the frog's eyes. Face silhouette masks now retain the supplied face and white eyes while excluding the source insignia. Desktop, mobile and meme wall images were inspected again; PNG exports still pass. |
| Low | `site/app.js:110`, `setLanguage()` | Shared initialization replaced the 404 page title with the home title. The title now branches for `.error-card` and has both language variants. The 404 renders correctly in the final browser suite. |
| Medium | `site/app.js`, `renderCoin()` and chart-link handlers; `site/index.html`, `#chart-actions` | A missing chart URL originally left an unexplained in-page link. It now gives an explicit unavailable/retry message. When embedded, the chart has a persistent full-chart link in case the provider cannot render. The URL validation, supported embed and unsupported-host fallback are exercised by fixtures. |

Source review also identified a loading-state defect in `site/app.js`, `renderMeme()`, and `site/index.html`, `#download-meme`: a click before artwork loaded could export the untouched canvas. The download now starts disabled and becomes available only after a successful render. A test deliberately withholds the logo response, verifies the disabled/loading state, then releases it and verifies the ready control. This Medium finding is fixed.

All identified applicable findings above were corrected. No unresolved primary-flow failure was observed.

## Actual checks

The runtime export was rebuilt with `python3 site/scripts/export.py`. It copies authored runtime files, requires all five entry files to exist, exports local assets, and emits a byte/hash inventory. The site itself needs no compilation or bundling. Both source and export remain usable as static files served over HTTP.

JavaScript typechecking passed with TypeScript 5.9.3:

```sh
/tmp/thirdswarm-tools/node_modules/.bin/tsc \
  --allowJs --checkJs --noEmit --target ES2022 --module ES2022 \
  --lib ES2022,DOM site/app.js site/art.js
```

The supplied browser MCP failed on its first navigation with **Transport closed**. A permitted bounded foreground harness (`site/scripts/browser-check.mjs`) instead starts its own local HTTP server, launches headless Chromium, serves the actual `dist/` at `/preview/`, and closes server/browser in `finally`. Playwright 1.58.2, Chromium 145.0.7632.6, and axe-core 4.11.1 were used. Tools and browser binaries are outside the repository.

**24 checks passed, zero uncaught browser/console errors and zero unexpected failed requests.** Coverage:

- Skippable intro and restoration of keyboard access.
- Delayed image response: no meme download until actual artwork has rendered.
- Nine sections, twelve original cards, loaded images, valid local anchor destinations.
- Initial real launch snapshot: pending contract and unavailable numbers; correct provided Buy URL.
- 320, 360, 375, 620, 768, 850, 1024, 1440 and 1920px reflow in both EN and ES, with no document or text overflow.
- Mobile menu keyboard open/close, Escape focus return and anchor navigation.
- Spanish persistence through reload and translated dynamic controls.
- Pointer and keyboard sticker movement/reset, fake morale meter, seven-click War Mode.
- All twelve PNG exports: real PNG signature, 1080×1080 IHDR and nontrivial byte size; actual card and custom-meme browser downloads.
- Generator template changes, accents, markup-like text and 64 consecutive wide characters.
- Explicit-click synthesized sound, salute and Konami feedback.
- A clearly synthetic post-deploy fixture for market rendering, valid token copying and feed-driven links. This fixture is never shipped as `/simd-coin.json`.
- Exact-host DexScreener embed URL construction, query preservation, untrusted look-alike hostname rejection, and an alternate logo from the feed.
- Malformed values/unsafe schemes rejected, HTTP failure labeled and recovered on retry.
- The 30-second refresh timer exercised using a clock installed before application initialization; no real 30-second wait needed.
- Reduced-motion preference and 404 layout/navigation at 375 and 1440px.

Axe scans returned zero WCAG 2 A/AA and WCAG 2.1 A/AA violations on the home page in EN and ES and the Spanish 404. This automated result is not a declaration of full WCAG conformance.

Rendered evidence was generated and inspected: desktop hero at 1440px, mobile hero/full page at 375px, Spanish hero, desktop meme wall, and Spanish 404. The images and machine-readable diagnostic reports are verification scratch outputs, excluded from the source submission. The final script reproduces them under ignored `test/scratch/site-validation/` when run.

Opaque CSS color-pair ratios were calculated using the WCAG sRGB relative-luminance formula:

| Foreground / background | Ratio |
| --- | ---: |
| Paper / ink | 15.83:1 |
| Muted / ink | 9.38:1 |
| Muted / surface | 8.35:1 |
| Ink / green | 14.45:1 |
| Ink / coral | 6.62:1 |
| White focus / ink | 18.33:1 |

These are identified solid pairs, not measurements of every textured/transparent rendered pixel.

## Existing Foundry verification

`forge build --offline`, `forge test --offline`, `forge fmt`, and `forge fmt --check` passed. The suite compiled two Solidity files and ran **12 tests, zero failures, including 2,000 fuzz cases**. A second run with seed `0x7468697264737761726d` also passed. The command requested `--fuzz-runs 5000`, but the unchanged accepted test's inline configuration retained 2,000 actual runs; 5,000 runs are not claimed.

All six file inputs opened by the Solidity tests are already tracked (`git ls-files --error-unmatch` passed). An export of the existing Git index into a clean temporary directory compiled and passed all 12 tests plus formatting without caches or network. The new website does not change Foundry inputs. The assignment prohibits touching `.git/`, so no staging or commit was attempted; the network worker must include the new site/export/docs in its submission. This was an indexed-tree check of the preserved Foundry work, not a claim that the website files were committed by this seat.

The inherited tests verify the accepted logo package only. They do not test a token, pool or hook. No contract/manifest implementation or blockchain deployment is part of this bounded website assignment.

## Packaging audit

The final runtime export contains 13 files totaling **302,464 bytes**, all byte-identical to their corresponding source files. The candidate submission's raw file payload is approximately **6.65 MiB**, including the preserved logo package, below the 8 MiB cap even before Git deduplication/compression. Dependencies, browser binaries, generated previews and diagnostic reports are outside the candidate file list. `git diff --check` passed. Protected configuration/dependencies, `.gitignore`, existing contracts/tests and all accepted logo bytes are unchanged. The artifact PNG opened by the inherited Solidity suite remains tracked.

## Limitations and completion

**Complete for the stated website scope**, with these explicit verification limits: no physical device, screen-reader session, Safari/Firefox run, native browser zoom or formal 60fps benchmark. Live DexScreener contents were not available for this prelaunch token; the iframe integration was validated with a controlled response. No real token address or market quote was available from the launch feed. Provider availability and actual launch deployment remain external dependencies. Native-speaker editorial review was not performed.

The production site adds no analytics, wallet connection or collection form. The requested third-party chart loads only when the feed supplies a supported URL. Publication is performed by the network from the finished export.
