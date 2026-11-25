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

            # Rule 14: initialEngineContext() / letter(_:tap:) must never read synchronous documentContextBeforeInput in .appex
            for fn_rx, fn_name in ((r'private\s+func\s+letter\b', 'letter(_:tap:)'),
                                   (r'private\s+func\s+initialEngineContext\b', 'initialEngineContext()')):
                fn_body = extract_func(code, fn_rx)
                if fn_body and "documentContextBeforeInput" in fn_body and "useInlineMarkedText" not in fn_body:
                    problems.append(f"{path}: {fn_name} reads documentContextBeforeInput synchronously without gating on useInlineMarkedText")

            # Rule 16: Height anti-bounce invariants in KeyboardViewController
            if "root.heightAnchor" in code:
                problems.append(f"{path}: height constraint must attach directly to view.heightAnchor, never root.heightAnchor (causes WeChat full-screen stretch)")
            uvc = extract_func(code, r'override\s+func\s+updateViewConstraints\b')
            if uvc and "allowsSelfSizing" in uvc:
                problems.append(f"{path}: updateViewConstraints() mutates allowsSelfSizing (causes extension height bounce)")
            vdl = extract_func(code, r'override\s+func\s+viewDidLoad\b')
            if vdl and re.search(r'(layoutIfNeeded|updateConstraintsIfNeeded)\s*\(', vdl):
                problems.append(f"{path}: viewDidLoad() forces synchronous layout/constraints pass")
            vda = extract_func(code, r'override\s+func\s+viewDidAppear\b')
            if vda and re.search(r'(setNeedsUpdateConstraints|layoutIfNeeded|updateConstraintsIfNeeded)\s*\(', vda):
                problems.append(f"{path}: viewDidAppear() forces post-appear height relayout/jump")
            if "preferredContentSize" in code:
                problems.append(f"{path}: preferredContentSize conflicts with view.heightAnchor self-sizing in UIInputViewController")
            vdls = extract_func(code, r'override\s+func\s+viewDidLayoutSubviews\b')
            if vdls and "setNeedsUpdateConstraints" in vdls:
                problems.append(f"{path}: viewDidLayoutSubviews() calls setNeedsUpdateConstraints() (causes layout bounce loop)")

        # Rule 17: Single calibrated fixed keyboard height (no multi-tier dynamic height regression)
        for forbidden_sym in ("KeyboardHeightPreset", "ElevationRailView"):
            if re.search(rf'\b{forbidden_sym}\b', code):
                problems.append(f"{path}: forbidden multi-tier height symbol `{forbidden_sym}` (must stay locked to single calibrated height)")

        # Rule 18: Subviews inside UIInputViewController must use pure frame layout (zero Auto Layout self-sizing pollution)
        if name in ("CandidateViews.swift", "KeyboardView.swift", "EmojiPanelView.swift", "AmbientLightView.swift"):
            for al_sym in ("NSLayoutConstraint", "UIStackView", "systemLayoutSizeFitting"):
                if re.search(rf'\b{al_sym}\b', code):
                    problems.append(f"{path}: forbidden Auto Layout `{al_sym}` inside keyboard subview (pollutes UIInputView self-sizing)")
            if re.search(r'(?:top|bottom|leading|trailing|width|height|centerX|centerY)Anchor\.constraint\b', code):
                problems.append(f"{path}: forbidden Anchor.constraint inside keyboard subview (use pure frame layout)")

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

                # Rule 19: KeyView must use feathered contact shadows (never shadowRadius = 0) and zero topHighlight line
                if re.search(r'\bshadowRadius\s*=\s*0(?:\.0+)?\b', kv):
                    problems.append(f"{path}: KeyView sets shadowRadius = 0 (creates hard 1px black sticker cutout; use Metrics.shadowBlur)")
                if "topHighlight" in kv:
                    problems.append(f"{path}: KeyView contains forbidden `topHighlight` straight white line")

        if name == "AmbientLightView.swift":
            # Rule 12: AmbientLightView must never attach a full-screen layer.mask or spawn CABasicAnimation
            if "layer.mask" in code or "CABasicAnimation" in code:
                problems.append(f"{path}: AmbientLightView must have zero layer.mask or CABasicAnimation over iOS Liquid Glass")

        if name != "KeyboardLayout.swift":
            # Rule 15: Every UIScrollView / UICollectionView in Keyboard/ must hide all 4 iOS 26 EdgeEffects via disableAllEdgeEffects()
            if re.search(r'\b(top|bottom|left|right)EdgeEffect\b', code):
                problems.append(f"{path}: partial EdgeEffect override — use disableAllEdgeEffects() to hide all 4 Liquid Glass blur curtains")
            if re.search(r'(:\s*UIScrollView\b|\bUIScrollView\s*\(|\bUICollectionView\s*\()', code) and "disableAllEdgeEffects()" not in code:
                problems.append(f"{path}: UIScrollView/UICollectionView missing disableAllEdgeEffects() call")

for p in problems:
    print(f"FAIL ios-keyboard-rules: {p}")

if problems:
    print(f"FAIL: {len(problems)} iOS keyboard rule violation(s)")
    sys.exit(1)

print("PASS ios-keyboard-rules: XPC, CoreAnimation, cursor, and gesture guardrails clean")
