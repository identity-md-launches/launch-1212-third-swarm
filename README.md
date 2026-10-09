# Third Swarm website ($SWARMLER)

The website is implemented in `site/` as static HTML, CSS, SVG and JavaScript. The finished production export is in `dist/`, including `index.html`, `404.html`, local fonts, the supplied logo, and a derived favicon. There is no application build step or runtime package dependency.

Nine sections cover the frog army's lore, live market feed, buying instructions, supply/fee mechanics, twelve downloadable original memes, a canvas meme generator, soundboard and community. English and Spanish are remembered locally. The signature morale console, draggable captain/stickers, confetti, saluting army and cosmetic War Mode follow the creator's brief. A visible effects control and reduced-motion support keep the site usable without animation.

## Install, preview and rebuild

No npm install is required to use or export the site. Python 3 is only needed for the optional copy/export command and a local preview server:

```sh
python3 site/scripts/export.py
python3 -m http.server 8080 --directory dist
```

Open `http://127.0.0.1:8080/`. You can also preview `site/` directly by changing the directory argument. The export copies the exact runtime source/assets and produces a SHA-256 inventory in `test/scratch/site-export.json`; it does not compile JavaScript. It fails if an entry file is missing. Test scripts and fixtures are excluded from the export.

A plain local server does not supply `/simd-coin.json`, so it deliberately shows a retryable unavailable-data state. Production's host must provide that same-origin endpoint. Do not publish the test fixture as the live feed.

## Data and interactions

`site/app.js` fetches `/simd-coin.json` immediately, every 30 seconds while the tab is visible, on return to a stale tab, and on manual refresh. It uses `coinUrl` and `chartUrl` for navigation, the optional `logo` for replacement artwork, and the three provided market fields. A missing token is shown as **launching…**; copy stays disabled. No token address is hardcoded. Failed requests are labeled; old data is explicitly stale.

Only exact `dexscreener.com` / `www.dexscreener.com` chart URLs become lazy-loaded iframes, with `embed=1&theme=dark`. Other HTTPS chart URLs remain normal links. A full-chart fallback is retained beside an embed. The current feed has no X account, so the community action is **Share on X**; a valid future `x` field becomes a join link.

Meme text stays in the browser. Downloads are real 1080×1080 PNGs. Audio is locally synthesized only after a soundboard click. Language/effects preferences are the only local-storage values; the intro uses session storage. There are no wallet connections, tracking scripts or data-collection forms.

## Validation

See [the complete review](docs/site-validation.md) for all six Better Interface domains, corrected findings, actual commands and limitations. [DESIGN.md](DESIGN.md) documents the final tokens, typography, components and responsive behavior.

Results: production export and JavaScript typecheck passed; **24 browser checks passed**, including both languages, nine viewport widths, downloads, URL/feed validation, clipboard copying and reduced motion. Automated axe scans found **zero violations** in the checked home/404 states. The existing Foundry suite passes **12 tests**, including 2,000 fuzz cases, in both the workspace and a fresh indexed-tree export. A second fuzz seed also passed. These are worker-side checks, not an independent network certification.

To reproduce the optional browser and type checks, install pinned tooling outside the repository:

```sh
npm install --prefix /tmp/thirdswarm-tools --cache /tmp/thirdswarm-npm-cache \
  --no-audit --no-fund typescript@5.9.3 playwright@1.58.2 @axe-core/playwright@4.11.1
PLAYWRIGHT_BROWSERS_PATH=/tmp/thirdswarm-browsers \
  /tmp/thirdswarm-tools/node_modules/.bin/playwright install chromium
/tmp/thirdswarm-tools/node_modules/.bin/tsc \
  --allowJs --checkJs --noEmit --target ES2022 --module ES2022 \
  --lib ES2022,DOM site/app.js site/art.js
PLAYWRIGHT_BROWSERS_PATH=/tmp/thirdswarm-browsers \
  node site/scripts/browser-check.mjs
forge build --offline
forge test --offline
forge fmt --check
```

The browser harness manages its own server/browser within one foreground process and closes both. Set `SWARM_TOOLS` to use another external tooling directory. Its minimal captured prelaunch fixture is in `site/scripts/fixtures/launch.json`; post-deploy/error cases are test fixtures only. It writes diagnostics/screenshots to ignored `test/scratch/site-validation/` for local review. Keep those generated previews/reports out of the Git submission. No runtime dependency manifests or lockfiles are needed for this static implementation; existing project configuration and dependency files were not modified.

Limitations: the live token has no address or market data yet; DexScreener contents were tested via an iframe fixture. No real-device, screen-reader, Safari/Firefox, native zoom, or formal 60fps benchmark was performed. The supplied browser MCP was unavailable, so actual rendered validation used local headless Chromium.

## Publish and packaging

Publish **the contents of `dist/`** at `https://thirdswarm.si-md.xyz`, retain relative asset URLs, configure the host to serve `404.html` for missing pages, and provide the launch's `/simd-coin.json` at the origin root. No server rewrite for an SPA is needed. Do not publish `site/scripts/`, its fixtures, or verification reports. The production metadata already uses the assigned canonical URL and supplied logo.

Source submission includes `site/`, `dist/`, this README, `DESIGN.md`, `docs/`, and the earlier accepted Foundry/logo files. Keep dependency caches and browser/tool installations outside Git. The required `artifacts/logo.png` is already tracked and must stay because the existing Solidity tests read it. No ignore-file change, manifest, wallet address, contract alteration or deployment was made. Git metadata is protected by this assignment, so the network worker performs the final staging/commit.

The interface guidance attribution and licenses are in `docs/design-guide-LICENSE.txt`; each bundled font has its license beside it. The logo is the creator-provided reference; the soldier/tank/meme compositions are original SVG code for this site.

---

The following is the preserved record of the earlier accepted logo assignment.

# Third Swarm logo package

Five 1024 × 1024 PNG logo options are delivered in [logos/](logos/README.md), in the requested mascot, minimal icon, ticker lettermark, minted emblem and illustrative meme order. [artifacts/logo.png](artifacts/logo.png) is the selected image-generated wallet logo, identical to option 2.

The image tool drew four options; the lettermark uses the authorized code-drawn SVG fallback after its image request failed. Five completed drafts were retained, with no rendered drafts discarded. The generation record, selection rationale and small-size review are in [logos/README.md](logos/README.md).

This is the **logo assignment**, not the token/hook implementation step. The Foundry project provides real offline asset checks so the required build/test execution compiles a test contract and checks the delivered files. No launch manifest or deployable smart contract is included.

```sh
forge build --offline
forge test --offline
forge fmt --check
python3 logos/verify.py
```

Solidity is pinned to 0.8.26 with Cancun, optimization and `bytecode_hash = "none"`. FFI is disabled. Filesystem permissions grant read access only to the five delivered `logos/logo-*.png` files and the delivered `artifacts/logo.png`. The tests have no external imports or dependencies and do not use the temporary `.imd/reads/` inputs. They validate PNG structure, dimensions, opacity, fingerprints, distinct options and exact equality of the selected file with option 2. The reusable structural validator lives in `src/PngAsset.sol`.

Packaging limitation: this worker's `.git/` is read-only, so `git add` and `git commit` cannot create `index.lock`. The files are present and visible in `git status`; none of the six PNG test inputs is ignored. The submitting worker must include **both `logos/*.png` and `artifacts/logo.png`**, plus `src/`, `test/` and `foundry.toml`, in its commit. The local verification also runs on a fresh copy containing only these deliverables, without `.imd/`, cached compilation output or generated-image storage.
