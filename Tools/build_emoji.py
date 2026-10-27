#!/usr/bin/env python3
"""Build Keyboard/Resources/emoji.txt for the 表情 page from emojibase-data (MIT, https://emojibase.dev).

    npm pack emojibase-data@16.0.3 && tar xzf emojibase-data-16.0.3.tgz
    python3 Tools/build_emoji.py package/zh/data.json

One emoji per line, in the Unicode order:  <category>\t<emoji version>\t<emoji>
Categories as the iOS emoji keyboard groups them: 0 笑脸与人物, 1 动物与自然, 2 食物与饮料, 3 活动,
4 旅行与地点, 5 物品, 6 符号, 7 旗帜. Skin-tone variants are left out (the default yellow is shown); the keyboard
hides emoji newer than the running iOS can draw, by the version column.
"""
import json, sys

# emojibase group -> iOS category (2 = components such as skin tones and hair styles: not offered on their own)
GROUPS = {0: 0, 1: 0, 3: 1, 4: 2, 6: 3, 5: 4, 7: 5, 8: 6, 9: 7}

data = json.load(open(sys.argv[1]))
rows = []
for e in data:
    g = e.get("group")
    if g not in GROUPS:
        continue
    rows.append((GROUPS[g], e["order"], e["version"], e["emoji"]))
rows.sort()
out = sys.argv[2] if len(sys.argv) > 2 else "Keyboard/Resources/emoji.txt"
with open(out, "w") as f:
    for cat, _, ver, emo in rows:
        f.write(f"{cat}\t{ver:g}\t{emo}\n")
print(len(rows), "emoji ->", out)
