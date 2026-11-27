#!/usr/bin/env python3
"""Build Tools/data/english.txt (the source of Keyboard/Resources/english.bin: Tools/build_english_bin.py)
— the English words offered while typing in Chinese mode (中英混输).

Sources (100% permissive / CC-BY-4.0, zero copyleft):
  1. SymSpell frequency_dictionary_en_82_765.txt (MIT — intersecting Google Books Ngram CC-BY-3.0 & SCOWL)
  2. amzxyz/rime-wanxiang-data en.dict.yaml (CC-BY-4.0) — modern tech/brand CamelCase forms & recent words
Each line: word <TAB> zipf frequency <TAB> how it is written (iOS, iPhone, OK, Wi-Fi ... ; plain words stay lowercase).

  python3 Tools/build_english.py [--symspell /tmp/symspell_en_82k.txt] [--wanxiang-en /tmp/wanxiang-dicts/en.dict.yaml]
"""
import argparse
import math
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DEFAULT = os.path.join(ROOT, "Tools", "data", "english.txt")

# How these are written in Chinese chat; typed as lowercase letters, offered in their usual form.
CASED = {
    "ok": "OK", "ios": "iOS", "ipados": "iPadOS", "macos": "macOS", "iphone": "iPhone", "ipad": "iPad", "imac": "iMac",
    "macbook": "MacBook", "airpods": "AirPods", "icloud": "iCloud", "itunes": "iTunes", "facetime": "FaceTime",
    "mac": "Mac", "apple": "Apple", "app": "App", "appstore": "App Store", "testflight": "TestFlight", "siri": "Siri",
    "wifi": "Wi-Fi", "usb": "USB", "pdf": "PDF", "ppt": "PPT", "ui": "UI", "ux": "UX", "api": "API", "id": "ID",
    "ai": "AI", "cpu": "CPU", "gpu": "GPU", "pc": "PC", "tv": "TV", "vr": "VR", "ar": "AR", "gps": "GPS", "sms": "SMS",
    "url": "URL", "html": "HTML", "css": "CSS", "json": "JSON", "sql": "SQL", "ip": "IP", "vpn": "VPN", "ceo": "CEO",
    "hr": "HR", "kpi": "KPI", "diy": "DIY", "faq": "FAQ", "nba": "NBA", "dj": "DJ", "mv": "MV", "kol": "KOL",
    "bug": "bug", "github": "GitHub", "google": "Google", "gmail": "Gmail", "youtube": "YouTube", "chatgpt": "ChatGPT",
    "openai": "OpenAI", "claude": "Claude", "anthropic": "Anthropic", "amazon": "Amazon", "microsoft": "Microsoft",
    "windows": "Windows", "android": "Android", "linux": "Linux", "excel": "Excel", "word": "Word", "iphones": "iPhones",
    "wechat": "WeChat", "tiktok": "TikTok", "instagram": "Instagram", "facebook": "Facebook", "twitter": "Twitter",
    "netflix": "Netflix", "tesla": "Tesla", "nike": "Nike", "ikea": "IKEA", "bmw": "BMW", "dna": "DNA",
    "covid": "COVID", "emoji": "emoji", "logo": "logo", "mosto": "Mosto", "gboard": "Gboard", "ins": "ins",
    "hi": "hi", "hello": "hello", "bye": "bye", "yes": "yes", "no": "no", "sorry": "sorry", "thx": "thx",
    "lol": "lol", "omg": "OMG", "wow": "wow", "vip": "VIP", "app store": "App Store", "pro": "Pro", "max": "Max",
    "plus": "Plus", "mini": "mini", "watch": "Watch", "i": "I",
}
# Kept even if rare in historical book corpora, since they come up in Chinese chat.
EXTRA = ["testflight", "chatgpt", "openai", "anthropic", "gboard", "mosto", "ipados", "airpods", "kol", "thx", "wechat", "tiktok"]


def main():
    ap = argparse.ArgumentParser(description="Build Tools/data/english.txt from SymSpell + Wanxiang en.dict.yaml")
    ap.add_argument("--symspell", default="/tmp/symspell_en_82k.txt", help="SymSpell frequency_dictionary_en_82_765.txt path")
    ap.add_argument("--wanxiang-en", default="/tmp/wanxiang-dicts/en.dict.yaml", help="Wanxiang en.dict.yaml path")
    ap.add_argument("--out", default=OUT_DEFAULT, help="Output TSV path")
    args = ap.parse_args()

    sym = {}
    with open(args.symspell, encoding="utf-8-sig") as f:
        for ln in f:
            p = ln.strip().split()
            if len(p) >= 2 and re.fullmatch(r"[a-z]{2,15}", p[0]):
                sym[p[0]] = int(p[1])
    tot_sym = sum(sym.values()) * 1.35
    words = {}
    for w, c in sorted(sym.items(), key=lambda kv: -kv[1])[:39000]:
        words[w] = max(2.0, min(7.8, math.log10(c / tot_sym * 1e9)))

    en_wx = {}
    en_wx_cased = {}
    body = False
    with open(args.wanxiang_en, encoding="utf-8") as f:
        for ln in f:
            ln = ln.rstrip("\n")
            if not body:
                body = ln.strip() == "..."
                continue
            p = ln.split("\t")
            if len(p) < 3:
                continue
            w = p[0]
            lw = w.lower()
            if not re.fullmatch(r"[a-z]{2,15}", lw):
                continue
            try:
                cnt = int(p[2])
            except ValueError:
                continue
            en_wx[lw] = en_wx.get(lw, 0) + cnt
            if any(c.isupper() for c in w[1:]) and any(c.islower() for c in w):
                en_wx_cased[lw] = w

    tot_wx = sum(en_wx.values()) * 1.35
    wx_zipf = {lw: max(2.5, min(6.2, math.log10(c / tot_wx * 1e9))) for lw, c in en_wx.items() if c > 0}

    for lw, c in en_wx.items():
        if lw not in words:
            if lw in en_wx_cased:
                words[lw] = max(3.5, wx_zipf[lw])
            elif c >= 50 and len(lw) >= 3:
                words[lw] = max(2.5, wx_zipf[lw])

    for w in list(CASED) + EXTRA:
        if re.fullmatch(r"[a-z]{2,15}", w):
            words[w] = max(words.get(w, 0.0), wx_zipf.get(w, 0.0), 4.0)

    disp = dict(en_wx_cased)
    disp.update(CASED)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        for w in sorted(words):
            f.write(f"{w}\t{words[w]:.2f}\t{disp.get(w, w)}\n")
    print(f"{len(words)} words -> {os.path.relpath(args.out)}")


if __name__ == "__main__":
    main()
