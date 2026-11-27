#!/usr/bin/env python3
"""One source for the hosted site, legal pages (docs/*.html), and the in-app copy (App/LegalText.swift).

    python3 Tools/build_legal.py
"""
import html
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = "https://mossotto.pages.dev"
SUPPORT_URL = "https://mossotto.pages.dev/#support"
MOSSLING_SITE = "https://mossotto.pages.dev/"
MOSSLING_STORE = "https://apps.apple.com/app/id6825856138"
EFFECTIVE = "2026 年 11 月 24 日"

URL_RX = re.compile(r"https://[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+")

# Each document: (id, title, [(heading, [paragraph | ["bullet", ...]])], [(action_title, action_subtitle, action_url)])
DOCS = [
    (
        "privacy",
        "隐私政策",
        [
            (
                "一、适用范围与运营主体",
                [
                    "本隐私政策适用于 iOS 应用「Mosto键盘」及其配套系统键盘扩展（以下合称“本应用”）。本应用的开发者与运营主体以 Apple App Store 商品页公示的开发者主体（OTTOSSOM Studio）为准。",
                    "本应用无需注册账号，不包含广告、数据统计分析、崩溃上报或任何第三方追踪 SDK。依据《常见类型移动互联网应用程序必要个人信息范围规定》，输入法类基本功能服务无需提供任何个人信息即可完整使用。",
                ],
            ),
            (
                "二、键盘扩展全程离线，伴侣应用零追踪",
                [
                    "Mosto键盘系统扩展（.appex）100% 在你的设备本地运行：不发起任何网络请求，不读取剪贴板、通讯录、相册、定位或其他应用数据。你在任何应用内输入的文字内容，开发者均无法获取。",
                    "伴侣应用同样不自建后台服务器，不采集或上传任何个人信息；仅当你主动轻点官方支持入口、官网介绍或《摸索台灯》关联卡片时，应用才会通过系统内置浏览器（SFSafariViewController）或 Apple 原生商店卡片（StoreKit）打开你选择的目标页面。",
                    "本应用不含任何生成式人工智能（AI）或大语言模型功能，也不接入云端推理服务；所有候选排序、触点纠错与词语联想均由本机内置词库与静态统计语言模型完成。",
                ],
            ),
            (
                "三、仅保存在本机私有容器的数据清单",
                [
                    "键盘扩展与伴侣应用彼此独立存放于各自的系统私有沙盒容器内，绝不跨应用读取用户输入。以下轻量记录仅保存于当前设备本地，直至你手动清除或卸载应用：",
                    [
                        "键盘学习记录（键盘扩展本机空间）：你主动选过的词组与双词衔接偏好，用于让常用表达排在更靠前的位置；",
                        "触点偏移习惯（键盘扩展本机空间）：按键落点的本机统计偏移，用于优化全拼、九宫格与小鹤双拼的纠错准度；",
                        "键盘偏好与常用表情（键盘扩展本机空间）：输入方案（全拼 / 小鹤双拼）、九宫格/全键盘开关、日夜外观与最近使用的表情/颜文字；",
                        "本机诊断计数（键盘扩展本机空间）：按键响应耗时与系统状态计数，仅在键盘内“诊断”面板中向你本人展示；",
                        "伴侣应用轻量偏好（伴侣应用本机空间）：离线彩蛋小游戏《桌边夜行 · Mosto Run》的本机最高分与音效开关，不接触任何输入记录。",
                    ],
                    "如你在 iOS 系统设置中开启了 iCloud 云备份或整机本地备份，上述设备数据可能随系统整机备份一并保存，由 Apple 按照对应系统隐私条款处理。",
                ],
            ),
            (
                "四、系统权限说明",
                [
                    [
                        "“允许完全访问”（可选）：iOS 为第三方键盘提供的系统开关。本应用仅在开启后用于播放按键震动反馈与系统按键声效；不开启也能完整使用全拼、九宫格、小鹤双拼、触点纠错与词语联想等全部核心功能。即便开启，键盘扩展依然零联网、零剪贴板读取。",
                        "未申请敏感权限：本应用不申请定位、相机、麦克风、通讯录、照片图库、蓝牙、日历、通知或剪贴板读取权限。",
                    ],
                ],
            ),
            (
                "五、密码与安全输入框保护",
                [
                    "在密码、验证码、银行卡与支付密码等安全输入框中，iOS 会自动切换回系统原生安全键盘，第三方键盘不会被系统加载，也无法接触任何安全输入内容。",
                ],
            ),
            (
                "六、你的权利与数据删除方式",
                [
                    "你可以随时查阅并彻底清除本机保留的本地数据：",
                    [
                        "清除输入学习数据：在系统键盘内点击顶栏设置 › 学习 ›“清空已学习的词语与触点习惯”，即可立即清除全部个人学习词库与触点偏移；",
                        "清除全部本机数据：卸载 Mosto键盘后，设备中保存的所有配置、词库学习记录与彩蛋最高分将被 iOS 系统彻底清除；开发者无任何云端留存。",
                    ],
                ],
            ),
            (
                "七、未成年人保护与支持渠道",
                [
                    "本应用不收集任何人的个人信息，包括未满 14 周岁儿童及未成年人的个人信息。",
                    "当你通过 App Store、TestFlight 或官网支持中心主动向我们提交产品反馈时，相关诊断与描述仅用于排查问题和改善产品体验。",
                    "本政策如有更新，将在官方支持页面与本应用内同步公布并更新生效日期。",
                ],
            ),
        ],
        [
            ("官方支持与反馈", "前往 OTTOSSOM 官网支持中心", SUPPORT_URL),
            ("在浏览器中查看隐私政策", "打开独立网页版本", SITE + "/privacy.html"),
        ],
    ),
    (
        "terms",
        "用户协议",
        [
            (
                "一、条款适用与服务性质",
                [
                    "本协议约定你与 OTTOSSOM Studio（下称“开发者”）之间就下载、安装与使用 Mosto键盘（下称“本应用”）所形成的权利义务。安装或继续使用本应用，即表示你已阅读并同意本协议。",
                    "本应用为免费提供的纯离线商业工具软件，不含广告、订阅或应用内购买；后续版本更新通过 Apple App Store 统一分发。",
                ],
            ),
            (
                "二、使用规范与输入核对提示",
                [
                    "候选词排序、触点纠错与词语联想均基于本机词库与静态统计语言模型实时计算，可能存在同音误选、词组偏差或错别字。在发送重要消息，或填写付款金额、医疗、合同、法律等关键信息前，请务必自行核对实际输入文字。",
                    "你不得将本应用用于违反所在地法律法规或侵害他人合法权益的用途，亦不得对本应用受保护的专有设计、品牌形象与核心引擎资产进行商业仿冒或侵权传播。",
                ],
            ),
            (
                "三、按现状提供与免责声明",
                [
                    "在适用法律允许的最大范围内，本应用按“现状”和“现有”提供，不作任何明示或默示的保证，包括但不限于适销性、特定用途适用性与不侵权保证。",
                    "对于因使用或无法使用本应用（包括但不限于候选偏差、自动纠错、系统兼容性限制或设备故障）造成的直接或间接损失，开发者不承担赔偿责任；适用法律另有强制性规定的，从其规定。",
                    "内置词条来源于公开语言统计而非人工编撰或 AI 生成，个别词条可能存在不准确表达，不代表开发者立场。你可以在候选栏长按个人学过的词条将其删除。",
                ],
            ),
            (
                "四、原创知识产权与品牌归属",
                [
                    "Mosto键盘的核心中文输入解码引擎、触点概率纠错模型、双段内存映射索引架构、滑键与游标手势交互体系、实体键帽与夜间光效视觉规范，均系 OTTOSSOM Studio 原创设计作品与著作权资产。",
                    "OTTOSSOM IP 家族原创角色形象（Moss、Otto 与 Mosto）、3D/2D 造型、界面视觉与名称“Mosto键盘”“摸索台灯”“OTTOSSOM”归开发者所有，未经书面授权不得用于商业混淆、复制或仿冒。",
                    "本应用在构建中合规引用的第三方开放语言数据与构建组件，详见“第三方致谢与合规声明”。",
                ],
            ),
            (
                "五、第三方名称与非隶属声明",
                [
                    "“小鹤双拼”“小鹤音形”是小鹤官方发布的输入方案名称，相关名称、标识及商标等权利归其权利人所有。本应用与小鹤及其权利人没有隶属、合作、授权或背书关系。",
                    "本应用中的“小鹤双拼”选项仅指与该方案兼容的声母/韵母键位映射规则，由开发者依据公开汉语拼音规则独立实现；本应用不包含、不分发小鹤音形码表、小鹤官方软件或其词库，也不使用小鹤的标识。",
                    "iOS、iPhone、TestFlight、App Store、Safari 是 Apple Inc. 的注册商标；本应用与 Apple 没有隶属、合作或背书关系。如任何权利人认为本应用存在名称或权利疑义，请通过官网支持中心联系，开发者将及时核实处理。",
                ],
            ),
            (
                "六、适用法律与协议变更",
                [
                    "本协议的解释与争议解决适用中华人民共和国法律（不含冲突法规则）；如你所在司法辖区存在不可排除的强制性消费者保护规定，则同时尊重该强制性规定。",
                    "本协议如有更新，将在官网与本应用内同步公布。继续使用本应用即视为接受更新后的协议。",
                ],
            ),
        ],
        [
            ("权利通知与官方支持", "前往官网支持中心联系我们", SUPPORT_URL),
            ("在浏览器中查看用户协议", "打开独立网页版本", SITE + "/terms.html"),
        ],
    ),
    (
        "notices",
        "第三方致谢与合规声明",
        [
            (
                "一、第三方开放数据与构建组件致谢",
                [
                    "Mosto键盘坚持完全本机计算、不依赖云端词库。本应用的核心解码器、触点纠错模型与交互视觉为 OTTOSSOM Studio 原创作品；部分词库语料与构建期工具基于以下公开项目合规整理与署名致谢：",
                    [
                        "雾凇拼音（rime-ice）：提供基础中文单字与常用词库语料（GPL-3.0-only）",
                        "八股文（rime-octagram-data）：提供上下文搭配与词语联想语言模型语料（LGPL-3.0-only）",
                        "万象语法模型（rime-wanxiang-data）：提供离线整句 N-gram 蒸馏语料参考（CC-BY-4.0）",
                        "wordfreq：提供公开英文词频统计表，用于中英混输候选排序（CC-BY-SA-4.0）",
                        "Emojibase：提供标准 Unicode Emoji 列表、分组与版本元数据（MIT）",
                        "Unicode CLDR：提供标准中文表情名称与检索词，用于本机表情联想（Unicode-3.0）",
                        "darts-clone：Double-Array Trie 离线索引构建库，仅于构建期使用（BSD-2-Clause）",
                        "pypinyin：词库构建期汉语拼音注音映射工具，仅于构建期使用（MIT）",
                    ],
                    "上述公开数据、标准与开源项目的所有权及商标权归原机构或原作者所有，本应用仅作合规署名致谢，不代表原机构或原作者对本应用的背书或合作关系。",
                ],
            ),
            (
                "二、离线合规、无生成式 AI 与平台规范",
                [
                    [
                        "纯本地单机工具：Mosto键盘扩展全程离线运行，伴侣应用亦不设后台服务器、账号系统或信息流发布服务；如未来版本新增任何联网服务，将在上线前依法完成对应地区的合规备案与公示。",
                        "中国个人信息保护合规：遵循《中华人民共和国个人信息保护法》（PIPL）及《常见类型移动互联网应用程序必要个人信息范围规定》，零采集、零上传、零画像。",
                        "App Store 隐私声明一致：隐私营养标签申报为“不收集数据（Data Not Collected）”，应用包内不含任何跨应用追踪接口或 IDFA 请求。",
                        "无生成式 AI 声明：本应用不接入任何大语言模型或生成式人工智能服务，亦不包含个性化广告或信息流推荐算法；所有候选均基于本机确定性词库与静态语言统计生成。",
                    ],
                ],
            ),
            (
                "三、同门产品与官方支持",
                [
                    "同门系列作品：《摸索台灯》（Mossling）是一款面向 0–3 岁亲子共玩与床头夜灯陪伴的 iOS 应用，Moss、Otto 与 Mosto 同属于 OTTOSSOM 设计宇宙。",
                    "如需获取使用帮助、查阅最新说明或提交意见反馈，请通过下方官方支持中心联系我们。",
                ],
            ),
        ],
        [
            ("访问 OTTOSSOM 官网与支持", "查看《摸索台灯》与官方帮助", SUPPORT_URL),
            ("在 App Store 查看《摸索台灯》", "OTTOSSOM 同门床头夜灯应用", MOSSLING_STORE),
        ],
    ),
]


