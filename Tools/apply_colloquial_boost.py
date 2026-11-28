#!/usr/bin/env python3
"""
Apply Tools/data/colloquial_boost.tsv directly onto an existing XHLX v3 lexicon.bin
without requiring the raw multi-GB Wanxiang source archive.
"""
import argparse
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Tools"))
from build_lexicon import write_lexicon


def load_lexicon_v3(path: str):
    with open(path, "rb") as f:
        data = f.read()
    magic, ver, syl_cnt, entry_cnt, syl_blob_cnt, text_blob_len = struct.unpack_from("<4sIIIII", data, 0)
    if magic != b"XHLX" or ver != 3:
        raise RuntimeError(f"Unsupported lexicon format: {magic} v{ver}")
    off = 24
    syls = [data[off + i * 8 : off + (i + 1) * 8].split(b"\x00", 1)[0].decode("ascii") for i in range(syl_cnt)]
    off += syl_cnt * 8
    off += syl_cnt * 8  # first-syllable index
    entries_off = off
    syl_blob_off = entries_off + entry_cnt * 12
    text_blob_off = syl_blob_off + syl_blob_cnt * 2

    scores = {}
    for idx in range(entry_cnt):
        toff, soff, score, tlen, slen = struct.unpack_from("<IIhBB", data, entries_off + idx * 12)
        sids = struct.unpack_from(f"<{slen}H", data, syl_blob_off + soff * 2)
        sy_tuple = tuple(syls[i] for i in sids)
        txt = data[text_blob_off + toff : text_blob_off + toff + tlen].decode("utf-8")
        scores[(txt, sy_tuple)] = score
    return scores, set(syls)


def load_boost_tsv(path: str):
    boosts = []
    with open(path, encoding="utf-8") as f:
        for ln in f:
            ln = ln.strip()
            if not ln or ln.startswith("#"):
                continue
            parts = ln.split("\t")
            if len(parts) < 3:
                continue
            text = parts[0].strip()
            syls = tuple(parts[1].strip().split())
            min_score = int(parts[2].strip())
            boosts.append((text, syls, min_score))
    return boosts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lexicon", default=os.path.join(ROOT, "Keyboard/Resources/lexicon.bin"))
    ap.add_argument("--boost", default=os.path.join(ROOT, "Tools/data/colloquial_boost.tsv"))
    ap.add_argument("-o", "--output", default=None, help="Output path (defaults to in-place update)")
    args = ap.parse_args()

    out_path = args.output or args.lexicon
    scores, valid_syls = load_lexicon_v3(args.lexicon)
    boosts = load_boost_tsv(args.boost)

    added, raised = 0, 0
    for text, syls, min_score in boosts:
        if any(s not in valid_syls for s in syls):
            print(f"WARN: skipping {text} ({syls}) — unknown syllable", file=sys.stderr)
            continue
        k = (text, syls)
        if k not in scores:
            scores[k] = min_score
            added += 1
        elif scores[k] < min_score:
            scores[k] = min_score
            raised += 1

    write_lexicon(out_path, scores)
    print(f"Colloquial boost applied: +{added} added, {raised} raised -> {len(scores)} total entries ({out_path})")


if __name__ == "__main__":
    main()
