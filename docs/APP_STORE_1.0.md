# Mosto键盘 v1.0 App Store Connect 逐项合规上架资料包

> 核对日期：2026-11-28 · 适用版本：iOS 1.0（参考基线 Build 433 / R106 收口版） · 开发者：温树垚（OTTOSSOM Studio）
> 规范依据：[Apple App Store Connect App Information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)、[Platform Version Information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)、[Screenshot Specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)。
> 商业法务原则：严格遵循顶级商用收敛规范，应用名、副标题、宣传文本、关键词与商店截图均**不出现**第三方方案商标词「小鹤」，仅在描述中以「可选双拼方案」中性呈现。

## 一、App 信息（App Information）

| App Store Connect 字段 | 限制 | 简体中文（主语言） | English (U.S.) | 校验状态 | 
| ----- | ----- | ----- | ----- | ----- | 
| **名称（Name）** | 2–30 字符 | `Mosto键盘` | `Mosto Keyboard` | 7 / 14 字符（通过） | 
| **副标题（Subtitle）** | ≤ 30 字符 | `纯离线全拼九宫格精准中文输入法` | `Offline Pinyin & T9 Keyboard` | 15 / 28 字符（通过） | 
| **套装 ID（Bundle ID）** | — | `app.mossling.keyboard` | `app.mossling.keyboard` | 与 Xcode 工程一致 | 
| **主要类别（Primary Category）** | 必选 | `效率`（Productivity） | `Productivity` | 推荐主类 | 
| **次要类别（Secondary Category）** | 可选 | `工具`（Utilities） | `Utilities` | 推荐副类 | 
| **内容版权（Content Rights）** | 必选 | 选「否，不包含、显示或访问第三方版权内容」（已合规署名开源数据） | No | 零 GPL / 纯 CC-BY-4.0 & MIT | 
| **年龄分级（Age Rating）** | 必选 | `4+`（全部内容问卷均选「无 / 否」） | `4+` | 预计 4+ | 
| **隐私政策网址（Privacy Policy URL）** | 必填 | `https://mosto-keyboard.pages.dev/privacy.html`（独立官网上线后填入） | 同左 | 须公开 HTTPS 可访问 | 
| **中国大陆 App 备案号** | 中国区必填 | 取得后填写；未取得前先不勾选中国大陆店面 | — | 不阻断海外首发 | 

## 二、版本页元数据（iOS 1.0 Version Information）

### 1. 简体中文（zh-Hans）— 直接粘贴

**宣传文本（Promotional Text，上限 170 字符，当前 79 字符）**

```
每天触碰三千次的键盘，值得安静与准确。开箱即用标准全拼与单手九宫格，本机触点纠错与千万级离线语料加持；不开「允许完全访问」照常打字，零联网、零广告、零云端上传。


```

**关键词（Keywords，上限 100 字符，当前 62 字符，英文逗号分隔无空格，不重复名称与副标题词）**

```
全拼,九宫格,中文输入法,拼音键盘,离线输入法,自动纠错,中英混输,双拼,隐私保护,无广告,手势输入,颜文字,T9


```

**应用描述（Description，上限 4000 字符，当前 728 字符，纯文本无 HTML/Emoji）**

```
每天被触碰最多次的交互面，值得与硬件同等级的准度、手势节奏与隐私边界。Mosto键盘是 OTTOSSOM Studio 出品的纯离线中文 iOS 键盘——安静、克制，所有输入计算 100% 在你的设备本机完成。

【全拼与九宫格主角体验】
开箱即用标准全拼全键盘与单手九宫格（T9），原生优化日常整句输入、首字母简拼（如 bzd、nh）与中英自然混输；九宫格提供左侧实时拼音微调与右侧同位符号面板，单手切换零学习成本。

【触点几何感知自动纠错】
结合手指在玻璃上的真实落点偏移与中文上下文语言模型，在不打扰正常打字的前提下自动扶正误触邻键、漏按、多按与顺手换位。空格上屏后在候选栏左侧保留一键撤回原键胶囊，改错了随时退回。

【双段本机离线语言引擎】
单文件双段内存映射架构（48.3 MB）将千万级开放语料蒸馏后的 2–4 元整句解码与上下文联想全部封装在本地，配合 41.3 万条中文词库与 4.4 万条英文词表，毫秒响应，无需网络等待。

【纯本机离线，不开「完全访问」也能完整使用】
iOS 的「允许完全访问」开关仅用于开启按键震动与系统按键音。即使保持关闭，全拼、九宫格、可选双拼、触点纠错与词语联想仍可完整使用。键盘扩展零联网、零剪贴板读取、零第三方统计 SDK。

【顺手手势与双材质高定外观】
- 标点轻上滑直出副符号、空格左右滑移游标与智能括号跳出；
- 左划退格快速清空、行内四则心算（输入 286/4= 直接出数）与相对日期联想；
- 横滑切页的 Emoji 与宽度自适应颜文字面板；
- 日光奶瓷、夜灯炭紫微扁平雕塑键帽与原生简洁玻璃态一键切换；
- 设置内提供可选双拼方案与键位练习，满足进阶用户需求。

【隐私承诺】
你输入的每一个字都只停留在你自己的设备上。Mosto键盘不会联网、不会读取剪贴板，也不会向任何服务器上传个人数据。


```