def esc(s):
    """HTML-escape prose and safely linkify any URL without swallowing trailing punctuation."""
    parts = []
    pos = 0
    for m in URL_RX.finditer(s):
        if m.start() > pos:
            parts.append(html.escape(s[pos:m.start()]))
        raw_url = m.group(0)
        stripped = raw_url.rstrip(".,;:!?)")
        tail = raw_url[len(stripped):]
        safe_url = html.escape(stripped, quote=True)
        parts.append(f'<a href="{safe_url}">{html.escape(stripped)}</a>{html.escape(tail)}')
        pos = m.end()
    if pos < len(s):
        parts.append(html.escape(s[pos:]))
    return "".join(parts)


SHARED_CSS = """:root{
  --bg:#F7F4EE;
  --surface:#FFFFFF;
  --surface-muted:#EFEAE0;
  --ink:#1E192B;
  --sub:#6A6478;
  --line:#E4DDD0;
  --violet:#633EBF;
  --on-violet:#FFFFFF;
  --amber:#D69A34;
  --moss:#55704A;
  --otto:#203872;
  --shadow:0 12px 32px rgba(30,25,43,.06);
}
@media (prefers-color-scheme:dark){
  :root{
    --bg:#14121D;
    --surface:#1F1B2E;
    --surface-muted:#28233B;
    --ink:#F4F1FA;
    --sub:#A7A1B8;
    --line:rgba(255,255,255,.11);
    --violet:#A78BFA;
    --on-violet:#1A1429;
    --amber:#FFC45A;
    --moss:#7EA86E;
    --otto:#7FA6E8;
    --shadow:0 14px 36px rgba(0,0,0,.35);
  }
}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{
  margin:0;
  background:var(--bg);
  color:var(--ink);
  font:16px/1.7 -apple-system,BlinkMacSystemFont,"PingFang SC","SF Pro Text",system-ui,sans-serif;
  -webkit-font-smoothing:antialiased;
}
a{color:var(--violet);text-decoration:none}
a:hover{text-decoration:underline}
.topbar{
  position:sticky;
  top:0;
  z-index:20;
  backdrop-filter:blur(16px);
  -webkit-backdrop-filter:blur(16px);
  background:color-mix(in srgb,var(--bg) 86%,transparent);
  border-bottom:1px solid var(--line);
}
.topbar-inner{
  max-width:1040px;
  margin:0 auto;
  padding:14px 20px;
  display:flex;
  align-items:center;
  justify-content:space-between;
  gap:16px;
  flex-wrap:wrap;
}
.brand{
  display:inline-flex;
  align-items:center;
  gap:10px;
  font-weight:700;
  color:var(--ink);
  letter-spacing:-.01em;
}
.brand-dot{
  width:10px;
  height:10px;
  border-radius:999px;
  background:linear-gradient(135deg,var(--violet),var(--amber));
  box-shadow:0 0 12px color-mix(in srgb,var(--amber) 55%,transparent);
}
nav{
  display:flex;
  align-items:center;
  gap:16px;
  flex-wrap:wrap;
  font-size:14px;
  font-weight:500;
}
nav a{color:var(--sub)}
nav a:hover,nav a[aria-current="page"]{color:var(--ink);text-decoration:none}
.wrap{max-width:1040px;margin:0 auto;padding:32px 20px 64px}
.narrow{max-width:780px}
.card{
  background:var(--surface);
  border:1px solid var(--line);
  border-radius:22px;
  padding:22px 24px;
  box-shadow:var(--shadow);
}
.btn{
  display:inline-flex;
  align-items:center;
  justify-content:center;
  gap:8px;
  padding:12px 20px;
  border-radius:14px;
  font-size:15px;
  font-weight:600;
  transition:transform .15s ease,opacity .15s ease;
}
.btn:hover{text-decoration:none;transform:translateY(-1px)}
.btn-primary{background:var(--violet);color:var(--on-violet)}
.btn-secondary{background:var(--surface-muted);color:var(--ink);border:1px solid var(--line)}
.pill{
  display:inline-flex;
  align-items:center;
  gap:6px;
  padding:5px 12px;
  border-radius:999px;
  font-size:12px;
  font-weight:600;
  background:color-mix(in srgb,var(--violet) 12%,transparent);
  color:var(--violet);
}
.pill-moss{background:color-mix(in srgb,var(--moss) 14%,transparent);color:var(--moss)}
.pill-amber{background:color-mix(in srgb,var(--amber) 16%,transparent);color:var(--amber)}
footer{
  margin-top:48px;
  padding-top:24px;
  border-top:1px solid var(--line);
  color:var(--sub);
  font-size:13px;
  display:flex;
  justify-content:space-between;
  gap:12px;
  flex-wrap:wrap;
}
.footer-links{display:flex;gap:16px;flex-wrap:wrap}
.footer-links a{color:var(--sub)}
"""


