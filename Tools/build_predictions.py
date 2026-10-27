#!/usr/bin/env python3
"""
Next-word predictions (联想) from the lexicon: after a word is committed, the keyboard offers the most frequent
continuations — phrases in the lexicon that start with that word — the way Gboard pinyin does.

  python3 Tools/build_predictions.py Keyboard/Resources/lexicon.bin -o Keyboard/Resources/predictions.bin

Layout (little endian):
  magic 'XHPR' | version u32 | keyCount u32 | itemCount u32 | textLen u32
  keys:  keyCount * (textOff u32, textLen u16, firstItem u32, itemCount u16)  sorted by key UTF-8 bytes
  items: itemCount * (textOff u32, textLen u16, score i16)                    best first per key
  text:  UTF-8
"""
import struct
import sys

MAX_PER_KEY = 8
MAX_KEY_CHARS = 4
MIN_SCORE = 650          # ln(weight+1)*100: only phrases seen often enough to be worth suggesting
MIN_KEY_SCORE = 800      # and only after words common enough that a continuation is meaningful


def read_lexicon(path):
    b = open(path, "rb").read()
    _, sc, ec, sb, tl = struct.unpack_from("<IIIII", b, 4)
    eo = 24 + sc * 8 + sc * 8
    so = eo + ec * 12
    to = so + sb * 2
    out = {}
    for i in range(ec):
        t, s, score, l, L = struct.unpack_from("<IIhBB", b, eo + i * 12)
        text = b[to + t:to + t + l].decode()
        if out.get(text, -1) < score:
            out[text] = score
    return out


def main():
    src = sys.argv[1]
    dst = sys.argv[sys.argv.index("-o") + 1]
    words = read_lexicon(src)
    pred = {}
    for text, score in words.items():
        if score < MIN_SCORE or len(text) < 2:
            continue
        for k in range(1, min(len(text), MAX_KEY_CHARS + 1)):
            prefix, rest = text[:k], text[k:]
            if words.get(prefix, -1) >= MIN_KEY_SCORE:
                pred.setdefault(prefix, {})
                if pred[prefix].get(rest, -1) < score:
                    pred[prefix][rest] = score
    keys = sorted(pred, key=lambda s: s.encode())
    blob = bytearray()
    key_recs = bytearray()
    item_recs = bytearray()
    n_items = 0
    for k in keys:
        items = sorted(pred[k].items(), key=lambda kv: -kv[1])[:MAX_PER_KEY]
        kb = k.encode()
        key_recs += struct.pack("<IHIH", len(blob), len(kb), n_items, len(items))
        blob += kb
        for t, s in items:
            tb = t.encode()
            item_recs += struct.pack("<IHh", len(blob), len(tb), s)
            blob += tb
            n_items += 1
    with open(dst, "wb") as f:
        f.write(b"XHPR")
        f.write(struct.pack("<IIII", 1, len(keys), n_items, len(blob)))
        f.write(key_recs)
        f.write(item_recs)
        f.write(blob)
    print(f"keys={len(keys)} items={n_items} bytes={20 + len(key_recs) + len(item_recs) + len(blob)}")
    for probe in ["你好", "我们", "今天", "谢谢", "输入", "中国", "我"]:
        if probe in pred:
            print(probe, "→", [t for t, _ in sorted(pred[probe].items(), key=lambda kv: -kv[1])[:MAX_PER_KEY]])


if __name__ == "__main__":
    main()
