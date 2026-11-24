# Mosto键盘 App Store 1.0 提审资料包

## 1. 应用基础元数据（App Information & Version 1.0）

- **应用名称（简体中文）**：Mosto键盘
- **副标题（简体中文，30 字符内）**：小鹤双拼离线纠错键盘
- **应用名称（English）**：Mosto Keyboard
- **副标题（English，30 chars max）**：Offline Xiaohe Pinyin Keyboard
- **主分类**：效率（Productivity）
- **副分类**：工具（Utilities）
- **价格与内购**：免费，无应用内购买，无订阅，无广告
- **年龄分级**：4+
- **支持语言**：简体中文（键盘支持中英混输）
- **隐私政策页面**：仓库 GitHub Pages 的 `privacy.html`（对应 `docs/privacy.html`）
- **技术支持页面**：仓库 GitHub Pages 的 `index.html`（对应 `docs/index.html`）
- **使用条款页面**：仓库 GitHub Pages 的 `terms.html`（对应 `docs/terms.html`）
- **参考验证版本**：1.0 RC（R88，商业化三页签伴侣 App + OTTOSSOM 家族联动 + 原生统一固定键盘高度收官版）

## 2. 关键词（Keywords，100 字符以内）

- **简体中文**：小鹤双拼,双拼输入法,双拼键盘,全拼,九宫格,中文输入法,离线键盘,自动纠错,无广告,隐私键盘
- **English**：xiaohe,shuangpin,pinyin,chinese keyboard,offline keyboard,autocorrect,t9,privacy

## 3. 应用描述（Description）

### 简体中文

Mosto键盘是一款专注中文输入精准度与隐私安全的离线 iOS 键盘，原生支持小鹤双拼与全拼两种方案，并同时提供全键盘与九宫格布局。

**核心特性**

- **触摸几何感知自动纠错**：结合按键落点偏移模型与中文词库概率，在保持正常输入零打扰的同时，自动修正误触邻键、多按漏按与跨音节顺手换位。
- **小鹤双拼与全拼双引擎**：完整支持标准小鹤双拼（零辅助码、两键一字）与标准全拼（支持简拼与半音节预测），并支持句子内中英混输。
- **纯本机离线运行**：无需开启“允许完全访问”即可使用全部核心打字、纠错与词库联想功能。键盘扩展零网络请求、零剪贴板读取、零云端上传、零第三方统计 SDK。
- **行内心算与智能相对日期**：输入算式加等号（如 `286/4=`）候选栏直接给出精确结果，输入「明天」「上周一」「下周一」「上个月」「下个月」「今年」「现在」自动匹配对应日期与时间。
- **WebView 零卡顿与实时原字母槽**：`.appex` 零 `setMarkedText` XPC + 0-XPC 中文空格断句，保障 Safari 与网页富文本编辑器丝滑跟手；顶部左侧「实时原字母槽」按输入节奏展示真实按键流（小鹤 2 键微隙 + 长串右锚定左渐隐 + 1.5pt 输入光标线，展开宫格时顶栏全宽展示），轻点即可原样上屏字母；内置 CoreText 非 BMP 生僻字形过滤，候选栏彻底告别缺字豆腐块。
- **全键盘标点轻上滑与四档线性触感**：中文「，」与英文「.」等带副符号按键支持轻上滑瞬出副符号（无需等待长按）；普通字母 0.66 `.light` 轻脆反馈与空格/回车/删除 0.78 `.rigid` 机械锚定感分层调校。
- **高定哑光双材质视觉与高密度单行候选**：Mosto 主题采用零重影单层超椭圆雕塑键帽（日光奶瓷白 + 暖哑金 / 夜灯深曜石炭紫，配 4.5pt 硬件微灯珠与空格盲打凹痕）与顶栏 28pt 一体 Mosto 胶囊（内置 228 条颜文字）；简洁风格完整复刻 iOS Liquid Glass；配合高速自适应无闪反馈（连打 `<130ms` 抑制遮挡气泡）与高密度 42pt 单行候选栏，展开候选宫格支持「单字」一键速筛。
- **工程级质量门禁实测（基于引擎回归基准）**：
  - 全拼自动纠错与顺手换位句级基准：`transpose.sentences` Top-1 59.21%（Top-3 67.11%）
  - 小鹤双拼核心指标均受 CI 自动化质量门禁保护（包含触控噪声词级/句级准确率、误纠率 <= 1.0%、平均解码时延 <= 3.0 ms、中英混输与冷启动联想时延）

**隐私承诺**

你输入的每一个字都只停留在你自己的设备上。Mosto键盘不会联网、不会上传输入记录、也不会追踪任何个人数据。

### English

Mosto Keyboard is a privacy-first, completely offline Chinese iOS keyboard built for Xiaohe Shuangpin and Full Pinyin, supporting both QWERTY and 9-key (T9) layouts.

**Key Features**

- **Touch-Geometry-Aware Autocorrect**: Combines spatial touch-offset modeling with a local Chinese language model to fix adjacent-key slips, missed/extra taps, and key transpositions without disrupting clean typing.
- **Xiaohe Shuangpin & Full Pinyin**: Native support for standard Xiaohe Shuangpin (2 keys per syllable) and Full Pinyin, including inline mixed Chinese-English typing.
- **100% Offline, Zero Full Access Required**: Works out of the box without enabling "Allow Full Access". No network calls, no clipboard reading, no cloud telemetry, and no third-party analytics SDKs.
- **Refined Tactile Design**: Switch between 3D sculpted keycaps and Liquid Glass styling with automatic Light/Dark mode support, crisp key sound, and haptic feedback.

## 4. 隐私营养标签（App Privacy Nutrition Label）

