#!/bin/bash
# The sentence model the keyboard reads keys with: 万象语法模型 (wanxiang-lts-zh-hans.gram), built by amzxyz from a
# ~48 GB modern Chinese corpus — https://github.com/amzxyz/rime-wanxiang-data (CC BY 4.0). Too large for git
# (~400 MB): fetched here, pinned by checksum so a new upstream release never changes the keyboard unnoticed.
set -euo pipefail
OUT="${1:-Keyboard/Resources/sentence.gram}"
URL="https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram"
SHA="e34500ab44626dc039a0641792ecba98ab63307646eb3d29186be56608ffe094"
if [ -f "$OUT" ] && echo "$SHA  $OUT" | shasum -a 256 -c - >/dev/null 2>&1; then echo "sentence model present"; exit 0; fi
curl -fsSL --retry 3 -o "$OUT.part" "$URL"
echo "$SHA  $OUT.part" | shasum -a 256 -c -
mv "$OUT.part" "$OUT"
echo "sentence model fetched: $(du -h "$OUT" | cut -f1)"
