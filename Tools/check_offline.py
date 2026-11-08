#!/usr/bin/env python3
"""CI assertion: the keyboard extension must have no network / clipboard / shared-container APIs.

The privacy promise ("不联网、只在本机") holds only while this is true. A plain
text declaration can drift; this check fails the build on the first violation.
Everything here is read-only over the source tree -- no third-party modules.

Usage: check_offline.py <root>   (root defaults to the repo root)
Exit 0 = clean, 1 = forbidden API found.
"""
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
KEYBOARD = os.path.join(ROOT, "Keyboard")

# An allowed escape hatch is a comment on the same line, e.g. a doc line that
# merely mentions URLSession. Sources of truth are code, not comments.
FORBIDDEN = [
    (r"\bURLSession\b", "URLSession"),
    (r"\bURLRequest\b", "URLRequest"),
    (r"\bNSURLConnection\b", "NSURLConnection"),
    (r"\bURL\s*\(\s*string\s*:", "URL(string:)"),
    (r"\bUIPasteboard\b", "UIPasteboard"),
    (r"\bsuiteName\s*:", "UserDefaults(suiteName:) / App Group"),
    (r"\bUIApplication\s*\.\s*shared\b", "UIApplication.shared"),
    (r"https?://", "hard-coded http(s) URL"),
]
COMPILED = [(re.compile(p), label) for p, label in FORBIDDEN]

hits = []
for dirpath, _dirs, files in os.walk(KEYBOARD):
    if "Resources" in dirpath or "/build" in dirpath:
        continue
    for name in files:
        if not name.endswith((".swift", ".m", ".mm", ".h")):
            continue
        path = os.path.join(dirpath, name)
        for lineno, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("*"):
                continue
            for rx, label in COMPILED:
                if rx.search(line):
                    hits.append((path.replace(ROOT + "/", ""), lineno, label, stripped[:90]))

for path, lineno, label, text in hits:
    print("FAIL offline %s:%d  %s  | %s" % (path, lineno, label, text))
if hits:
    print("FAIL: %d forbidden API reference(s) in Keyboard/" % len(hits))
    sys.exit(1)
print("PASS offline: Keyboard/ has no network, clipboard or shared-container API")
