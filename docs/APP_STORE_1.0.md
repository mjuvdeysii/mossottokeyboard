# Mosto键盘 App Store 1.0 提审资料包

## 1. 应用基础元数据（App Information & Version 1.0）

- **应用名称（简体中文）**：Mosto键盘
- **副标题（简体中文，30 字符内）**：全拼九宫格离线精准中文键盘
- **应用名称（English）**：Mosto Keyboard
- **副标题（English，30 chars max）**：Offline Pinyin & T9 Keyboard
- **主分类**：效率（Productivity）
- **副分类**：工具（Utilities）
- **价格与内购**：免费，无应用内购买，无订阅，无广告
- **年龄分级**：4+
- **支持语言**：简体中文（键盘支持中英混输）
- **隐私政策页面**：`https://mossotto.pages.dev/privacy.html`（对应 `docs/privacy.html`）
- **技术支持页面**：`https://mossotto.pages.dev/#support`（对应 `docs/index.html#support`）
- **使用条款页面**：`https://mossotto.pages.dev/terms.html`（对应 `docs/terms.html`）
- **品牌官网主页**：`https://mossotto.pages.dev/`
- **参考验证版本**：1.0 RC（R100.5，全拼+九宫格大众定位重构、双段离线语法引擎、横滑表情与自适应颜文字、升级版《桌边夜行》彩蛋与商业化法务官网）

## 2. 关键词（Keywords，100 字符以内）

- **简体中文**：全拼输入法,九宫格输入法,中文输入法,拼音键盘,离线键盘,自动纠错,中英混输,小鹤双拼,隐私键盘,无广告
- **English**：pinyin,chinese keyboard,t9,offline keyboard,autocorrect,privacy,shuangpin,xiaohe,no ads

## 3. 应用描述（Description）

### 简体中文

每天被触碰最多次的交互面，值得与硬件同等级的准度、手势节奏与隐私边界。Mosto键盘是 OTTOSSOM Studio 打造的纯离线中文 iOS 键盘——由屏幕里的 Mosto 出发，把安静可靠的输入手感延续到书桌上的 Moss 与 Otto（《摸索台灯》）。

开箱即用标准全拼全键盘与九宫格（T9）全拼，同时为高阶双拼用户内置完整小鹤双拼键位，所有解码、纠错与联想 100% 在设备本机完成。

**核心特性**

- **大众全拼与九宫格主角体验**：原生优化全拼整句输入、首字母简拼（如 `bzd`）与中英混输；九宫格模式支持单手顺滑打字、左侧实时拼音微调与右侧同位分类符号面板。
- **触摸几何感知自动纠错**：结合手指真实落点偏移与中文词库统计，在零打扰的前提下自动修正误触邻键、多按漏按与跨音节顺手换位，空格上屏后支持一键撤回原键。
- **双段本机离线语言引擎**：单文件双段内存映射架构，在极小本机空间内兼顾千万级语料蒸馏后的 2–4 元整句排序与自然上下文联想，毫秒响应零网络等待。
- **纯本机离线，无需“完全访问”**：不开启“允许完全访问”即可完整使用全拼、九宫格、小鹤双拼、纠错与联想。键盘扩展零联网、零剪贴板读取、零云端上传、零第三方统计 SDK。
- **顺手手势、心算与横滑表情面板**：支持标点轻上滑副符号、空格滑移游标与智能括号跳出、行内四则心算（`286/4=`）与相对日期；Emoji 与 Mosto 颜文字面板支持左右横滑切页与宽度自适应排版。
- **双材质高定外观与兼顾小鹤双拼**：在实体雕塑键帽（日光奶瓷 / 夜灯炭紫）与原生 Liquid Glass 风格间一键切换，并在指南二级页面提供小鹤双拼练习与键位图谱。

**隐私承诺**

你输入的每一个字都只停留在你自己的设备上。Mosto键盘不会联网、不会读取剪贴板，也不会追踪任何个人数据。

### English

The surface you touch most often every day deserves hardware-grade precision, effortless gesture rhythm, and strict privacy boundaries. Mosto Keyboard by OTTOSSOM Studio is a 100% offline Chinese iOS keyboard built around Full Pinyin (QWERTY & 9-key T9), with optional Xiaohe Shuangpin support.

**Key Features**

- **Mainstream Full Pinyin & 9-Key T9**: Fast whole-sentence Full Pinyin decoding, initials shorthand, inline mixed Chinese-English typing, and ergonomic one-handed 9-key T9 with live syllable tuning.
- **Touch-Geometry-Aware Autocorrect**: Combines spatial touch-offset modeling with an on-device language model to fix adjacent-key slips, missed/extra taps, and key transpositions without interrupting clean typing.
- **100% Offline, Zero Full Access Required**: Works out of the box without enabling "Allow Full Access". Zero network requests, zero clipboard reading, zero cloud telemetry, and zero third-party SDKs.
- **Refined Tactile Craft & Horizontal Emoji Deck**: Switch between 3D sculpted ceramic/obsidian keycaps and Liquid Glass styling, swipe horizontally through Emoji categories and adaptive-width Kaomoji moods, and discover Moss & Otto from OTTOSSOM's companion world.

## 4. 隐私营养标签（App Privacy Nutrition Label）

