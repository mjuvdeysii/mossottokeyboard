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
MOSSLING_SITE = "https://mossotto.pages.dev/"
EFFECTIVE = "2026 年 11 月 24 日"

# Each document: (id, title, [(heading, [paragraph | ["bullet", ...]])])
DOCS = [
    ("privacy", "隐私政策", [
        ("一、适用范围与主体", [
            "本政策适用于 iOS 应用 Mosto键盘 及其中的 Mosto键盘 键盘扩展（以下合称“本应用”）。本应用的开发者主体以 App Store 商品页公示的开发者名称为准。",
            "本应用不需要注册账号，不含广告、统计分析、崩溃上报或任何第三方追踪 SDK。依据《常见类型移动互联网应用程序必要个人信息范围规定》，输入法类基本功能服务无需提供个人信息即可使用。",
        ]),
        ("二、键盘扩展完全离线，伴侣 App 零追踪", [
            "键盘扩展（Mosto键盘 .appex）100% 在设备本地运行：不发起任何网络请求，不读取剪贴板、通讯录、相册、定位或其他 App 数据。你在任何应用里输入的文字，开发者都无法获取。",
            "伴侣 App 同样不自建后台服务器、不采集或上传任何个人信息；仅当你主动点击官网介绍、开源仓库、服务条款网页或“摸索台灯”关联卡片时，应用才会通过系统内置浏览器（SFSafariViewController）或 Apple 原生商店页（StoreKit）打开你点击的目标页面。",
            "本应用不含任何生成式人工智能（AI）或大语言模型功能，也不接入云端推理服务；所有候选、纠错与联想均基于内置开源词库与本机统计模型完成。",
        ]),
        ("三、只保存在本机的数据清单与期限", [
            "为了让输入更顺手，以下数据仅保存在你当前设备的私有存储空间内，永不上传或与第三方共享，直至你手动清除或卸载本应用：",
            ["学习记录：你主动选过的词与词组，用于把常用词排在更靠前的位置；",
             "触点习惯：按键落点的统计偏移量，用于在本机进行触点纠错；",
             "偏好设置与常用表情：输入方案（小鹤双拼 / 全拼）、九宫格/全键盘、日夜外观与最近使用的表情；",
             "本机诊断计数：按键响应耗时与系统取消次数，仅在键盘设置“诊断”中向你本人展示；",
             "离线小彩蛋记录：伴侣 App 离线彩蛋游戏（Mosto Run）的本机最高分，仅存放在本机偏好设置中。"],
            "如果你在系统设置中开启了 iCloud 云备份或电脑整机备份，上述本机数据可能随系统整机备份一并保存，由 Apple 按其隐私政策处理。",
        ]),
        ("四、系统权限说明", [
            ["“允许完全访问”（可选）：iOS 为第三方键盘提供的系统开关。本应用仅在开启时用于播放按键震动反馈与系统按键音；不开启也能正常使用全部核心打字、纠错与候选功能。即使开启，键盘扩展依然零联网、零剪贴板读取。",
             "未申请权限：本应用不申请定位、相机、麦克风、通讯录、照片图库、蓝牙、日历、通知或剪贴板读取权限。"],
        ]),
        ("五、密码与安全输入框保护", [
            "在密码、验证码、支付密码等安全输入框中，iOS 会自动切换回系统自带键盘，第三方键盘不会被系统加载，也无法接触任何安全输入内容。",
        ]),
        ("六、你的权利与数据删除方式", [
            "你可以随时行使对本机数据的查阅与删除权：",
            ["清除输入学习数据：前往键盘设置 › 学习 ›“清空已学习的词语与触点习惯”，即可立即清除全部个人学习词库与触点偏移；",
             "清除全部本机数据：卸载本应用后，设备中保存的所有配置、词库学习记录与彩蛋最高分将被 iOS 彻底删除；开发者无云端留存。"],
        ]),
        ("七、未成年人保护与反馈渠道", [
            "本应用不收集任何人的个人信息，包括未满 14 周岁儿童及未成年人的个人信息。",
            "通过 App Store / TestFlight 提交反馈时，你主动填写的文字、截图与诊断报告由 Apple 按对应平台规则转交开发者，仅用于排查与改进产品；你也可随时通过 " + ISSUES + " 联系开发者。",
            "本政策如有更新，会在本页面与 App 内同步公布并更新生效日期。",
        ]),
    ]),
    ("terms", "用户协议与免责声明", [
        ("一、条款适用与服务性质", [
            "本协议约定你与 Mosto键盘 开发者之间就下载、安装与使用本应用所形成的权利义务。安装或继续使用本应用，即表示你已阅读并同意本协议。",
            "本应用为免费提供的纯离线输入工具，不含广告、订阅或应用内购买；后续版本更新通过 App Store 统一分发。",
        ]),
        ("二、使用规范与输入核对提示", [
            "候选词、触点纠错与词语联想均基于本机开源词库与静态统计语言模型计算得出，可能存在偏差、同音误选或错别字。在发送重要消息，或填写付款、医疗、合同、法律等关键信息前，请务必自行核对实际输入的文字。",
            "你不得将本应用用于违反所在地法律法规或侵害他人合法权益的用途；如你基于本应用开源代码进行二次分发，须严格遵守 GPL-3.0 开源许可证条款。",
        ]),
        ("三、按现状提供与免责声明", [
            "在适用法律允许的最大范围内，本应用按“现状”和“现有”提供，不作任何明示或默示的保证，包括但不限于适销性、特定用途适用性与不侵权保证。",
            "对因使用或无法使用本应用（包括但不限于候选偏差、自动纠错、系统兼容性限制或设备故障）造成的直接或间接损失，开发者不承担赔偿责任；适用法律另有强制性规定的，从其规定。",
            "候选词来源于公开语料统计而非人工编撰或 AI 生成，个别词条可能存在不准确或不当表达，不代表开发者立场。你可以在候选栏长按个人学过的词条将其删除。",
        ]),
        ("四、知识产权与品牌归属", [
            "OTTOSSOM 家族（Moss、Otto、Mosto）原创角色形象、3D/2D 造型、界面视觉与名称“Mosto键盘”“摸索台灯”“OTTOSSOM”归开发者所有，未经授权不得用于商业混淆或仿冒。",
            "本应用源代码以 GPL-3.0 许可证开源，完整代码托管于：" + REPO,
            "第三方词库、语言模型与数据按各自许可证使用，详见应用内“内容与词库来源”及“开源许可与致谢”。",
        ]),
        ("五、第三方商标与非隶属声明", [
            "“小鹤双拼”“小鹤音形”是小鹤（官网 https://flypy.cc）发布的输入方案名称，相关名称、标识及商标等权利归其权利人所有。本应用与小鹤及其权利人没有隶属、合作、授权或背书关系。",
            "本应用中的“小鹤双拼”仅指与该方案兼容的声母/韵母键位映射规则，由开发者依据公开汉语拼音规则独立实现；本应用不包含、不分发小鹤音形码表、小鹤官方软件或其词库，也不使用小鹤的标识。本应用词库来自开源项目雾凇拼音。",
            "如权利人认为本应用对上述名称或方案的使用存在不妥，请通过 " + ISSUES + " 联系，开发者将及时核实处理。",
            "iOS、iPhone、TestFlight、App Store、Safari 是 Apple Inc. 的注册商标；本应用与 Apple 没有隶属、合作或背书关系。",
        ]),
        ("六、适用法律与协议变更", [
            "本协议的解释与争议解决适用中华人民共和国法律（不含冲突法规则）；如你所在司法辖区存在不可排除的强制性消费者保护规定，则同时尊重该强制性规定。",
            "本协议如有更新，将在本页面与 App 内公布。继续使用本应用即视为接受更新后的协议。反馈渠道：" + ISSUES,
        ]),
    ]),
    ("sources", "内容与词库来源", [
        ("一、透明来源说明", [
            "Mosto键盘 坚持完全本机计算、不依赖云端词库。以下列出本应用内置词库、语法模型、词频表、表情名称与键位规则的原始出处与用途，便于用户与开源社区核验。",
        ]),
        ("二、中文词库与语言模型", [
            ["雾凇拼音 rime-ice：提供基础中文单字与常用词库（含经其收录整理的腾讯 AI Lab 公开中文词向量词表），并由 pypinyin 生成注音映射 — https://github.com/iDvel/rime-ice",
             "八股文 rime-octagram-data：提供词语搭配、短语直连与上下文联想语言模型 — https://github.com/lotem/rime-octagram-data",
             "万象语法模型 rime-wanxiang-data：提供离线整句 N-gram 蒸馏教师模型（与八股文双段合成单文件，全程本机 mmap 零网络）— https://github.com/amzxyz/rime-wanxiang-data"],
        ]),
        ("三、英文词频与表情数据", [
            ["wordfreq：提供公开英文词频统计表，用于中英混输时的英文候选排序 — https://github.com/rspeer/wordfreq",
             "Emojibase：提供标准 Unicode Emoji 列表、分组结构与版本元数据 — https://github.com/milesj/emojibase",
             "Unicode CLDR：提供 Emoji 的标准中文名称与检索关键词，用于本机表情联想 — https://github.com/unicode-org/cldr"],
        ]),
        ("四、拼音与键位规范及非背书声明", [
            "全拼与九宫格（T9）遵循《汉语拼音方案》及通用手机键盘数字字母映射；小鹤双拼键位兼容小鹤公开双拼键位布局，由开发者独立实现。",
            "上述公开数据、标准与开源项目的所有权及商标权归原机构或原作者所有；本应用仅作合规引用或依开源许可使用，不代表原机构或原作者对本应用的背书或合作关系。",
        ]),
    ]),
    ("licenses", "开源许可与致谢", [
        ("一、本应用开源许可", [
            "Mosto键盘 源代码依据 GNU General Public License v3.0（SPDX: GPL-3.0-only）开源发布。",
            "完整源代码与完整许可文本： " + REPO,
        ]),
        ("二、第三方开源组件与数据许可（SPDX）", [
            ["雾凇拼音 rime-ice — GPL-3.0-only — https://github.com/iDvel/rime-ice",
             "pypinyin（词库构建期注音工具）— MIT — https://github.com/mozillazg/python-pinyin",
             "八股文 rime-octagram-data — LGPL-3.0-only — https://github.com/lotem/rime-octagram-data",
             "万象语法模型 rime-wanxiang-data — CC-BY-4.0 — https://github.com/amzxyz/rime-wanxiang-data",
             "darts-clone（Double-Array Trie 构建库，仅构建期工具使用）— BSD-2-Clause — https://github.com/s-yata/darts-clone",
             "wordfreq（英文词频数据）— CC-BY-SA-4.0 — https://github.com/rspeer/wordfreq",
             "Emojibase — MIT — https://github.com/milesj/emojibase",
             "Unicode CLDR — Unicode-3.0 — https://github.com/unicode-org/cldr"],
            "各上游项目的完整版权声明与许可证全文见本应用代码仓库的 LICENSE 与 ThirdParty 目录。衷心感谢上述开源作者与社区维护者。",
        ]),
    ]),
    ("regulatory", "法规、备案与合规信息", [
        ("一、网络与备案合规说明", [
            "Mosto键盘 键盘扩展（.appex）全程离线运行，不发起任何网络连接；伴侣 App 亦不自建后台服务器、不提供账号注册或互联网信息发布服务，属于纯本地离线单机工具。",
            "如后续版本新增联网云同步或在线服务功能，开发者将在上线前依法完成对应地区的互联网信息服务（ICP）备案及公示。",
        ]),
        ("二、个人信息保护与平台合规", [
            ["中国法规遵从：遵循《中华人民共和国个人信息保护法》（PIPL）及《常见类型移动互联网应用程序必要个人信息范围规定》，零采集、零上传、零画像。",
             "Apple App Store 隐私规范：App Store 隐私营养标签申报为“不收集数据”（Data Not Collected），与本机实际代码行为保持一致（仓库内通过自动化离线门禁持续校验）。",
             "隐私清单声明：应用包内不包含第三方追踪域或跨 App 追踪接口，不请求 IDFA 广告标识符。"],
        ]),
        ("三、无生成式 AI 与算法推荐声明", [
            "本应用不接入任何大语言模型或生成式人工智能服务，亦不包含面向商业营销或信息流分发的个性化推荐算法；全部输入候选均由本机确定性词典检索与静态语言统计完成。",
        ]),
        ("四、关联产品与联系支持", [
            "同系列产品：《摸索台灯》（Mossling，0–3 岁亲子共玩与床头夜灯 iOS 应用），官网：" + MOSSLING_SITE,
            "问题反馈、合规垂询或权利通知：" + ISSUES,
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
                    stripped = b.rstrip("，。；")
                    tail = b[len(stripped):]
                    e = html.escape(a + sep) + f'<a href="{html.escape(stripped)}">{html.escape(stripped)}</a>{html.escape(tail)}'
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
nav a{{margin-right:14px;font-size:14px;display:inline-block;margin-bottom:4px}}
</style></head><body><main>
<nav><a href="index.html">Mosto键盘</a><a href="privacy.html">隐私政策</a><a href="terms.html">用户协议</a><a href="sources.html">内容与词库来源</a><a href="licenses.html">开源许可</a><a href="regulatory.html">法规与合规</a></nav>
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

INDEX_BODY = f"""<section><h2>纯离线小鹤双拼与全拼 iOS 键盘</h2>
<p>小鹤双拼 · 全拼 · 九宫格，按触点位置自动纠错，支持中英混输。OTTOSSOM 家族的 Moss、Otto 与 Mosto 陪你安静打字。</p>
<p>键盘扩展全程零联网，不读取剪贴板，不收集任何个人数据；你学过的词和触点习惯只留在你的设备上。</p></section>
<section><h2>启用方式</h2><p>安装后打开伴侣应用首页，或前往 设置 › 通用 › 键盘 › 键盘 › 添加新键盘 选择 Mosto键盘，长按地球键切换即可打字；不开启“允许完全访问”也能使用全部核心功能。</p></section>
<section><h2>支持与反馈</h2><p>欢迎在使用中反馈建议与问题：<a href="{ISSUES}">{ISSUES}</a></p></section>"""

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
    print("wrote docs/{index,privacy,terms,sources,licenses,regulatory}.html and App/LegalText.swift")

if __name__ == "__main__":
    main()
