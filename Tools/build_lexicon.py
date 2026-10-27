#!/usr/bin/env python3
"""
Build the compact binary lexicon (lexicon.bin) used by the keyboard engine.

Source data: rime-ice (雾凇拼音) cn_dicts — https://github.com/iDvel/rime-ice (GPL-3.0)
  8105.dict.yaml  通用规范汉字 8105 单字 + 字频
  base.dict.yaml  基础词库 + 词频

Usage:
  python3 build_lexicon.py <8105.dict.yaml> <base.dict.yaml> [more .dict.yaml ...] -o lexicon.bin

Binary layout (little endian):
  magic 'XHLX' | version u32 | sylCount u32 | entryCount u32 | sylBlobCount u32 | textBlobLen u32
  syllable names: sylCount * 8 bytes (ASCII, NUL padded)
  first-syllable index: sylCount * (start u32, end u32)   -> entry index range
  entries: entryCount * 12 bytes (textOff u32, sylOff u32, score i16, textLen u8, sylLen u8)
           version 2: sorted by first syllable, then second syllable (single characters first), then two-syllable
           words before longer ones, then score desc — so the words that start with a given pair of syllables are
           one contiguous run, found by binary search (no index in memory)
  syllable blob: u16[sylBlobCount]
  text blob: UTF-8 bytes
"""
import math
import struct
import sys

# ---------------------------------------------------------------- Xiaohe scheme
INITIAL_KEY = {"zh": "v", "ch": "i", "sh": "u"}
FINAL_KEY = {
    "iu": "q", "ei": "w", "e": "e", "uan": "r", "van": "r", "ue": "t", "ve": "t",
    "un": "y", "vn": "y", "u": "u", "i": "i", "o": "o", "uo": "o", "ie": "p",
    "a": "a", "ong": "s", "iong": "s", "ai": "d", "en": "f", "eng": "g",
    "ang": "h", "an": "j", "ing": "k", "uai": "k", "iang": "l", "uang": "l",
    "ou": "z", "ia": "x", "ua": "x", "ao": "c", "ui": "v", "v": "v", "in": "b",
    "iao": "n", "ian": "m",
}
ZERO_INITIAL = {"a", "ai", "an", "ang", "ao", "e", "ei", "en", "eng", "er", "o", "ou"}


def code_for(py: str):
    """Xiaohe shuangpin 2-key code for a pinyin syllable, or None if not typeable."""
    if py in ZERO_INITIAL:
        if len(py) == 1:          # a -> aa, e -> ee, o -> oo
            return py + py
        if len(py) == 2:          # ai an ao ei en er ou -> as written
            return py
        return py[0] + FINAL_KEY[py]  # ang -> ah, eng -> eg
    for ini in ("zh", "ch", "sh"):
        if py.startswith(ini):
            fin = py[2:]
            return INITIAL_KEY[ini] + FINAL_KEY[fin] if fin in FINAL_KEY else None
    ini, fin = py[0], py[1:]
    if ini not in "bpmfdtnlgkhjqxrzcsyw":
        return None
    return ini + FINAL_KEY[fin] if fin in FINAL_KEY else None


# ---------------------------------------------------------------- parsing
def read_dict(path):
    out = []
    in_body = False
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not in_body:
                if line.strip() == "...":
                    in_body = True
                continue
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 2:
                continue
            text, py = parts[0], parts[1]
            w = 0
            if len(parts) >= 3:
                try:
                    w = int(parts[2])
                except ValueError:
                    w = 0
            out.append((text, py.split(" "), w))
    return out


def main():
    args = sys.argv[1:]
    if "-o" not in args:
        print(__doc__)
        sys.exit(1)
    o = args.index("-o")
    out_path = args[o + 1]
    inputs = args[:o] + args[o + 2:]

    merged = {}
    skipped = 0
    for p in inputs:
        for text, syls, w in read_dict(p):
            if len(syls) > 8 or len(syls) == 0:
                skipped += 1
                continue
            if any(code_for(s) is None for s in syls):
                skipped += 1
                continue
            key = (text, tuple(syls))
            if merged.get(key, -1) < w:
                merged[key] = w

    syllables = sorted({s for (_, syls) in merged for s in syls})
    sid = {s: i for i, s in enumerate(syllables)}

    # sanity: every syllable must have a 2-letter code
    for s in syllables:
        c = code_for(s)
        assert c and len(c) == 2 and c.isalpha(), (s, c)

    entries = []
    for (text, syls), w in merged.items():
        score = int(round(math.log(w + 1) * 100))
        score = min(score, 32767)
        ids = [sid[s] for s in syls]
        second = ids[1] if len(ids) > 1 else -1
        entries.append((sid[syls[0]], (second, 0 if len(ids) <= 2 else 1, -score), text, ids, score))
    entries.sort(key=lambda e: (e[0], e[1]))

    syl_blob = []
    text_blob = bytearray()
    recs = bytearray()
    index = [[0, 0] for _ in syllables]
    for i, (first, _, text, ids, score) in enumerate(entries):
        if index[first][1] == 0 and (i == 0 or entries[i - 1][0] != first):
            index[first][0] = i
        index[first][1] = i + 1
        tb = text.encode("utf-8")
        if len(tb) > 255:
            continue
        recs += struct.pack("<IIhBB", len(text_blob), len(syl_blob), score, len(tb), len(ids))
        text_blob += tb
        syl_blob.extend(ids)

    with open(out_path, "wb") as f:
        f.write(b"XHLX")
        f.write(struct.pack("<IIIII", 2, len(syllables), len(entries), len(syl_blob), len(text_blob)))
        for s in syllables:
            f.write(s.encode("ascii").ljust(8, b"\0"))
        for a, b in index:
            f.write(struct.pack("<II", a, b))
        f.write(recs)
        f.write(struct.pack("<%dH" % len(syl_blob), *syl_blob))
        f.write(text_blob)

    print(f"syllables={len(syllables)} entries={len(entries)} skipped={skipped} "
          f"sylBlob={len(syl_blob)} textBlob={len(text_blob)}")
    with open(out_path + ".codes.txt", "w") as f:
        for s in syllables:
            f.write(f"{s}\t{code_for(s)}\n")


if __name__ == "__main__":
    main()