- **数据收集声明**：**不收集数据（Data Not Collected）**
- **追踪声明**：不用于跨应用或跨网站追踪
- **隐私清单对应文件**：`App/PrivacyInfo.xcprivacy`
- **工程自动化校验**：每次 CI 构建均运行 `Tools/check_offline.py` 静态扫描，强制拦截网络 API、剪贴板读取与追踪相关调用。

## 5. App Review 审核备注（English）

```text
Thank you for reviewing Mosto Keyboard (Mosto键盘).

1. No Account Required:
   The app and keyboard extension require no sign-in, no account, and no network connection.

2. No "Allow Full Access" Required:
   The keyboard extension operates 100% offline using an on-device lexicon and touch-offset autocorrect engine. All core typing, Xiaohe Shuangpin / Full Pinyin switching, 9-key / QWERTY layouts, and autocorrect features work completely without enabling "Allow Full Access".

3. How to Test:
   - Open Settings > General > Keyboard > Keyboards > Add New Keyboard > select "Mosto键盘".
   - Open Notes or the companion app's Home tab (`伴侣`), tap the native verification field (`真机键盘验证`), and switch to Mosto键盘 using the globe key.
   - Try typing Xiaohe Shuangpin (e.g., "nihc" -> "你好", or slipped "jbtmtmqohfhc" -> "今天天气很好") or hold the emoji key on the keyboard to adjust Full Pinyin / T9, appearance, and feedback inside the keyboard console.

4. Privacy & Offline Architecture:
   The keyboard extension performs zero network requests, zero clipboard access, and zero analytics tracking.
```

## 6. App Store 5 张商店截图分镜（6.9" / 6.7" iPhone）

| 序号 | 主标题 | 副标题 | 画面构图与展示重点 | 视觉规范 |
| --- | --- | --- | --- | --- |
| 1 | 小鹤双拼，顺手就准 | 离线触摸纠错，不打断你的节奏 | 顶部居中展示手机真机框，输入框演示误触/换位输入实时纠错为正确整句，键盘区高亮当前键位与候选条 | 暖白底色 `#FBF8F2`，主字深靛紫 `#2B1961`，点缀金 `#FFC45A`，零 Emoji |
| 2 | 不开完全访问，也能完整打字 | 零联网、零上传、零广告 | 居中展示系统键盘启用步骤与离线隐私徽标卡片，底部配局部键盘特写，强调纯本机词库运行 | 与隐私页同色系卡片留白构图，信息层级清晰，单屏无冗余文案 |
| 3 | 小鹤与全拼，全键与九宫格 | 一键切换你最熟悉的中文输入方式 | 左右双机错层或上下分屏对比：展示小鹤双拼全键盘与九宫格（T9）布局及中英混输候选效果 | 清晰展示按键字母排布与候选栏，突出可读性与低门槛切换 |
| 4 | 双材质键盘美学 | 3D 实体键帽与 Liquid Glass 随心切换 | 对角线切分或双卡片同屏对比浅色 3D 实体键帽质感与深色 Liquid Glass 质感，呈现精致光影细节 | 真实渲染界面截图，严禁过度滤镜或失真装饰 |
| 5 | 你的离线桌面伴侣 | 真实键盘启用指引 + 小鹤双拼指法图谱 | 展示伴侣 App 首页 OTTOSSOM 家族（Moss、Otto 与 Mosto）桌面互动、系统键盘真机验证区与小鹤双拼指法图谱 | 保持原生 iOS 三页签实际 UI 比例与留白构图，零假沙盒 |

## 7. 提审前最终自检清单（R88 1.0 RC 收尾核对）

- [x] **CI 与 SDK 链路核查**：`build` 任务运行于 `macos-15`（`Xcode 26.3 / 17C529`，iOS 26 SDK）负责全量编译、模拟器快照、Keyboard Test Bench 与引擎质量门禁；`testflight` 任务运行于 `xcode-27`（iOS 27 SDK）负责 Release 归档、自动云端签名与上传 TestFlight。
- [x] **签名与容器边界**：`.xcodeproj` 零签名改动、零新增 `.entitlements`，`App/PrivacyInfo.xcprivacy` 与 `Keyboard/Resources/PrivacyInfo.xcprivacy` 声明完整，`ITSAppUsesNonExemptEncryption = NO`。
- [x] **静态门禁全绿**：`Tools/check_offline.py`、`Tools/check_no_sync_tap.py` 与 `Tools/check_ios_keyboard_rules.py`（17 条工程红线）全量通过。
- [x] **1.0 RC 核心体验与合规打磨（R35–R88）**：商业化原生三页签伴侣 App（伴侣 / 指南 / 关于）、OTTOSSOM Moss+Otto+Mosto 同台联动与手机音量检查提示、真实系统输入框验通、移除易引起宿主抖动的动态多档高度并锁定单一生效原生标准高度（258 pt 竖屏 / 198 pt 横屏，彻底消除微信顶部空档与全屏拉伸）、消费级隐私说明、`ThirdParty/` 全套 6 份开源许可齐备、零重影单层雕塑键帽、两阶段引擎加载与全链路 0 阻塞 XPC。
- [ ] 核对 App Store Connect 中隐私政策 URL、技术支持 URL 与 `docs/privacy.html`、`docs/index.html` 线上可访问性。
- [ ] 核对 App Store Connect 隐私标签已勾选“不收集数据（Data Not Collected）”。
- [ ] 使用真机（未开启“允许完全访问”）完整复测小鹤双拼、全拼、九宫格、成对标点联动删除与中英混输。
- [ ] 在 TestFlight 最新绿灯构建上截取 6.9" / 6.7" 商店 5 图并提交 App Review。
