#!/usr/bin/env python3
"""Build Keyboard/Resources/english.bin from Tools/data/english.txt: the English words and their letter trie, laid out flat so
the keyboard memory-maps the file and reads it in place — nothing is parsed or built when the keyboard starts.

  python3 Tools/build_english_bin.py [english.txt] [english.bin]

Layout (little endian):
  magic 'XHEN' | version u32 | wordCount u32 | nodeCount u32 | textLen u32 | pad u32
  words: wordCount * 20 bytes, sorted by key:
         keyOff u32, dispOff u32, keyLen u8, dispLen u8, pad u16, zipf f64
  nodes: nodeCount * 24 bytes, breadth first (node 0 is the root; a node's children are consecutive, sorted):
         firstChild u32, childCount u8, char u8, pad u16, word i32 (-1: no word ends here),
         bestWord i32 (the likeliest word at or below), best f64 (its ln probability)
  text:  keys and displays, UTF-8
"""
import math
import struct
import sys

src = sys.argv[1] if len(sys.argv) > 1 else "Tools/data/english.txt"
out = sys.argv[2] if len(sys.argv) > 2 else "Keyboard/Resources/english.bin"

words = []
for line in open(src, encoding="utf-8"):
    f = line.rstrip("\n").split("\t")
    if len(f) >= 3:
        words.append((f[0], float(f[1]), f[2]))
words.sort(key=lambda w: w[0])


def logp(z):
    return (z - 9) * 2.302585


# trie
children = [{}]
word_at = [-1]
for i, (key, z, disp) in enumerate(words):
    n = 0
    for c in key:
        if c not in children[n]:
            children.append({})
            word_at.append(-1)
            children[n][c] = len(children) - 1
        n = children[n][c]
    word_at[n] = i

# best word at or below each node (post-order)
best = [(-math.inf, -1)] * len(children)
order = []
stack = [0]
while stack:
    n = stack.pop()
    order.append(n)
    stack.extend(children[n].values())
for n in reversed(order):
    b = (logp(words[word_at[n]][1]), word_at[n]) if word_at[n] >= 0 else (-math.inf, -1)
    for c in children[n].values():
        if best[c][0] > b[0]:
            b = best[c]
    best[n] = b

# breadth-first renumbering so each node's children are consecutive
bfs = [0]
new_id = {0: 0}
i = 0
while i < len(bfs):
    n = bfs[i]
    for c in sorted(children[n]):
        new_id[children[n][c]] = len(bfs)
        bfs.append(children[n][c])
    i += 1

text = bytearray()
wrec = bytearray()
for key, z, disp in words:
    ko = len(text); text += key.encode()
    if disp == key:
        do, dl = ko, len(key.encode())
    else:
        do = len(text); text += disp.encode(); dl = len(disp.encode())
    wrec += struct.pack("<IIBBHd", ko, do, len(key.encode()), dl, 0, z)

nrec = bytearray()
for n in bfs:
    kids = sorted(children[n])
    first = new_id[children[n][kids[0]]] if kids else 0
    ch = 0
    nrec += struct.pack("<IBBHiid", first, len(kids), 0, 0, word_at[n], best[n][1], best[n][0] if best[n][1] >= 0 else -1e30)
# fill in each node's own character (the edge that leads to it)
nrec = bytearray(nrec)
for n in bfs:
    for c, k in children[n].items():
        nrec[new_id[k] * 24 + 5] = ord(c)

with open(out, "wb") as fo:
    fo.write(b"XHEN")
    fo.write(struct.pack("<IIIII", 1, len(words), len(bfs), len(text), 0))
    fo.write(wrec)
    fo.write(nrec)
    fo.write(text)
print(f"{len(words)} words, {len(bfs)} nodes -> {out}")