def nav_html(current="index"):
    links = [
        ("index.html", "首页", "index"),
        ("index.html#features", "核心能力", "features"),
        ("index.html#family", "摸索台灯", "family"),
        ("index.html#support", "官方支持", "support"),
        ("privacy.html", "隐私政策", "privacy"),
        ("terms.html", "用户协议", "terms"),
        ("notices.html", "致谢与合规", "notices"),
    ]
    nav_items = []
    for href, label, key in links:
        cur = ' aria-current="page"' if key == current else ""
        nav_items.append(f'<a href="{href}"{cur}>{html.escape(label)}</a>')
    return (
        '<header class="topbar"><div class="topbar-inner">'
        '<a class="brand" href="index.html"><span class="brand-dot"></span><span>OTTOSSOM · Mosto键盘</span></a>'
        f'<nav>{"".join(nav_items)}</nav>'
        "</div></header>"
    )


def footer_html():
    return (
        "<footer>"
        "<div>Mosto键盘 · OTTOSSOM Studio 原创作品 · 纯离线零追踪 · © 2026 OTTOSSOM Studio</div>"
        '<div class="footer-links">'
        '<a href="privacy.html">隐私政策</a>'
        '<a href="terms.html">用户协议</a>'
        '<a href="notices.html">第三方致谢与合规声明</a>'
        '<a href="index.html#support">官方支持</a>'
        "</div></footer>"
    )


