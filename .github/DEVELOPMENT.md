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
# 1. 下载万象语言模型原表（约 373 MB，CC-BY-4.0）并准备万象辞典 zi/jichu/duoyin/diming/en.dict.yaml
bash Tools/fetch_sentence_model.sh /tmp/wanxiang-lts-zh-hans.gram

# 2. 构建纯 CC-BY-4.0 中文词库（输出 lexicon.bin、.codes.txt，并导出单字权重 /tmp/zi_standalone.tsv）
python3 Tools/build_lexicon.py \
  --wanxiang-dir /tmp/wanxiang-dicts \
  --gram /tmp/wanxiang-lts-zh-hans.gram \
  --demote Tools/data/demote.txt \
  --zi-out /tmp/zi_standalone.tsv \
  -o Keyboard/Resources/lexicon.bin

# 3. 蒸馏双段 8-bit 量化语言模型 Mosto::GramV2（<= 48.50 MiB）
python3 Tools/distill_grammar.py \
  --source /tmp/wanxiang-lts-zh-hans.gram \
  --lexicon Keyboard/Resources/lexicon.bin \
  --zi /tmp/zi_standalone.tsv \
  --out Keyboard/Resources/grammar.gram

# 4. 英文词表（SymSpell MIT + 万象 en.dict.yaml CC-BY-4.0）→ 内存映射二进制
python3 Tools/build_english.py --symspell /tmp/symspell_en_82k.txt --wanxiang-en /tmp/wanxiang-dicts/en.dict.yaml
python3 Tools/build_english_bin.py

# 5. 增删源文件后重新生成 Xcode 工程
python3 Tools/gen_xcodeproj.py
```

## 合规与公开测试

- 隐私政策、用户协议与免责声明、开源许可：一份文本 `Tools/build_legal.py`，生成 App 内页面（`App/LegalText.swift`）与网页版（`docs/*.html`）。改文字后运行 `python3 Tools/build_legal.py`。
- 网页版由 GitHub Pages 发布（仓库 Settings › Pages › Branch: main，文件夹 /docs），隐私政策网址：https://mjuvdeysii.github.io/mossottokeyboard/privacy.html
- 隐私清单：`App/PrivacyInfo.xcprivacy` 与 `Keyboard/Resources/PrivacyInfo.xcprivacy`（不追踪、不收集数据；UserDefaults CA92.1、文件时间戳 C617.1）。
- 出口合规：`ITSAppUsesNonExemptEncryption = NO`（不使用加密）。

## 留出测试集

`EngineCLI/sentences3.tsv`（185 句）不参与任何调参，只用于验证改动是否真的变好：
`SENTENCES=EngineCLI/sentences3.tsv EngineCLI <lexicon.bin> bench 0.22`（`PERFECT_DEBUG=1` 列出打错的句子）。
`EngineCLI/sentences4.tsv`（158 句，运营 / 育儿 / 摄影 / 日语 / 日常，pypinyin 生成后人工校对多音字）是第二个留出集，同样只用于验证。
门禁另含：多按一键 / 漏按一键（全拼）整句首选、中英混输句子、自造词（单打 / 句中）。

联想质量：`SEG=<按词切分的句子文件> EngineCLI <lexicon.bin> predbench`（只在词边界处计分：下一个词是否在前六个联想里）。