### 2. English (U.S.) — 直接粘贴

**Promotional Text（上限 170 字符，当前 157 字符）**

```
A quiet, 100% offline Chinese iOS keyboard built for Full Pinyin and 9-key T9. Touch-aware autocorrect, zero Full Access required, zero tracking, and zero ads.


```

**Keywords（上限 100 字符，当前 88 字符）**

```
pinyin,chinese keyboard,t9,offline keyboard,autocorrect,privacy,shuangpin,no ads,kaomoji


```

**Description（上限 4000 字符，当前 1094 字符）**

```
The surface you touch most often every day deserves hardware-grade precision, calm rhythm, and strict privacy boundaries. Mosto Keyboard by OTTOSSOM Studio is a 100% offline Chinese iOS keyboard crafted around Full Pinyin (QWERTY) and ergonomic 9-key T9, with an optional Shuangpin layout in Settings.

Key Features
- Mainstream Full Pinyin & 9-Key T9: Fast whole-sentence Full Pinyin decoding, initials shorthand, inline mixed Chinese-English typing, and one-handed 9-key T9 with live syllable tuning.
- Touch-Geometry-Aware Autocorrect: Combines spatial touch-offset modeling with a 48.3 MB on-device dual-section language model to correct adjacent-key slips, missed or extra taps, and transpositions, with one-tap undo right after Space.
- 100% Offline, No Full Access Required: All core typing, autocorrect, prediction, and emoji panels work completely without enabling "Allow Full Access". Zero network requests, zero clipboard reading, zero analytics SDKs.
- Tactile Craft & Expressive Gestures: Switch between sculpted Day Ceramic / Night Charcoal keycaps and clean native styling, slide Space to move the cursor, flick punctuation for secondary symbols, and swipe horizontally through Emoji and adaptive Kaomoji decks.

Privacy Promise
Every character you type stays strictly on your device. Mosto Keyboard never connects to the internet and never collects personal data.


```

### 3. 版本页其他必填项

| 字段 | 填写内容 | 
| ----- | ----- | 
| **技术支持网址（Support URL）** | `https://mosto-keyboard.pages.dev/#support` | 
| **营销网址（Marketing URL）** | `https://mosto-keyboard.pages.dev/` | 
| **版权（Copyright）** | `© 2026 温树垚`（或 `© 2026 OTTOSSOM Studio`） | 
| **版本号（Version）** | `1.0`（与 `MARKETING_VERSION = 1.0` 一致） | 
| **出口合规（Export Compliance）** | `ITSAppUsesNonExemptEncryption = NO`（已在工程配置，免交加密文档） | 
| **发布方式** | 手动发布此版本（Manual Release） | 

## 三、App 隐私（App Privacy）与销售范围

* **隐私营养标签**：选择 **「不，我们不从此 App 中收集数据」（Data Not Collected）**，与 `App/PrivacyInfo.xcprivacy` 及 `Keyboard/Resources/PrivacyInfo.xcprivacy` 完全一致。

* **价格**：免费，无应用内购买，无订阅，无广告。

* **销售范围建议**：

  * 首发（中国大陆备案前）：勾选中国香港、中国澳门、中国台湾、新加坡、马来西亚、澳大利亚、新西兰、美国、加拿大、英国、日本等主要海外地区；同时开启 TestFlight 外部公开链接供中国大陆用户抢先体验。

  * 欧盟地区：需在 App Store Connect 完成《数字服务法》（DSA）身份声明；个人免费非商业应用可声明为「非交易者（Non-Trader）」，或暂不勾选欧盟店面。

  * 中国大陆地区：完成备案或纯离线免备案确认后勾选上线。

## 四、App Review 审核信息（可直接粘贴）

| 字段 | 填写内容 | 
| ----- | ----- | 
| **登录要求** | 取消勾选「需要登录」（无需账号） | 
| **联系人** | 温树垚 | 
| **电话** | 填写负责人有效手机号（含国家区号，如 `+61 ...`） | 
| **电子邮件** | `lbuiuiysdeyzxl@yeah.net` | 

**审核备注（Review Notes，英文直贴）**

