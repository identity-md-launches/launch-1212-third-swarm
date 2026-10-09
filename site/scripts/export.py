#!/usr/bin/env python3
"""Dependency-free production export. The authored site itself requires no build."""
from pathlib import Path
import shutil
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'site'
DEST = ROOT / 'dist'
FILES = ['index.html', '404.html', 'styles.css', 'app.js', 'art.js']

def main():
    for name in FILES:
        if not (SOURCE / name).is_file():
            raise SystemExit(f'Missing required source: {name}')
    if DEST.exists():
        shutil.rmtree(DEST)
    DEST.mkdir()
    for name in FILES:
        path = SOURCE / name
        shutil.copy2(path, DEST / name)
    shutil.copytree(SOURCE / 'assets', DEST / 'assets', dirs_exist_ok=True)
    manifest = {str(p.relative_to(DEST)): {'bytes': p.stat().st_size,
                'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                for p in sorted(DEST.rglob('*')) if p.is_file()}
    (ROOT / 'test/scratch').mkdir(parents=True, exist_ok=True)
    (ROOT / 'test/scratch/site-export.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Exported static site: {len(manifest)} files, {sum(f["bytes"] for f in manifest.values())} bytes')

if __name__ == '__main__':
    main()
