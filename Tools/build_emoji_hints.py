#!/usr/bin/env python3
"""表情联想: Chinese words → emoji, from Unicode CLDR's Chinese emoji annotations (Unicode-3.0 licence;
Tools/data/cldr/annotations_zh.xml). Writes Keyboard/Resources/emoji_hints.txt: `word<TAB>emoji emoji…`.

A word maps to an emoji when it is the emoji's short name (tts) or one of its keywords, two characters or longer;
a keyword shared by more than four emoji says too little (脸, 人) and is left out. Only emoji the keyboard's own
emoji page lists (emoji.txt) are used, so every suggestion renders on the phone."""
import re, sys, os
from collections import OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = os.path.join(ROOT, "Tools/data/cldr/annotations_zh.xml")
known = {}        # without U+FE0F → as the emoji page writes it (with it, so it draws as emoji, not text)
version = {}      # Unicode emoji version: older ones are the familiar ones, first when a word has several
for ln in open(os.path.join(ROOT, "Keyboard/Resources/emoji.txt"), encoding="utf-8"):
    parts = ln.split()
    if len(parts) >= 3:
        e = parts[2]
        known[e.replace("\ufe0f", "")] = e
        try: version[e] = float(parts[1])
        except ValueError: version[e] = 99
xml = open(src, encoding="utf-8").read()
words = OrderedDict()
def add(w, e, prio):
    w = w.strip()
    if len(w) < 2 or not re.fullmatch(r"[\u3400-\u9fff]+", w): return
    words.setdefault(w, []).append((prio, e))
for m in re.finditer(r'<annotation cp="([^"]+)"( type="tts")?>([^<]+)</annotation>', xml):
    cp, tts, text = m.group(1), m.group(2), m.group(3)
    if cp not in known: continue
    e = known[cp]
    if tts: add(text, e, 0)
    else:
        for k in text.split("|"): add(k, e, 1)
# everyday words the annotations miss or rank oddly (加油 is not a petrol pump in a chat)
CURATED = {
    "哈哈": "😂 😆", "哈哈哈": "😂 🤣", "好的": "👌 👍", "点赞": "👍", "厉害": "👍 💪", "加油": "💪 🔥",
    "爱心": "❤️ 💕", "爱你": "❤️ 😘", "么么哒": "😘", "开心": "😊 😄", "生气": "😠 😡", "无语": "😑 🙄",
    "尴尬": "😅", "害羞": "😳 ☺️", "拜拜": "👋", "再见": "👋", "晚安": "🌙 😴", "早安": "☀️", "早上好": "☀️",
    "谢谢": "🙏", "感谢": "🙏", "好吃": "😋", "好热": "🥵", "好冷": "🥶", "睡觉": "😴", "吃饭": "🍚",
    "生日快乐": "🎂 🎉", "恭喜": "🎉", "红包": "🧧", "发财": "💰", "宝宝": "👶", "猫猫": "🐱", "狗狗": "🐶",
    # Mosto himself: his name read fast is 魔头 — typing it calls up his grin and his signature kaomoji
    "魔头": "😈 ψ(｀∇´)ψ", "小魔王": "😈 ψ(｀∇´)ψ", "恶魔": "😈 👿",
    "抱抱": "🤗", "哭哭": "😭", "难过": "😢", "震惊": "😱", "思考": "🤔", "收到": "👌", "可以": "👌",
}
out = [f"{w}\t{e}" for w, e in CURATED.items()]
for w, lst in words.items():
    if w in CURATED: continue
    if sum(1 for p, _ in lst if p == 1) > 4 and not any(p == 0 for p, _ in lst): continue
    seen = []
    for p, e in sorted(lst, key=lambda x: (x[0], version.get(x[1], 99))):
        if e not in seen: seen.append(e)
    out.append(f"{w}\t{' '.join(seen[:3])}")
open(os.path.join(ROOT, "Keyboard/Resources/emoji_hints.txt"), "w", encoding="utf-8").write("\n".join(out) + "\n")
print(len(out), "words", file=sys.stderr)
