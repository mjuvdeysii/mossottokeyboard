#!/usr/bin/env python3
"""One source for the legal pages: writes the hosted pages (docs/*.html, served by GitHub Pages — the privacy policy
URL App Store Connect asks for) and the same text inside the app (App/LegalText.swift), so the two never drift.

    python3 Tools/build_legal.py
"""
import html, json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "https://github.com/mjuvdeysii/mossottokeyboard"
ISSUES = REPO + "/issues"
SITE = "https://mjuvdeysii.github.io/mossottokeyboard"
EFFECTIVE = "2026 年 10 月 28 日"

# Each document: (id, title, [(heading, [paragraph | ["bullet", ...]])])
DOCS = [
    ("privacy", "隐私政策", [
        ("适用范围", [
            "本政策适用于 Mosto键盘 App 及其中的 Mosto键盘 键盘扩展（以下合称“本应用”）。本应用的开发者以 App Store / TestFlight 上显示的开发者名称为准。",
        ]),
        ("本应用不收集任何数据", [
            "本应用不联网：键盘扩展与 App 都不发起任何网络请求。本应用不包含统计、广告、崩溃上报或任何第三方 SDK。你在键盘上输入的任何内容，开发者都无法获取。",
            "App 中“打开系统设置”与开源项目链接只会打开系统设置或 Safari，由你主动点击。",
        ]),
        ("只保存在你设备上的数据", [
            "为了让输入更准，以下内容只保存在你这台设备上本应用的存储空间内，不会被上传或分享：",
            ["学习记录：你选过的词与词组，用于把你常用的词排在前面；",
             "触点习惯：你按各个键时的位置偏差，用于按触点位置纠错；",
             "常用表情与键盘设置（输入方案、中文键盘、数字键盘、外观等）；",
             "诊断计数：被系统取消的按键数与响应时间，只在键盘设置的“诊断”中显示给你看。"],
            "如果你开启了 iOS 的设备备份（iCloud 云备份或电脑备份），这些数据可能随设备备份一起保存，由 Apple 按其政策处理。",
        ]),
        ("“允许完全访问”", [
            "iOS 为第三方键盘提供“允许完全访问”开关。本应用只用它播放按键震动与按键音；不开启也能正常打字。即使开启，本应用也不联网、不读取剪贴板、通讯录或其他 App 的数据。",
        ]),
        ("密码与安全输入框", [
            "在密码等安全输入框中，iOS 会自动换成系统键盘，第三方键盘不会出现在这些输入框里。",
        ]),
        ("删除数据", [
            ["键盘设置 › 学习 › “清空已学习的词语与触点习惯”：清除学习记录与触点习惯；",
             "删除本应用：清除本应用在设备上的全部数据。"],
        ]),
        ("儿童隐私", [
            "本应用不收集任何人的个人信息，包括儿童的个人信息。",
        ]),
        ("测试版反馈", [
            "通过 TestFlight 参与测试时，你主动提交的反馈（说明文字、截图）与测试者信息由 Apple 依 TestFlight 条款处理并提供给开发者，仅用于测试沟通与改进本应用。",
        ]),
        ("政策更新与联系", [
            "本政策如有更新，会在本页面与 App 内公布，并更新生效日期。",
            "问题与建议：" + ISSUES,
        ]),
    ]),
    ("terms", "用户协议与免责声明", [
        ("测试版", [
            "当前版本为 TestFlight 公开测试版，功能可能随时变动，可能存在错误、崩溃或本机数据（包括学习记录）丢失。",
            "候选、自动纠错与联想可能出错。发送消息、填写付款、医疗、法律等重要内容前，请自行核对上屏的文字。",
        ]),
        ("按现状提供", [
            "在适用法律允许的最大范围内，本应用按“现状”和“现有”提供，不作任何明示或默示的保证，包括但不限于适销性、特定用途适用性与不侵权的保证。",
            "对因使用或无法使用本应用而产生的任何直接或间接损失（包括因候选、自动纠错、联想造成的输入错误），开发者不承担责任。适用法律另有强制性规定的，从其规定。",
        ]),
        ("候选内容", [
            "候选词来自开源词库与语言模型，可能包含不准确或不当的词语，不代表开发者的观点。你可以在候选栏长按自己学过的词将其删除。",
        ]),
        ("知识产权", [
            "Mosto 角色形象与名称归开发者所有。本应用源代码以 GPL-3.0 许可开源：" + REPO,
            "第三方词库、语言模型与数据按各自的许可使用，详见“开源许可”。",
        ]),
        ("商标与关系声明", [
            "“小鹤双拼”为其原作者设计的双拼方案；iOS、iPhone、TestFlight、App Store 是 Apple Inc. 的商标。本应用与上述各方没有隶属、合作或背书关系。",
        ]),
        ("协议变更", [
            "本协议如有更新，会在本页面与 App 内公布。继续使用本应用即表示你接受更新后的协议。",
            "问题与建议：" + ISSUES,
        ]),
    ]),
    ("licenses", "开源许可", [
        ("本应用", [
            "Mosto键盘 — GPL-3.0。完整源代码：" + REPO,
        ]),
        ("词库与数据", [
            ["雾凇拼音 rime-ice（中文词库）— GPL-3.0 — https://github.com/iDvel/rime-ice",
             "其中的腾讯词库部分来自腾讯 AI Lab 中文词向量词表，经 rime-ice 收录；注音由 pypinyin（MIT）生成",
             "八股文 rime-octagram-data（语言模型）— LGPL-3.0 — https://github.com/lotem/rime-octagram-data",
             "wordfreq（英文词频，中英混输）— 数据 CC BY-SA 4.0 — https://github.com/rspeer/wordfreq",
             "Emojibase（表情列表与分类）— MIT — https://github.com/milesj/emojibase"],
            "各许可的完整文本见源代码仓库中的 LICENSE 与 ThirdParty 目录。",
        ]),
    ]),
]

