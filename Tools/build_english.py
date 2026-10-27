#!/usr/bin/env python3
"""Build Keyboard/Resources/english.txt — the English words offered while typing in Chinese mode (中英混输).

Source: wordfreq (https://github.com/rspeer/wordfreq; data CC BY-SA 4.0), the most frequent English words.
Each line: word <TAB> zipf frequency <TAB> how it is written (iOS, iPhone, OK, Wi-Fi … ; plain words stay lowercase).

  pip install wordfreq==3.1.1
  python3 Tools/build_english.py
"""
import os
import re

from wordfreq import top_n_list, zipf_frequency

N = 40000
OUT = os.path.join(os.path.dirname(__file__), "..", "Keyboard", "Resources", "english.txt")

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
# Kept even if rare in the corpus, since they come up in Chinese chat.
EXTRA = ["testflight", "chatgpt", "openai", "anthropic", "gboard", "mosto", "ipados", "airpods", "kol", "thx", "wechat", "tiktok"]


def main():
    words = {}
    for w in top_n_list("en", N):
        if re.fullmatch(r"[a-z]{2,15}", w):
            words[w] = zipf_frequency(w, "en")
    for w in list(CASED) + EXTRA:
        if re.fullmatch(r"[a-z]{2,15}", w):
            words.setdefault(w, max(zipf_frequency(w, "en"), 3.0))
    with open(OUT, "w", encoding="utf-8") as f:
        for w in sorted(words):
            f.write(f"{w}\t{words[w]:.2f}\t{CASED.get(w, w)}\n")
    print(f"{len(words)} words -> {os.path.relpath(OUT)}")


if __name__ == "__main__":
    main()
