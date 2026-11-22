#!/usr/bin/env python3
"""CI static gate: enforce iOS 26/27 Custom Keyboard Extension rules proactively.

Catches recurring real-device pitfalls BEFORE they ever reach TestFlight:
  1. No empty setMarkedText("", ...) in Keyboard/ (pulls cursor to 0 in WKWebView/rich text).
  2. No view.window / superview gesture recognizer mutation (breaks host app scrolling/gestures).
  3. No NSExpression in Keyboard/ (ObjC exception crash risk on malformed input).
  4. No documentContextBeforeInput/AfterInput IPC inside viewWillDisappear or refresh().
  5. No KeyView offscreen shadow rasterization (lip.shadowOpacity > 0 without shadowPath)
     and no CABasicAnimation inside KeyView.pressed hot path.

Usage: check_ios_keyboard_rules.py [Keyboard_dir]
Exit 0 = clean, 1 = violation.
"""
import os
import re
import sys

KEYBOARD = sys.argv[1] if len(sys.argv) > 1 else "Keyboard"


def strip_comments(src: str) -> str:
    out = []
    for line in src.splitlines():
        out.append(line.split("//", 1)[0])
    return "\n".join(out)


def extract_func(code: str, signature_rx: str) -> str:
    m = re.search(signature_rx, code)
    if not m:
        return ""
    start = m.start()
    depth = 0
    in_body = False
    for i in range(start, len(code)):
        ch = code[i]
        if ch == "{":
            depth += 1
            in_body = True
        elif ch == "}":
            depth -= 1
            if in_body and depth == 0:
                return code[start : i + 1]
    return code[start:]


problems = []

for dirpath, _dirs, files in os.walk(KEYBOARD):
    if "Resources" in dirpath or "/build" in dirpath:
        continue
    for name in sorted(files):
        if not name.endswith(".swift"):
            continue
        path = os.path.join(dirpath, name)
        raw = open(path, encoding="utf-8", errors="replace").read()
        code = strip_comments(raw)

        # Rule 1: Never call setMarkedText("", ...)
        if re.search(r'setMarkedText\s*\(\s*""', code):
            problems.append(f"{path}: forbidden empty setMarkedText(\"\", ...) -- breaks WebView cursor")

        # Rule 2: Never mutate view.window gesture recognizers
        if re.search(r'view\.window\??\.gestureRecognizers', code):
            problems.append(f"{path}: forbidden view.window.gestureRecognizers mutation -- breaks host gestures")

        # Rule 3: Never use NSExpression (ObjC exception risk)
        if re.search(r'\bNSExpression\b', code):
            problems.append(f"{path}: forbidden NSExpression -- use pure-Swift parser to avoid ObjC exceptions")

        if name == "KeyboardViewController.swift":
            # Rule 4a: No documentContext IPC in viewWillDisappear
            vwd = extract_func(code, r'override\s+func\s+viewWillDisappear\b')
            if vwd and re.search(r'documentContext(Before|After)Input|contextSnapshot\s*\(', vwd):
                problems.append(f"{path}: viewWillDisappear() performs host documentContext XPC IPC")

            # Rule 4b: No per-keystroke documentContext IPC in refresh()
            ref = extract_func(code, r'private\s+func\s+refresh\b')
            if ref and re.search(r'documentContext(Before|After)Input|contextSnapshot\s*\(', ref):
                problems.append(f"{path}: refresh() performs per-keystroke documentContext XPC IPC")

            # Rule 6: No engine.trim() inside select() commit hot path (drops caches & writes disk on every word)
            sel = extract_func(code, r'private\s+func\s+select\b')
            if sel and "engine.trim()" in sel:
                problems.append(f"{path}: select() calls engine.trim() on commit hot path (causes disk write + cache re-parse storm)")

            # Rule 7: No UserDefaults reads inside reconfigure() per-keystroke hot path
            rec = extract_func(code, r'private\s+func\s+reconfigure\b')
            if rec and "KeyboardSettings.shared" in rec:
                problems.append(f"{path}: reconfigure() reads KeyboardSettings.shared on keystroke hot path (cache flags in applySettings)")

            # Rule 8: Never eagerly allocate emojiPanel inside applyAppearance()
            app = extract_func(code, r'private\s+func\s+applyAppearance\b')
            if app and re.search(r'\bemojiPanel\.', app):
                problems.append(f"{path}: applyAppearance() accesses eager emojiPanel instead of emojiPanelIfLoaded?")

            # Rule 9: setMarked(_:) must coalesce rapid .appex marked text updates (24ms frame budget) and insertCommitted/clearComposition must cancel pending updates
            sm = extract_func(code, r'private\s+func\s+setMarked\b')
            if sm and ("pendingMarkedWork" not in sm or "cancelPendingMarked" not in sm):
                problems.append(f"{path}: setMarked(_:) must coalesce rapid .appex setMarkedText updates via pendingMarkedWork/cancelPendingMarked")
            ic = extract_func(code, r'private\s+func\s+insertCommitted\b')
            if ic and "cancelPendingMarked" not in ic:
              problems.append(f"{path}: insertCommitted(_:) must call cancelPendingMarked() before host.insertText")
             cc = extract_func(code, r'private\s+func\s+clearComposition\b')
            if cc and "cancelPendingMarked" not in cc:
                problems.append(f"{path}: clearComposition() must call cancelPendingMarked() before clearing marked text")
                
        if name == "KeyboardView.swift":
            # Rule 5a: No CABasicAnimation in KeyView.pressed hot path
            kv = extract_func(code, r'final\s+class\s+KeyView\b')
            if kv:
                pressed = extract_func(kv, r'var\s+pressed\s*=\s*false')
                if pressed and "CABasicAnimation" in pressed:
                    problems.append(f"{path}: KeyView.pressed spawns CABasicAnimation on keystroke hot path")

                # Rule 5b: No lip.shadowOpacity > 0 without lip.shadowPath = UIBezierPath
                if re.search(r'lip\.shadowOpacity\s*=\s*(?!0(?:\.0+)?\b)\S', kv) and "lip.shadowPath = UIBezierPath" not in kv:
                    problems.append(f"{path}: KeyView sets lip.shadowOpacity > 0 without shadowPath (causes offscreen rasterization)")

for p in problems:
    print(f"FAIL ios-keyboard-rules: {p}")

if problems:
    print(f"FAIL: {len(problems)} iOS keyboard rule violation(s)")
    sys.exit(1)

print("PASS ios-keyboard-rules: XPC, CoreAnimation, cursor, and gesture guardrails clean")