LEGAL_PAGE = """<!doctype html>
<html lang="zh-Hans">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · Mosto键盘</title>
<style>
{css}
.doc-head{{margin-bottom:20px}}
.doc-head h1{{font-size:30px;line-height:1.25;margin:8px 0 6px;letter-spacing:-.02em}}
.doc-meta{{color:var(--sub);font-size:14px}}
.doc-section{{margin:14px 0}}
.doc-section h2{{font-size:17px;margin:0 0 10px;letter-spacing:-.01em}}
.doc-section p,.doc-section li{{margin:8px 0;color:var(--ink)}}
.doc-section ul{{margin:8px 0;padding-left:20px}}
.actions{{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:12px;margin-top:18px}}
.action-card{{
  display:flex;
  align-items:center;
  justify-content:space-between;
  gap:12px;
  padding:14px 18px;
  border-radius:16px;
  background:var(--surface);
  border:1px solid var(--line);
  color:var(--ink);
}}
.action-card:hover{{text-decoration:none;border-color:var(--violet)}}
.action-title{{font-weight:600;font-size:15px}}
.action-sub{{font-size:13px;color:var(--sub)}}
</style>
</head>
<body>
{nav}
<main class="wrap narrow">
  <div class="doc-head">
    <span class="pill">OTTOSSOM Studio 官方文档</span>
    <h1>{title}</h1>
    <div class="doc-meta">生效日期：{effective}</div>
  </div>
  {body}
  {actions}
  {footer}
</main>
</body>
</html>
"""


