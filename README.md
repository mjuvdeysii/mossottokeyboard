# Mosto键盘 · Mosto Keyboard（iOS）

![Mosto](docs/images/mosto_sheet.png)

以小鹤双拼为主（两键一字、小写字母输入）、兼容全拼的 iOS 第三方键盘，核心是 **按触点位置的自动纠错**：点偏到相邻键时，结合手指落点概率与词频，把首选纠正为最可能想打的词。

## 功能

| 项目 | 说明 |
|---|---|
| 自动纠错 | 高斯触点模型 + 词库联合解码；首选带下划线表示已纠错，第二候选为原文 |
| 个人习惯 | 记录常用词；学习手指相对键位中心的固定偏移 |
| 候选栏 | 只显示放得下的候选，不横向滚动；⌄ 展开全部候选（竖向） |
| 布局 | 按 Gboard iOS 实测尺寸（402 pt 屏宽）：工具栏 64、行距 53、键距 5.5×11；字母键不加数字角标 |
| 质感 | iOS 26 液态玻璃：键盘背景透明交给系统玻璃，圆角键帽；设置中可改为 Gboard 无边框样式 |
| 外观 | 日光 / 夜灯，与摸索台灯一致：自动跟随系统、固定日光、固定夜灯、晚上 19:00–6:00 自动夜灯 |
| 联想 | 上屏后推荐下一个词（3.9 万个词头、11 万条续写）；最后一个候选始终是输入的字母原文 |
| 输入方案 | 小鹤双拼与全拼（含简拼、半截音节），设置里切换；两种方案都按触点自动纠错 |
| Mosto | 键盘里的薰衣草紫小魔王（谐音“魔头”），空闲时待在候选栏左侧，点它打开设置；设定见 [docs/MOSTO.md](docs/MOSTO.md) |
| 符号 | 中/英两套 123、#+= 页面，与 Gboard 同排布，每页 ≤10 键/行，全部可见 |
| 手感 | 自绘按键、整块区域统一处理触摸、多指连按不丢字、按住空格左右拖动移光标（其余键帽变空白，拖得快移得多，按字符移动、表情不拆开）、删除长按加速 |
| 隐私 | 不联网；词库和学习数据只存在本机 |

## 发布到 TestFlight（自动）

推送到 `main` 后，GitHub Actions（`.github/workflows/ios.yml`）自动：编译 → 引擎基准测试 → 归档签名 → 上传 TestFlight。

一次性准备：
1. 本仓库 Settings › Secrets and variables › Actions 添加 `ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8`、`APPLE_TEAM_ID`（App Store Connect API 密钥，可与其他 App 共用）。
2. App Store Connect › App › ＋ 新建 App：平台 iOS，套装 ID `app.mossling.keyboard`（首次运行流程会自动注册该 ID 及扩展 ID `app.mossling.keyboard.ext`），名称与 SKU 自定。

构建报告推送到 `ci-logs`（编译）与 `ci-logs-testflight`（上传）分支。

## 本地安装到 iPhone

1. Mac 上用 Xcode 15 或更新版本打开 `MossOttoKeyboard.xcodeproj`，两个 target 的 Signing 选自己的 Team，真机 Run。
2. iPhone：设置 › 通用 › 键盘 › 键盘 › 添加新键盘 › 小鹤双拼。可选开启“允许完全访问”（仅用于震动与按键音）。

## 键位

- 空格：上屏首选　回车：上屏字母原文　删除：逐键回退
- 底行：`123` · ⚙︎ 设置 · `中/英` · 空格 · `，`（长按 `。`）· ↵
- 字母键不设长按；数字与符号在 `123` / `#+=` 页
- 设置：纠错开关、纠错强度、震动、按键边框、清空学习数据

## 目录

```
App/        容器 App（启用说明 + 试打）
Keyboard/   键盘扩展 UI（UIKit）
Engine/     解码引擎（纯 Swift，不依赖 UIKit，可在 macOS/Linux 测试）
EngineCLI/  引擎命令行测试与模拟触点基准
Tools/      词库构建、Xcode 工程生成脚本
```

## 引擎测试（macOS / Linux）

```sh
swiftc -O Engine/*.swift EngineCLI/main.swift -o /tmp/engine
/tmp/engine Keyboard/Resources/lexicon.bin type nihcdajx   # 查看候选
/tmp/engine Keyboard/Resources/lexicon.bin bench           # 模拟触点纠错基准
```

## 重新生成词库 / 工程

```sh
# 词库：rime-ice cn_dicts 的 8105.dict.yaml 与 base.dict.yaml
python3 Tools/build_lexicon.py 8105.dict.yaml base.dict.yaml -o Keyboard/Resources/lexicon.bin
# 增删源文件后重新生成 Xcode 工程
python3 Tools/gen_xcodeproj.py
```

## 许可

词库数据来自 [雾凇拼音 rime-ice](https://github.com/iDvel/rime-ice)（GPL-3.0），因此本项目整体按 GPL-3.0 发布，见 `LICENSE`。