```
Thank you for reviewing Mosto Keyboard (Mosto键盘).

1. No Account & 100% Offline Architecture:
   Neither the companion app nor the keyboard extension requires an account or internet connection. The keyboard extension (.appex) makes zero network requests, performs zero clipboard reads, and contains zero third-party analytics or advertising SDKs.

2. No "Allow Full Access" Required:
   All core features—Full Pinyin (QWERTY), 9-key T9, optional Shuangpin layout, touch-offset autocorrect, dual-section on-device language model, and Emoji/Kaomoji panels—work completely without enabling "Allow Full Access". Enabling Full Access is strictly optional and only enables tactile haptics and system key click sounds.

3. How to Test:
   - Go to iOS Settings > General > Keyboard > Keyboards > Add New Keyboard > select "Mosto键盘".
   - Open Apple Notes or tap the native verification field on the companion app's Home tab, then switch to Mosto键盘 via the globe key.
   - Type Full Pinyin sentences (e.g., "nihao" -> "你好", or mistyped "jintianttianqihenhao" -> "今天天气很好").
   - Tap the top-right gear icon (or long-press the bottom-left Mosto key) inside the keyboard to toggle 9-key T9, optional Shuangpin, and Day/Night themes.

4. Open-Data Licensing:
   All bundled offline dictionaries and language models are derived strictly from commercial-friendly open datasets (CC-BY-4.0, MIT, Unicode-3.0) with zero copyleft/GPL dependencies. Full attributions are visible in the companion app's About tab.


```

## 五、苹果官方最大尺寸市场宣传图规范（Apple Official Maximum Specs）

依据 [Apple Developer Screenshot Specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)，**不采用最低达标尺寸，全部按苹果官方允许的最高像素上限制作**（App Store Connect 会自动向下高质量适配其余机型）：

| 平台类别 | 苹果官方最大尺寸（竖屏） | 苹果官方最大尺寸（横屏） | 格式与硬性合规要求 | 本项目是否必填 | 
| ----- | ----- | ----- | ----- | ----- | 
| **iPhone 6.9"（配备灵动岛大屏）** | **`1320 × 2868 px`** | `2868 × 1320 px` | PNG / JPEG，**严禁 Alpha 透明通道**，sRGB | **必填（iPhone 最高官方上限，本次已直接生成 5 张）** | 
| iPhone 6.5"（面容 ID 大屏） | `1284 × 2778 px` | `2778 × 1284 px` | 若已上传 6.9" `1320×2868`，系统自动缩放，无需重复上传 | 可选 | 
| iPhone 6.3"（配备灵动岛中屏） | `1206 × 2622 px` | `2622 × 1206 px` | 若已上传 6.9" `1320×2868`，系统自动缩放 | 可选 | 
| iPad 13" 显示屏 | `2064 × 2752 px` | `2752 × 2064 px` | 仅当 `TARGETED_DEVICE_FAMILY` 包含 iPad 时必填（当前工程为 `1` 即纯 iPhone） | 当前工程无需（纯 iPhone） | 

### 已生成的 5 张 `1320 × 2868 px` 纯 RGB 市场图清单（打包于 `mosto-v1-appstore-screenshots-1320x2868.zip`）

| 序号 | 文件名 | 尺寸与色彩模式 | 主标题 | 副标题 | 画面依据（Build 433 实机渲染） | 
| ----- | ----- | ----- | ----- | ----- | ----- | 
| 1 | `01_mosto_quanpin_autocorrect_1320x2868.png` | `1320×2868` RGB | 全拼顺手就准，偏键自动扶正 | 本机触点几何纠错，整句一遍过 | `day_letters_composing.png` + 暖瓷主视觉 | 
| 2 | `02_mosto_t9_onehand_1320x2868.png` | `1320×2868` RGB | 单手九宫格，一秒随手切 | 左侧实时拼音微调，中英自然混输 | `day_t9_composing.png` | 
| 3 | `03_mosto_offline_privacy_1320x2868.png` | `1320×2868` RGB | 不开完全访问，照常完整打字 | 纯本机离线，零联网零读剪贴板 | `day_app_privacy.png` + 零上传规格条 | 
| 4 | `04_mosto_craft_emoji_1320x2868.png` | `1320×2868` RGB | 雕塑键帽与横滑表情面板 | 日光奶瓷 / 夜灯炭紫双材质质感 | `day_emoji.png` + `night_forced_idle.png` | 
| 5 | `05_mosto_companion_family_1320x2868.png` | `1320×2868` RGB | 从指尖到书桌的安静伙伴 | 日光与夜灯切换，认识 OTTOSSOM 家族 | `day_app_home0.png` + `night_app_home0.png` | 
