#!/usr/bin/env python3
"""
Re-weight the lexicon's word frequencies with the 万象 (rime-wanxiang-data / RIME-LMDG) counts: word + reading
frequencies counted over a ~48 GB modern Chinese corpus (Q&A, blogs, WeChat articles, news, reviews, encyclopaedia…),
CC BY 4.0 — https://github.com/amzxyz/rime-lmdg

Usage:
  python3 reweight_lexicon.py <lexicon.bin> <wanxiang dicts dir> -o <out.bin> [--alpha 1.0] [--miss 150]

  alpha: how much of the 万象 count replaces the current score (1 = all of it), after mapping it onto the current
         scale (a straight-line fit over the words both have).
  miss:  what a word of two or more characters the 万象 lists do not have loses (rare tencent-only words like 忒宽).
"""
import math
import os
import struct
import sys
import unicodedata

sys.path.insert(0, os.path.dirname(__file__))
from build_lexicon import write_lexicon  # noqa: E402


def read_lexicon(path):
    b = open(path, "rb").read()
    assert b[:4] == b"XHLX"
    _, nsyl, nent, nsb, ntb = struct.unpack_from("<IIIII", b, 4)
    off = 24
    syl = [b[off + 8 * i: off + 8 * i + 8].rstrip(b"\0").decode() for i in range(nsyl)]
    off += 8 * nsyl + 8 * nsyl
    recs = off
    off += 12 * nent
    blob = struct.unpack_from("<%dH" % nsb, b, off)
    off += 2 * nsb
    text = b[off: off + ntb]
    out = {}
    for i in range(nent):
        to, so, score, tl, sl = struct.unpack_from("<IIhBB", b, recs + 12 * i)
        t = text[to: to + tl].decode()
        s = tuple(syl[x] for x in blob[so: so + sl])
        out[(t, s)] = score
    return out


def plain(py):
    """ā bà → a ba; nǚ → nv; lüè → lve."""
    out = []
    for s in py.split(" "):
        s = s.replace("ü", "v").replace("ǖ", "v").replace("ǘ", "v").replace("ǚ", "v").replace("ǜ", "v")
        s = "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")
        out.append(s.lower())
    return tuple(out)


def read_counts(paths):
    counts = {}
    for p in paths:
        body = False
        for line in open(p, encoding="utf-8"):
            line = line.rstrip("\n")
            if not body:
                body = line.strip() == "..."
                continue
            parts = line.split("\t")
            if len(parts) < 3 or line.startswith("#"):
                continue
            try:
                c = int(parts[2])
            except ValueError:
                continue
            key = (parts[0], plain(parts[1]))
            counts[key] = max(counts.get(key, 0), c)
    return counts


def main():
    args = sys.argv[1:]
    lex_path, wx_dir = args[0], args[1]
    out_path = args[args.index("-o") + 1]
    alpha = float(args[args.index("--alpha") + 1]) if "--alpha" in args else 1.0
    miss = float(args[args.index("--miss") + 1]) if "--miss" in args else 150.0
    single_alpha = float(args[args.index("--single") + 1]) if "--single" in args else alpha

    scores = read_lexicon(lex_path)
    counts = read_counts([os.path.join(wx_dir, f) for f in ("zi.dict.yaml", "jichu.dict.yaml", "duoyin.dict.yaml")])

    # fit current = a·ln(count+1) + b over the words both lists have (2+ characters, ordinary scores)
    xs, ys = [], []
    for k, v in scores.items():
        if len(k[0]) >= 2 and k in counts and v > 0:
            xs.append(math.log(counts[k] + 1)); ys.append(v)
    n = len(xs); mx = sum(xs) / n; my = sum(ys) / n
    a = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sum((x - mx) ** 2 for x in xs)
    b = my - a * mx
    print(f"fit over {n} shared words: score = {a:.1f}·ln(count+1) + {b:.1f}", file=sys.stderr)

    # --rank: map a count onto the score that sits at the same rank among the shared words (keeps the current
    # spread of scores; the fit's straight line squeezes it)
    rank = "--rank" in args
    if rank:
        import bisect
        sx = sorted(xs); sy = sorted(ys)
        def mapf(c):
            x = math.log(c + 1)
            i = min(bisect.bisect_left(sx, x), len(sy) - 1)
            return sy[i]
    else:
        def mapf(c):
            return a * math.log(c + 1) + b
    out = {}
    changed = missing = 0
    for k, v in scores.items():
        if v <= -500:            # demoted words stay demoted
            out[k] = v; continue
        if k in counts:
            mapped = mapf(counts[k])
            w = single_alpha if len(k[0]) == 1 else alpha
            out[k] = int(round((1 - w) * v + w * mapped)); changed += 1
        elif len(k[0]) >= 2:
            out[k] = int(round(v - miss)); missing += 1
        else:
            out[k] = v
    print(f"re-weighted {changed}, not in 万象 {missing} (−{miss})", file=sys.stderr)
    write_lexicon(out_path, out)


if __name__ == "__main__":
    main()