- **数据收集声明**：**不收集数据（Data Not Collected）**
- **追踪声明**：不用于跨应用或跨网站追踪
- **隐私清单对应文件**：`App/PrivacyInfo.xcprivacy`、`Keyboard/Resources/PrivacyInfo.xcprivacy`
- **工程自动化校验**：每次 CI 构建均运行 `Tools/check_offline.py` 静态扫描，强制拦截网络 API、剪贴板读取与追踪相关调用。

## 5. App Review 审核备注（English）

```text
Thank you for reviewing Mosto Keyboard (Mosto键盘).

1. No Account Required:
   The app and keyboard extension require no sign-in, no account, and no network connection.

2. No "Allow Full Access" Required:
   The keyboard extension operates 100% offline using an on-device lexicon, dual-section offline grammar model, and touch-offset autocorrect engine. All core typing, Full Pinyin / 9-key T9 / Xiaohe Shuangpin switching, and autocorrect features work completely without enabling "Allow Full Access".

3. How to Test:
   - Open Settings > General > Keyboard > Keyboards > Add New Keyboard > select "Mosto键盘".
   - Open Notes or the companion app's Home tab (`伴侣`), tap the native verification field (`真机键盘验证`), and switch to Mosto键盘 using the globe key.
   - Try typing Full Pinyin (e.g., "nihao" -> "你好", or slipped "jintianttianqihenhao" -> "今天天气很好"), or tap the top-right gear / hold the bottom-left Mosto key to switch to 9-key T9, Xiaohe Shuangpin, appearance, and feedback inside the keyboard console.

4. Privacy & Offline Architecture:
   The keyboard extension performs zero network requests, zero clipboard access, and zero analytics tracking.
```

## 6. App Store 5 张商店截图分镜（6.9" / 6.7" iPhone）

| 序号 | 主标题 | 副标题 | 画面构图与展示重点 | 视觉规范 |
| --- | --- | --- | --- | --- |
| 1 | 全拼顺手就准，偏键也能读对 | 本机触点纠错，整句一遍过 | 顶部居中展示手机真机框，输入框演示全拼整句与偏键/漏键输入实时纠错为正确汉字，键盘高亮按压与候选条撤回原键胶囊 | 暖白底色 `#F7F4EE`，主字深墨 `#1E192B`，点缀紫 `#633EBF` 与暖金 `#D69A34`，零 Emoji |
| 2 | 全拼全键盘与九宫格，一秒随手切 | 单手九宫格顺打 + 左侧拼音微调 | 双机错层对比展示标准全拼全键盘与九宫格（T9）布局、左侧动态拼音列与中英自然混输候选 | 清晰展示按键排布与候选栏，突出日常大众低门槛上手体验 |
| 3 | 不开完全访问，也能完整打字 | 纯本机离线，零联网、零读剪贴板 | 居中展示系统键盘启用指引与隐私承诺卡片，底部配局部键盘特写，明确传达不授权照常打字、不上传任何内容 | 与官网一致的暖瓷卡片留白构图，信息层级简洁克制 |
| 4 | 双材质键盘与横滑颜文字 | 实体雕塑键帽、Liquid Glass 与流式表情栏 | 上半部分双卡展示日光奶瓷实体键帽与深色夜灯玻璃态切换，下半部分特写横向切页 Emoji 与宽窄自适应颜文字网格 | 真实渲染界面，严禁过度滤镜或失真装饰 |
| 5 | 从指尖到书桌的桌面伙伴 | OTTOSSOM IP 家族与《摸索台灯》彩蛋 | 展示伴侣 App 首页 Moss、Otto 与 Mosto 三位伙伴同台互动、拉绳切换夜灯与输入指南卡片 | 保持原生 iOS 三页签实际 UI 比例与留白构图，零假沙盒 |

## 7. 提审前最终自检清单（1.0 终版核对）

- [x] **CI 与 SDK 链路核查**：`build` 任务运行于 `macos-15` 负责全量编译、快照与引擎质量门禁；`testflight` 任务运行于 `xcode-27` 负责 Release 归档、自动云端签名与上传 TestFlight。
- [x] **签名与容器边界**：`.xcodeproj` 零签名改动、零新增 `.entitlements`，`App/PrivacyInfo.xcprivacy` 与 `Keyboard/Resources/PrivacyInfo.xcprivacy` 声明完整，`ITSAppUsesNonExemptEncryption = NO`。
- [x] **静态门禁全绿**：`Tools/check_offline.py`、`Tools/check_no_sync_tap.py` 与 `Tools/check_ios_keyboard_rules.py` 全量通过。
- [x] **商业化与合规收口**：隐私政策、用户协议与第三方致谢与合规声明收敛为 3 项清晰入口，品牌链接统一指向 `https://mossotto.pages.dev/` 与 `#support`，伴侣 App 前台无个人账号或开源协议噪音。
- [ ] 核对 App Store Connect 中隐私政策 URL（`https://mossotto.pages.dev/privacy.html`）、技术支持 URL（`https://mossotto.pages.dev/#support`）线上可访问性。
- [ ] 核对 App Store Connect 隐私标签已勾选“不收集数据（Data Not Collected）”。
- [ ] 使用真机（未开启“允许完全访问”）完整复测全拼、九宫格、小鹤双拼、横滑 Emoji/颜文字与中英混输。
- [ ] 在 TestFlight 最新绿灯构建上截取 6.9" / 6.7" 商店 5 图并提交 App Review。
