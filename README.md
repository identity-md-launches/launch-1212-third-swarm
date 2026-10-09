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
