#!/usr/bin/env python3
"""
Prune an existing XHLX v3 lexicon.bin to reduce app bundle size while keeping 100% of single characters
and all high-frequency multi-character words (score >= min_score).

Usage:
  python3 Tools/prune_lexicon.py Keyboard/Resources/lexicon.bin --min-score 500
"""
import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_lexicon import write_lexicon


def prune(path: str, out_path: str, min_score: int) -> None:
    with open(path, "rb") as f:
        data = f.read()

    magic, ver, syl_count, entry_count, syl_blob_count, text_blob_len = struct.unpack_from("<4sIIIII", data, 0)
    assert magic == b"XHLX" and ver == 3, f"Unsupported lexicon header: {magic} v{ver}"

    off = 24
    syllables = []
    for i in range(syl_count):
        raw = data[off + i * 8 : off + (i + 1) * 8]
        syllables.append(raw.split(b"\0", 1)[0].decode("ascii"))
    off += syl_count * 8
    off += syl_count * 8  # first-syllable index

    entries_off = off
    syl_blob_off = entries_off + entry_count * 12
    text_blob_off = syl_blob_off + syl_blob_count * 2

    scores = {}
    kept_single = 0
    kept_multi = 0
    for i in range(entry_count):
        text_off, syl_off, score, text_len, syl_len = struct.unpack_from("<IIhBB", data, entries_off + i * 12)
        if syl_len == 1 or score >= min_score:
            text = data[text_blob_off + text_off : text_blob_off + text_off + text_len].decode("utf-8")
            sids = struct.unpack_from(f"<{syl_len}H", data, syl_blob_off + syl_off * 2)
            syls = tuple(syllables[s] for s in sids)
            key = (text, syls)
            if key not in scores or score > scores[key]:
                scores[key] = score
            if syl_len == 1:
                kept_single += 1
            else:
                kept_multi += 1

    tmp_out = out_path + ".tmp"
    write_lexicon(tmp_out, scores)
    os.replace(tmp_out, out_path)
    if os.path.exists(tmp_out + ".codes.txt"):
        os.replace(tmp_out + ".codes.txt", out_path + ".codes.txt")

    before_mb = len(data) / 1048576.0
    after_mb = os.path.getsize(out_path) / 1048576.0
    print(f"pruned {path}: {entry_count:,} -> {len(scores):,} entries (single={kept_single:,}, multi={kept_multi:,}), "
          f"{before_mb:.1f} MB -> {after_mb:.1f} MB")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("lexicon", help="Path to lexicon.bin")
    ap.add_argument("-o", "--output", help="Output path (default: overwrite input in place)")
    ap.add_argument("--min-score", type=int, default=500, help="Minimum score for multi-char words (default: 500)")
    args = ap.parse_args()
    prune(args.lexicon, args.output or args.lexicon, args.min_score)


if __name__ == "__main__":
    main()
