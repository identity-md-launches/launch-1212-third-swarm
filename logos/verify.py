#!/usr/bin/env python3
"""Verify the delivered PNGs offline using only the Python standard library.

Checks PNG CRCs, dimensions, opaque RGB, IDAT decompression, scanline count,
filter bytes and reviewed SHA-256 fingerprints. Also verifies the canonical copy
when artifacts/logo.png is present. Does not create or modify any files.
"""
import hashlib
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parent
HASHES = (
    "d031c31fb0f99d2d8ea89579caa9fded6f708c39cbf962a3778a0f56bdd99174",
    "ea7ffdd2c33081cfa7f37eaedf0e78bf170bf902b0c5532dabf8ff85bbaf7998",
    "b3e962b2cd026f5615f12b0085e6f5331b25b7984333913b5182ce2b2ef39077",
    "9e4f56383b26ba65118afc9fac500b94f50e8898c9e372f36ca1fe1ef835efe4",
    "463afa0d060ba13cfd0c67bc3e3bb84d38d9c21e5cb4ccf15bf58a580cf40ced",
)


def verify(path, expected_hash):
    raw = path.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == expected_hash, f"{path}: changed pixels or metadata"
    assert raw[:8] == b"\x89PNG\r\n\x1a\n", f"{path}: bad PNG signature"
    pos, kinds, compressed = 8, [], bytearray()
    while pos < len(raw):
        assert pos + 12 <= len(raw), "truncated chunk"
        length, kind = struct.unpack_from(">I4s", raw, pos)
        end = pos + 12 + length
        assert end <= len(raw), "chunk length exceeds file size"
        data = raw[pos + 8:end - 4]
        crc = struct.unpack_from(">I", raw, end - 4)[0]
        assert zlib.crc32(kind + data) & 0xFFFFFFFF == crc, f"bad {kind!r} CRC"
        if kind == b"IHDR":
            assert not kinds and length == 13, "IHDR must be first and unique"
            assert struct.unpack(">IIBBBBB", data) == (1024, 1024, 8, 2, 0, 0, 0), "expected opaque RGB 1024 square"
        elif kind == b"IDAT":
            compressed.extend(data)
        elif kind == b"IEND":
            assert length == 0 and end == len(raw), "bad IEND or trailing bytes"
        assert kind not in (b"tRNS", b"acTL"), "transparency or animation is forbidden"
        kinds.append(kind)
        pos = end
    assert kinds[0] == b"IHDR" and kinds[-1] == b"IEND" and compressed, "incomplete PNG"
    pixels = zlib.decompress(compressed)
    stride = 1024 * 3 + 1
    assert len(pixels) == 1024 * stride, "invalid decompressed raster length"
    assert all(pixels[y * stride] <= 4 for y in range(1024)), "invalid scanline filter"
    print(f"PASS {path.name}: 1024x1024 opaque RGB, {len(raw)} bytes, CRC/decompression/SHA-256 valid")


if __name__ == "__main__":
    for i, digest in enumerate(HASHES, 1):
        verify(ROOT / f"logo-{i}.png", digest)
    canonical = ROOT.parent / "artifacts" / "logo.png"
    if canonical.exists():
        verify(canonical, HASHES[1])
        assert canonical.read_bytes() == (ROOT / "logo-2.png").read_bytes()
        print("PASS artifacts/logo.png is byte-for-byte identical to the selected logo-2.png")
    else:
        print("Canonical artifacts/logo.png absent in this checkout; all five source logos checked.")