def render_legal_body(sections):
    parts = []
    for heading, items in sections:
        inner = []
        for it in items:
            if isinstance(it, list):
                inner.append("<ul>" + "".join(f"<li>{esc(x)}</li>" for x in it) + "</ul>")
            else:
                inner.append(f"<p>{esc(it)}</p>")
        parts.append(f'<section class="card doc-section"><h2>{html.escape(heading)}</h2>{"".join(inner)}</section>')
    return "\n  ".join(parts)


def render_legal_actions(actions):
    if not actions:
        return ""
    cards = []
    for title, subtitle, url in actions:
        cards.append(
            f'<a class="action-card" href="{html.escape(url, quote=True)}">'
            f'<div><div class="action-title">{html.escape(title)}</div>'
            f'<div class="action-sub">{html.escape(subtitle)}</div></div>'
            '<span aria-hidden="true">↗</span></a>'
        )
    return '<div class="actions">' + "".join(cards) + "</div>"


def render_index_html():
    return f"""<!doctype html>
<html lang="zh-Hans">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mosto键盘 · 全拼九宫格离线精准中文输入法 · OTTOSSOM</title>
<meta name="description" content="Mosto键盘是 OTTOSSOM Studio 出品的纯离线 iOS 中文输入法，原生支持全拼全键盘、九宫格全拼与小鹤双拼，以触点几何纠错与零联网隐私守护每天的高频输入。">
<style>
{SHARED_CSS}
.hero{{
  position:relative;
  overflow:hidden;
  border-radius:28px;
  padding:36px 32px;
  background:radial-gradient(circle at 82% 12%,color-mix(in srgb,var(--amber) 22%,transparent),transparent 46%),
             radial-gradient(circle at 14% 85%,color-mix(in srgb,var(--violet) 16%,transparent),transparent 52%),
             var(--surface);
  border:1px solid var(--line);
  box-shadow:var(--shadow);
  display:grid;
  grid-template-columns:1.25fr .95fr;
  gap:28px;
  align-items:center;
}}
@media (max-width:780px){{.hero{{grid-template-columns:1fr;padding:26px 20px}}}}
.hero-badges{{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:14px}}
.hero h1{{font-size:38px;line-height:1.18;margin:0 0 14px;letter-spacing:-.025em}}
@media (max-width:600px){{.hero h1{{font-size:30px}}}}
.hero p{{margin:0 0 22px;color:var(--sub);font-size:16.5px;max-width:54ch}}
.hero-cta{{display:flex;gap:12px;flex-wrap:wrap}}
.hero-stage{{
  background:var(--surface-muted);
  border:1px solid var(--line);
  border-radius:22px;
  padding:20px;
  display:flex;
  flex-direction:column;
  gap:14px;
}}
.preview-bar{{
  display:flex;
  align-items:center;
  justify-content:space-between;
  gap:8px;
  background:var(--surface);
  border:1px solid var(--line);
  border-radius:12px;
  padding:8px 12px;
  font-size:13px;
}}
.preview-cands{{display:flex;gap:10px;font-weight:600;color:var(--ink)}}
.preview-fix{{color:var(--violet);font-size:12px;font-weight:600}}
.key-grid{{display:grid;grid-template-columns:repeat(6,1fr);gap:6px}}
.kcap{{
  background:var(--surface);
  border:1px solid var(--line);
  border-radius:10px;
  height:38px;
  display:flex;
  align-items:center;
  justify-content:center;
  font-weight:600;
  font-size:14px;
  box-shadow:0 2px 0 color-mix(in srgb,var(--ink) 8%,transparent);
}}
.kcap.accent{{background:var(--violet);color:var(--on-violet);border-color:transparent}}
.kcap.amber{{background:color-mix(in srgb,var(--amber) 24%,var(--surface));color:var(--ink)}}
.section-head{{margin:48px 0 18px}}
.section-head h2{{font-size:26px;margin:6px 0 4px;letter-spacing:-.02em}}
.section-head p{{margin:0;color:var(--sub)}}
.bento{{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}}
@media (max-width:860px){{.bento{{grid-template-columns:repeat(2,1fr)}}}}
@media (max-width:580px){{.bento{{grid-template-columns:1fr}}}}
.bento .card{{padding:20px 22px;display:flex;flex-direction:column;gap:8px}}
.bento h3{{margin:4px 0 2px;font-size:17px}}
.bento p{{margin:0;color:var(--sub);font-size:14.5px}}
.icon-box{{
  width:36px;height:36px;border-radius:10px;
  display:inline-flex;align-items:center;justify-content:center;
  font-weight:700;font-size:14px;
  background:color-mix(in srgb,var(--violet) 14%,transparent);
  color:var(--violet);
}}
.icon-box.moss{{background:color-mix(in srgb,var(--moss) 15%,transparent);color:var(--moss)}}
.icon-box.amber{{background:color-mix(in srgb,var(--amber) 18%,transparent);color:var(--amber)}}
.icon-box.otto{{background:color-mix(in srgb,var(--otto) 15%,transparent);color:var(--otto)}}
.family-grid{{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin-bottom:16px}}
@media (max-width:760px){{.family-grid{{grid-template-columns:1fr}}}}
.member-tag{{font-size:12px;font-weight:600;color:var(--sub)}}
.sister-banner{{
  display:flex;align-items:center;justify-content:space-between;gap:20px;flex-wrap:wrap;
  background:linear-gradient(135deg,color-mix(in srgb,var(--otto) 8%,var(--surface)),color-mix(in srgb,var(--amber) 10%,var(--surface)));
}}
.support-grid{{display:grid;grid-template-columns:1fr 1.15fr;gap:16px}}
@media (max-width:780px){{.support-grid{{grid-template-columns:1fr}}}}
.steps{{margin:0;padding-left:20px}}
.steps li{{margin:10px 0}}
details{{border-bottom:1px solid var(--line);padding:12px 0}}
details:last-of-type{{border-bottom:none}}
summary{{cursor:pointer;font-weight:600;list-style:none;display:flex;justify-content:space-between;align-items:center}}
summary::-webkit-details-marker{{display:none}}
details p{{margin:8px 0 0;color:var(--sub);font-size:14.5px}}
</style>
</head>
<body>
{nav_html("index")}
<main class="wrap">
  <section class="hero">
    <div>
      <div class="hero-badges">
        <span class="pill">全拼 · 九宫格 · 小鹤双拼</span>
        <span class="pill pill-moss">100% 本机离线 · 零联网</span>
      </div>
      <h1>把每天触碰最多次的屏幕，打磨到硬件级准度</h1>
      <p>Mosto键盘是 OTTOSSOM 推出的纯离线中文 iOS 键盘。开箱即用全拼全键盘与九宫格全拼，融合触点几何纠错、48.4 MB 本机双段离线引擎与零“完全访问”隐私边界——由手机里的 Mosto，引出你书桌上的 Moss 与 Otto《摸索台灯》。</p>
      <div class="hero-cta">
        <a class="btn btn-primary" href="#support">App Store 即将上架 · 启用指引</a>
        <a class="btn btn-secondary" href="#family">探索《摸索台灯》家族</a>
      </div>
    </div>
    <div class="hero-stage" aria-label="Mosto键盘触点纠错示意">
      <div class="preview-bar">
        <div class="preview-cands"><span>你好</span><span style="color:var(--sub);font-weight:500">尼好</span><span style="color:var(--sub);font-weight:500">拟好</span></div>
        <span class="preview-fix">nihap → nihao</span>
      </div>
      <div class="key-grid">
        <div class="kcap">Q</div><div class="kcap">W</div><div class="kcap">E</div><div class="kcap">R</div><div class="kcap">T</div><div class="kcap">Y</div>
        <div class="kcap">A</div><div class="kcap">S</div><div class="kcap">D</div><div class="kcap">F</div><div class="kcap amber">G</div><div class="kcap">H</div>
        <div class="kcap">123</div><div class="kcap">，↑。</div><div class="kcap" style="grid-column:span 2">空格游标</div><div class="kcap">中/英</div><div class="kcap accent">换行</div>
      </div>
      <div style="font-size:12.5px;color:var(--sub);display:flex;justify-content:space-between;gap:8px;flex-wrap:wrap">
        <span>日间暖瓷 / 夜间台灯双外观</span>
        <span>不开启完全访问亦可完整打字</span>
      </div>
    </div>
  </section>

  <div id="features" class="section-head">
    <span class="pill">六大核心能力</span>
    <h2>为大众高频中文输入而设的精准引擎</h2>
    <p>没有云端猜测、没有广告推送，把每一分计算留在本机输入手感上。</p>
  </div>
  <section class="bento">
    <article class="card">
      <div class="icon-box">全</div>
      <h3>全拼全键盘，整句直接顺打</h3>
      <p>针对日常全拼习惯优化整句解码、简拼（如 bzd）与中英混输，长句首词精准命中，无需逐词确认。</p>
    </article>
    <article class="card">
      <div class="icon-box otto">九</div>
      <h3>九宫格全拼，单手顺滑跟手</h3>
      <p>2–9 键单手快速拼词，左侧动态拼音微调栏随打随选，右侧独立符号面板保持底栏零漂移。</p>
    </article>
    <article class="card">
      <div class="icon-box amber">纠</div>
      <h3>触点几何纠错，顺手就读准</h3>
      <p>结合真实手指落点概率与语言统计，自动修正偏邻键、多按、漏按与相邻换位；空格后支持一键撤回原键。</p>
    </article>
    <article class="card">
      <div class="icon-box">语</div>
      <h3>48.4 MB 本机双段离线引擎</h3>
      <p>单文件 8-bit 量化双段内存映射架构，同时承担 1164 万条 2–4 元整句解码与 85 万条上下文联想，毫秒响应零卡顿。</p>
    </article>
    <article class="card">
      <div class="icon-box moss">隐</div>
      <h3>无需“完全访问”的隐私证明</h3>
      <p>键盘扩展全程零联网、零剪贴板读取。个人词频、双词习惯与触点偏移只留在设备本地，随删随清。</p>
    </article>
    <article class="card">
      <div class="icon-box">双</div>
      <h3>高效手势与小鹤双拼支持</h3>
      <p>自带标点轻上滑、空格游标微调、行内四则心算与横滑表情/颜文字面板，并为双拼用户内置完整小鹤键位方案。</p>
    </article>
  </section>

  <div id="family" class="section-head">
    <span class="pill pill-amber">OTTOSSOM IP 宇宙</span>
    <h2>认识住在键盘与书桌上的三位伙伴</h2>
    <p>Mosto键盘是《摸索台灯》的日常高频入口先锋，在同一套日光暖瓷与夜间微光设计语言下陪伴左右。</p>
  </div>
  <section class="family-grid">
    <article class="card">
      <div class="member-tag">Moss · 摸索与好奇心</div>
      <h3>Moss</h3>
      <p style="color:var(--sub);margin:6px 0 0;font-size:14.5px">顶着薄荷嫩芽的绒绿小鹅卵石，象征每一次下意识按键时的好奇、轻快与克制护持。</p>
    </article>
    <article class="card">
      <div class="member-tag">Mosto · 键盘里的伙伴</div>
      <h3>Mosto</h3>
      <p style="color:var(--sub);margin:6px 0 0;font-size:14.5px">住在键盘底栏的紫色小魔王：单击切表情、双击呼出自适应颜文字面板、长按直达键盘控制台。</p>
    </article>
    <article class="card">
      <div class="member-tag">Otto · 台灯与柔和陪伴</div>
      <h3>Otto</h3>
      <p style="color:var(--sub);margin:6px 0 0;font-size:14.5px">头顶暖金灯珠的深蓝台灯大人，在深夜里为键盘与书桌调亮一束柔和而不刺眼的微光。</p>
    </article>
  </section>

  <section class="card sister-banner">
    <div style="max-width:58ch">
      <span class="pill pill-amber" style="margin-bottom:8px">同门作品 · 《摸索台灯》</span>
      <h3 style="margin:4px 0 6px;font-size:21px">孩子摸索，大人点灯</h3>
      <p style="margin:0;color:var(--sub);font-size:15px">《摸索台灯》（Mossling）是一款 0–3 岁亲子共玩、床头夜灯与成长手账 iOS 应用。把键盘上的安静手感带回书桌，和 Moss、Otto 一起度过温柔的夜晚。</p>
    </div>
    <div class="hero-cta">
      <a class="btn btn-primary" href="{MOSSLING_STORE}">前往 App Store 了解《摸索台灯》</a>
    </div>
  </section>

  <div id="support" class="section-head">
    <span class="pill pill-moss">官方支持中心</span>
    <h2>启用指南与常见问题</h2>
    <p>三步开启 Mosto键盘；如在使用中需要协助，欢迎查阅下方常见问题或通过 App Store 商品页联系开发者。</p>
  </div>
  <section class="support-grid">
    <div class="card">
      <h3 style="margin:0 0 10px">三步启用 Mosto键盘</h3>
      <ol class="steps">
        <li>打开 iPhone 的 <strong>设置 › 通用 › 键盘 › 键盘</strong>；</li>
        <li>轻点 <strong>添加新键盘</strong>，在列表中选中 <strong>Mosto键盘</strong>；</li>
        <li>在任意输入框长按地球键切换至 Mosto键盘即可使用（不开启“允许完全访问”也可正常完成全部输入与纠错）。</li>
      </ol>
      <div style="margin-top:16px;padding:12px 14px;border-radius:14px;background:var(--surface-muted);font-size:14px;color:var(--sub)">
        反馈与协助：请通过 <strong>App Store 商品页支持入口</strong> 或 <strong>TestFlight 反馈功能</strong> 与 OTTOSSOM Studio 取得联系，我们会在第一时间跟进处理。
      </div>
    </div>
    <div class="card">
      <h3 style="margin:0 0 6px">常见问答</h3>
      <details open>
        <summary>不开启“允许完全访问”也能使用吗？</summary>
        <p>可以。全拼、九宫格、小鹤双拼、触点纠错、词库联想与表情/颜文字面板均 100% 本地运行，无需“允许完全访问”。该系统开关仅用于开启按键震动与系统声效。</p>
      </details>
      <details>
        <summary>如何在全拼、九宫格和小鹤双拼之间切换？</summary>
        <p>在 Mosto键盘中轻点顶栏右侧齿轮图标，或长按底栏 Mosto 图标打开控制台，即可直接切换全拼 / 小鹤双拼、九宫格 / 全键盘以及日光 / 夜灯外观。</p>
      </details>
      <details>
        <summary>如何清除我学过的词和触点习惯？</summary>
        <p>在键盘内打开控制台 › 学习，轻点“清空已学习的词语与触点习惯”即可立即清空；卸载应用后所有本地记录也会随系统容器彻底删除。</p>
      </details>
      <details>
        <summary>键盘内为什么不支持联网云同步？</summary>
        <p>我们希望键盘扩展成为绝对可信的纯离线输入工具：不发起网络请求、不读写剪贴板、不采集任何个人输入习惯，彻底消除隐忧。</p>
      </details>
    </div>
  </section>

  {footer_html()}
</main>
</body>
</html>
"""


