# 开发与发布

仓库维护说明（构建、发布、测试、数据生成、合规材料），不在仓库首页展示。

## 发布到 TestFlight（自动）

推送到 `main` 后，GitHub Actions（`.github/workflows/ios.yml`）自动：编译 → 引擎基准测试 → 归档签名 → 上传 TestFlight。

一次性准备：
1. 本仓库 Settings › Secrets and variables › Actions 添加 `ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8`、`APPLE_TEAM_ID`（App Store Connect API 密钥，可与其他 App 共用）。
2. App Store Connect › App › ＋ 新建 App：平台 iOS，套装 ID `app.mossling.keyboard`（首次运行流程会自动注册该 ID 及扩展 ID `app.mossling.keyboard.ext`），名称与 SKU 自定。

构建报告推送到 `ci-logs`（编译）与 `ci-logs-testflight`（上传）分支。

## 本地安装到 iPhone

1. Mac 上用 Xcode 15 或更新版本打开 `MossOttoKeyboard.xcodeproj`，两个 target 的 Signing 选自己的 Team，真机 Run。
2. iPhone：设置 › 通用 › 键盘 › 键盘 › 添加新键盘 › Mosto键盘。可选开启“允许完全访问”（仅用于震动与按键音）。

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
# 词库：rime-ice cn_dicts 的 8105、base、ext 与 tencent（tencent 只有文字，先用 pypinyin 注音）
python3 Tools/tencent_pinyin.py tencent.dict.yaml tencent_py.dict.yaml     # 需 pip install pypinyin（MIT）
python3 Tools/build_lexicon.py 8105.dict.yaml base.dict.yaml ext.dict.yaml tencent_py.dict.yaml -o Keyboard/Resources/lexicon.bin
# 语言模型：rime-octagram-data（hans 分支）的 zh-hans-t-essay-bgw.gram，原样复制
cp zh-hans-t-essay-bgw.gram Keyboard/Resources/grammar.gram
# 英文词表：Tools/data/english.txt（Tools/build_english.py 生成）→ 内存映射的二进制
python3 Tools/build_english_bin.py
# 增删源文件后重新生成 Xcode 工程
python3 Tools/gen_xcodeproj.py
```

## 合规与公开测试

- 隐私政策、用户协议与免责声明、开源许可：一份文本 `Tools/build_legal.py`，生成 App 内页面（`App/LegalText.swift`）与网页版（`docs/*.html`）。改文字后运行 `python3 Tools/build_legal.py`。
- 网页版由 GitHub Pages 发布（仓库 Settings › Pages › Branch: main，文件夹 /docs），隐私政策网址：https://mjuvdeysii.github.io/mossottokeyboard/privacy.html
- 隐私清单：`App/PrivacyInfo.xcprivacy` 与 `Keyboard/Resources/PrivacyInfo.xcprivacy`（不追踪、不收集数据；UserDefaults CA92.1、文件时间戳 C617.1）。
- 出口合规：`ITSAppUsesNonExemptEncryption = NO`（不使用加密）。
