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

            # Rule 8: Never eagerly allocate panels inside applyAppearance()
            app = extract_func(code, r'private\s+func\s+applyAppearance\b')
            if app and re.search(r'\b(emojiPanel|grid|settingsPanel)\.', app):
                problems.append(f"{path}: applyAppearance() accesses eager panel instead of *IfLoaded?")

            # Rule 13a: Never call engine.trim() inside viewDidDisappear() (drops warm caches between sessions)
            vdd = extract_func(code, r'override\s+func\s+viewDidDisappear\b')
            if vdd and "engine.trim()" in vdd:
                problems.append(f"{path}: viewDidDisappear() calls engine.trim() — keep warm engine caches across dismiss")

            # Rule 9: setMarked(_:) must gate host.setMarkedText behind useInlineMarkedText (0 setMarkedText XPC in .appex)
            sm = extract_func(code, r'private\s+func\s+setMarked\b')
            if sm and ("useInlineMarkedText" not in sm or "candidateBar.setPreedit" not in sm):
                problems.append(f"{path}: setMarked(_:) must gate host.setMarkedText behind useInlineMarkedText and use candidateBar.setPreedit in .appex")

        if name in ("EmojiPanelView.swift", "CandidateViews.swift"):
            # Rule 10: Any layer with shadowOpacity > 0 in EmojiPanelView/CandidateViews must configure shadowPath (no offscreen rasterization)
            if re.search(r'\.shadowOpacity\s*=\s*(?!0(?:\.0+)?\b)\S', code) and "shadowPath" not in code:
                problems.append(f"{path}: sets shadowOpacity > 0 without shadowPath (causes offscreen rasterization)")

        if name == "CandidateViews.swift":
            # Rule 11: CandidateBarView.pauseTimers() must invalidate forgetTimer (zero leaked timers on dismissal)
            pt = extract_func(code, r'func\s+pauseTimers\b')
            if pt and "forgetTimer?.invalidate()" not in pt:
                problems.append(f"{path}: pauseTimers() must invalidate forgetTimer on keyboard dismissal")

        if name == "KeyboardView.swift":
            # Rule 5a: No CABasicAnimation in KeyView.pressed hot path
            kv = extract_func(code, r'final\s+class\s+KeyView\b')
            if kv:
                pressed = extract_func(kv, r'var\s+pressed\s*=\s*false')
                if pressed and "CABasicAnimation" in pressed:
                    problems.append(f"{path}: KeyView.pressed spawns CABasicAnimation on keystroke hot path")

                # Rule 5b: No shadowOpacity > 0 without shadowPath in KeyView
                for m in re.finditer(r'\bshadowOpacity\s*=\s*([^\s;\n]+)', kv):
                    val = m.group(1)
                    if not re.match(r'^0(?:\.0+)?$', val) and "shadowPath" not in kv:
                        problems.append(f"{path}: KeyView sets shadowOpacity > 0 without shadowPath (causes offscreen rasterization)")
                        break

        if name == "AmbientLightView.swift":
            # Rule 12: AmbientLightView must never attach a full-screen layer.mask or spawn CABasicAnimation
            if "layer.mask" in code or "CABasicAnimation" in code:
                problems.append(f"{path}: AmbientLightView must have zero layer.mask or CABasicAnimation over iOS Liquid Glass")

for p in problems:
    print(f"FAIL ios-keyboard-rules: {p}")

if problems:
    print(f"FAIL: {len(problems)} iOS keyboard rule violation(s)")
    sys.exit(1)

print("PASS ios-keyboard-rules: XPC, CoreAnimation, cursor, and gesture guardrails clean")
