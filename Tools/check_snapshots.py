#!/usr/bin/env python3
"""CI gate: a rendered snapshot that is blank / a flat colour is a broken view.

Why this exists: build 256 shipped an emoji panel with a gradient mask whose
colours were inverted, so the whole list was transparent. The gate (numbers)
and the render step (which only listed files) both stayed green. This check
makes a blank view fail the build.

No third-party dependencies -- decode the PNG IDAT ourselves and measure the
spread of sampled bytes. A flat/blank image has variance ~0; a real keyboard
screenshot has hundreds of distinct tones.

Usage: check_snapshots.py <min_bytes> <png> [png ...]
Exit 0 = every snapshot has content, 1 = at least one is blank.
"""
import os
import struct
import sys
import zlib


def variance(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        return None
    pos, w, h, colour, idat = 8, None, None, None, b""
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            w, h, _depth, colour = struct.unpack(">IIBB", chunk[:10])
        elif kind == b"IDAT":
            idat += chunk
        elif kind == b"IEND":
            break
    if not idat or w is None:
        return None
    try:
        raw = zlib.decompress(idat)
    except zlib.error:
        return None
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(colour, 4)
    stride = w * channels
    step = max(1, channels * 16)
    samples = []
    offset = 0
    for y in range(min(h, 240)):
        if offset + 1 + stride > len(raw):
            break
        line = raw[offset + 1:offset + 1 + stride]  # skip the filter byte
        offset += 1 + stride
        if y % 8 == 0:
            samples.extend(line[::step])
    if not samples:
        return None
    mean = sum(samples) / len(samples)
    return sum((v - mean) ** 2 for v in samples) / len(samples)


def main():
    if len(sys.argv) < 3:
        print("usage: check_snapshots.py <min_bytes> <png...>")
        sys.exit(2)
    min_bytes = int(sys.argv[1])
    files = sys.argv[2:]
    bad = []
    for path in files:
        size = os.path.getsize(path)
        var = variance(path)
        ok = size >= min_bytes and var is not None and var > 50
        print(("OK    " if ok else "BLANK ") + path
              + "  bytes=%d var=%s" % (size, "%.1f" % var if var is not None else "n/a"))
        if not ok:
            bad.append(path)
    print("snapshots with content: %d/%d" % (len(files) - len(bad), len(files)))
    if bad:
        print("FAIL: blank or unreadable snapshot(s): " + ", ".join(os.path.basename(b) for b in bad))
        sys.exit(1)


if __name__ == "__main__":
    main()