def render_compat_stub(filename, title):
    return f"""<!doctype html>
<html lang="zh-Hans">
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="0; url=notices.html">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} · Mosto键盘</title>
<style>{SHARED_CSS}</style>
</head>
<body>
{nav_html("notices")}
<main class="wrap narrow">
  <section class="card">
    <h1 style="margin:0 0 8px">{html.escape(title)}</h1>
    <p style="color:var(--sub)">相关内容已合并收录于新版《第三方致谢与合规声明》页面。</p>
    <p style="margin-top:18px"><a class="btn btn-primary" href="notices.html">前往第三方致谢与合规声明</a></p>
  </section>
  {footer_html()}
</main>
</body>
</html>
"""


def main():
    os.makedirs(os.path.join(ROOT, "docs"), exist_ok=True)
    for did, title, sections, actions in DOCS:
        with open(os.path.join(ROOT, "docs", f"{did}.html"), "w", encoding="utf-8") as f:
            f.write(
                LEGAL_PAGE.format(
                    title=html.escape(title),
                    effective=html.escape(EFFECTIVE),
                    css=SHARED_CSS,
                    nav=nav_html(did),
                    body=render_legal_body(sections),
                    actions=render_legal_actions(actions),
                    footer=footer_html(),
                )
            )

    with open(os.path.join(ROOT, "docs", "index.html"), "w", encoding="utf-8") as f:
        f.write(render_index_html())

    for stub_id, stub_title in [
        ("sources", "内容与词库来源"),
        ("licenses", "第三方致谢与许可"),
        ("regulatory", "法规、备案与合规信息"),
    ]:
        with open(os.path.join(ROOT, "docs", f"{stub_id}.html"), "w", encoding="utf-8") as f:
            f.write(render_compat_stub(f"{stub_id}.html", stub_title))

    open(os.path.join(ROOT, "docs", ".nojekyll"), "w", encoding="utf-8").close()

    def swift(s):
        return json.dumps(s, ensure_ascii=False)

    lines = [
        "// Generated by Tools/build_legal.py — edit the source there, not here.",
        "",
        "enum LegalText {",
        f"    static let effective = {swift(EFFECTIVE)}",
        f"    static let site = {swift(SITE)}",
        f"    static let supportURL = {swift(SUPPORT_URL)}",
        "    enum Item { case text(String), bullets([String]) }",
        "    struct Action { let title: String; let subtitle: String; let url: String }",
        "    struct Doc { let id: String; let title: String; let sections: [(String, [Item])]; let actions: [Action] }",
        "    static let docs: [Doc] = [",
    ]
    for did, title, sections, actions in DOCS:
        lines.append(f"        Doc(id: {swift(did)}, title: {swift(title)}, sections: [")
        for heading, items in sections:
            its = ", ".join(
                f".bullets([{', '.join(swift(x) for x in it)}])" if isinstance(it, list) else f".text({swift(it)})"
                for it in items
            )
            lines.append(f"            ({swift(heading)}, [{its}]),")
        acts = ", ".join(
            f"Action(title: {swift(at)}, subtitle: {swift(asub)}, url: {swift(au)})"
            for at, asub, au in actions
        )
        lines.append(f"        ], actions: [{acts}]),")
    lines += ["    ]", "}", ""]
    with open(os.path.join(ROOT, "App", "LegalText.swift"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("wrote docs/{index,privacy,terms,notices,sources,licenses,regulatory}.html and App/LegalText.swift")


if __name__ == "__main__":
    main()
