# 小鹤双拼键盘（iOS）

纯小鹤双拼（两键一字、小写字母输入）的 iOS 第三方键盘，核心是 **按触点位置的自动纠错**：点偏到相邻键时，结合手指落点概率与词频，把首选纠正为最可能想打的词。

## 功能

| 项目 | 说明 |
|---|---|
| 输入方案 | 小鹤双拼，无形码、无辅助码；一字两键 |
| 自动纠错 | 高斯触点模型 + 词库联合解码；首选带蓝色下划线表示已纠错，第二候选为原文 |
| 个人习惯 | 记录常用词；学习手指相对键位中心的固定偏移 |
| 候选栏 | 只显示放得下的候选，不横向滚动；⌄ 展开全部候选（竖向） |
| 符号 | 中/英两套 123、#+= 页面，每页 ≤10 键/行，全部可见 |
| 手感 | 自绘按键、整块区域统一处理触摸、多指连按不丢字、空格拖动移光标、删除长按加速 |
| 隐私 | 不联网；词库和学习数据只存在本机 |

## 安装到 iPhone

1. Mac 上用 Xcode 15 或更新版本打开 `MossOttoKeyboard.xcodeproj`。
2. 两个 target（`MossOttoKeyboard`、`MossOttoKeyboardExt`）的 **Signing & Capabilities** 里选自己的 Team。若提示 Bundle ID 已被占用，把 `com.mossotto.keyboard` 改成自己的前缀（扩展须保持 `<主 App ID>.ext`）。
3. 选择 iPhone 真机，Run。
4. iPhone：设置 › 通用 › 键盘 › 键盘 › 添加新键盘 › 小鹤双拼。可选开启“允许完全访问”（仅用于震动与按键音）。

## 键位

- 空格：上屏首选　回车：上屏字母原文　删除：逐键回退
- `中/英`：切换中文/英文　`123`、`#+=`：数字与符号
- 长按首行字母：数字；长按其他字母：常用符号；长按 `，` `。`：`？` `！`
- 候选栏空闲时 ⚙︎：设置（纠错开关、纠错强度、震动、清空学习数据）

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
