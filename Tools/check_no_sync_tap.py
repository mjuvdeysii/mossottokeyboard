#!/usr/bin/env python3
"""CI assertion: tapping a candidate must never synchronously wait for the engine.

build 256/258 and the "点首选没反应/要点几次" reports share one root cause:
candidateTapped -> select -> currentResult -> engine.decodeNow (queue.sync).
When the engine queue is busy the main thread blocks and iOS drops the touch,
so the tap does nothing. The fix queues the tap (pendingSelect) and executes it
from show(), when that generation's result is already on screen.

The simulator test bench cannot reproduce the race (its engine is synchronous),
so this source-level check is the regression guard. It fails if a synchronous
decode call is reintroduced on the candidate-tap path, or if the pendingSelect
mechanism is removed.

Usage: check_no_sync_tap.py <KeyboardViewController.swift>
Exit 0 = clean, 1 = violation.
"""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "Keyboard/KeyboardViewController.swift"
src = open(path, encoding="utf-8").read()

def strip_comments(text):
    """Remove // comments so explanatory prose cannot trip the checks."""
    out = []
    for line in text.split("\n"):
        # naive but adequate: these files have no // inside string literals on code lines we inspect
        out.append(line.split("//", 1)[0])
    return "\n".join(out)

code = strip_comments(src)

problems = []

# 1. The mechanism must exist.
for token in ("pendingSelect", "resultGeneration != generation"):
    if token not in src:
        problems.append("missing %r -- the queued-tap mechanism is gone" % token)

# 2. select() must read the cached result, never call currentResult()/decodeNow.
m = re.search(r"private func select\(_ index: Int.*?\n    \}", code, re.S)
if not m:
    problems.append("select(_:shown:) not found")
else:
    body = m.group(0)
    for bad in ("decodeNow", "currentResult()", "queue.sync"):
        if bad in body:
            problems.append("select() calls %r -- a tap would block on the engine queue" % bad)

# 3. show() must drain the pending tap.
s = re.search(r"private func show\(_ out:.*?\n    \}", code, re.S)
if not s or "pendingSelect" not in s.group(0):
    problems.append("show() does not execute pendingSelect -- queued taps would never commit")

# 4. candidateTapped's candidate branch must not synchronously decode.
c = re.search(r"func candidateTapped\(_ i: Int\).*?\n    \}", code, re.S)
if not c:
    problems.append("candidateTapped not found")
else:
    for bad in ("decodeNow", "queue.sync"):
        if bad in c.group(0):
            problems.append("candidateTapped calls %r" % bad)

for p in problems:
    print("FAIL no-sync-tap %s: %s" % (path, p))
if problems:
    print("FAIL: %d violation(s)" % len(problems))
    sys.exit(1)
print("PASS no-sync-tap: candidate taps never synchronously wait for the engine")