def esc(s):
    """HTML-escape, with bare URLs turned into links."""
    out = []
    for w in s.split(" "):
        e = html.escape(w)
        if w.startswith("https://"):
            stripped = w.rstrip("，。；")
            tail = w[len(stripped):]
            e = f'<a href="{html.escape(stripped)}">{html.escape(stripped)}</a>{html.escape(tail)}'
        else:
            for sep in ("：",):
                if sep + "https://" in w:
                    a, b = w.split(sep, 1)
                    e = html.escape(a + sep) + f'<a href="{html.escape(b)}">{html.escape(b)}</a>'
        out.append(e)
    return " ".join(out)

PAGE = """<!doctype html>
<html lang="zh-Hans"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · Mosto键盘</title>
<style>
:root{{--bg:#FBF8F2;--card:#fff;--ink:#2B1961;--sub:#6A5C96;--line:#E6DEF5;--accent:#633EBF}}
@media (prefers-color-scheme:dark){{:root{{--bg:#16112F;--card:#221A45;--ink:#F4EEFF;--sub:#B4A8DC;--line:#3A2E70;--accent:#FFC45A}}}}
body{{margin:0;background:var(--bg);color:var(--ink);font:16px/1.7 -apple-system,"PingFang SC",system-ui,sans-serif}}
main{{max-width:720px;margin:0 auto;padding:28px 16px 48px}}
h1{{font-size:26px;margin:0 0 4px}} h2{{font-size:17px;margin:26px 0 6px}}
.meta{{color:var(--sub);font-size:14px;margin-bottom:18px}}
section{{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:6px 18px 12px;margin:12px 0}}
p,li{{margin:8px 0}} ul{{padding-left:20px}} a{{color:var(--accent);word-break:break-all}}
nav a{{margin-right:14px;font-size:14px}}
</style></head><body><main>
<nav><a href="index.html">Mosto键盘</a><a href="privacy.html">隐私政策</a><a href="terms.html">用户协议与免责声明</a><a href="licenses.html">开源许可</a></nav>
<h1>{title}</h1><div class="meta">生效日期：{effective}</div>
{body}
</main></body></html>
"""

def page_body(sections):
    parts = []
    for heading, items in sections:
        inner = []
        for it in items:
            if isinstance(it, list):
                inner.append("<ul>" + "".join(f"<li>{esc(x)}</li>" for x in it) + "</ul>")
            else:
                inner.append(f"<p>{esc(it)}</p>")
        parts.append(f"<section><h2>{html.escape(heading)}</h2>{''.join(inner)}</section>")
    return "\n".join(parts)

INDEX_BODY = f"""<section><h2>纯双拼与全拼的 iOS 键盘</h2>
<p>小鹤双拼 · 全拼 · 九宫格，按触点位置自动纠错，中英混输。住在键盘里的小魔王 Mosto 陪你打字。</p>
<p>键盘不联网，不收集任何数据；你学过的词和触点习惯只存在你的设备上。</p></section>
<section><h2>参加公开测试</h2><p>通过 TestFlight 公开链接加入测试；安装后在 设置 › 通用 › 键盘 › 键盘 › 添加新键盘 中选择 Mosto键盘。</p></section>
<section><h2>支持与反馈</h2><p>在 TestFlight 中截图即可提交反馈，或在这里提问：<a href="{ISSUES}">{ISSUES}</a></p></section>"""

def main():
    os.makedirs(os.path.join(ROOT, "docs"), exist_ok=True)
    for did, title, sections in DOCS:
        with open(os.path.join(ROOT, "docs", f"{did}.html"), "w") as f:
            f.write(PAGE.format(title=title, effective=EFFECTIVE, body=page_body(sections)))
    with open(os.path.join(ROOT, "docs", "index.html"), "w") as f:
        f.write(PAGE.format(title="Mosto键盘", effective=EFFECTIVE, body=INDEX_BODY))
    open(os.path.join(ROOT, "docs", ".nojekyll"), "w").close()
    # the app's copy
    def swift(s): return json.dumps(s, ensure_ascii=False)
    lines = ["// Generated by Tools/build_legal.py — edit the source there, not here.", "",
             "enum LegalText {",
             f"    static let effective = {swift(EFFECTIVE)}",
             f"    static let site = {swift(SITE)}",
             "    enum Item { case text(String), bullets([String]) }",
             "    struct Doc { let id: String; let title: String; let sections: [(String, [Item])] }",
             "    static let docs: [Doc] = ["]
    for did, title, sections in DOCS:
        lines.append(f"        Doc(id: {swift(did)}, title: {swift(title)}, sections: [")
        for heading, items in sections:
            its = ", ".join(f".bullets([{', '.join(swift(x) for x in it)}])" if isinstance(it, list) else f".text({swift(it)})" for it in items)
            lines.append(f"            ({swift(heading)}, [{its}]),")
        lines.append("        ]),")
    lines += ["    ]", "}", ""]
    with open(os.path.join(ROOT, "App", "LegalText.swift"), "w") as f:
        f.write("\n".join(lines))
    print("wrote docs/{index,privacy,terms,licenses}.html and App/LegalText.swift")

if __name__ == "__main__":
    main()
