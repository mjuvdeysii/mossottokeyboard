# iOS 26/27 自定义键盘扩展工程铁律（事前防线）

> 目标：**把 iOS 键盘扩展（`UIInputViewController` / `UITextDocumentProxy` / CoreAnimation / XPC / Jetsam）的平台硬限制写成自动化静态门禁（`Tools/check_ios_keyboard_rules.py`），在提交与 CI 阶段直接拦住问题，而不是等真机出现卡顿、崩溃或光标错位再去补救。**

## 1. XPC 跨进程通信预算（防非微信 App 打字卡顿）
- `UITextDocumentProxy.documentContextBeforeInput` 与 `documentContextAfterInput` 是**同步跨进程 XPC**。在原生 `UITextView`（微信）下约 0.5 ms，但在 Safari、`WKWebView`、备忘录富文本、Flutter/Electron 宿主中单次可达 **8–25 ms**。
- **铁律**：
  1. 组合打字态（`!taps.isEmpty`）每键 **0 次**额外 `documentContext` 读取（`refresh()` 与 `handle()` 末尾禁止无条件读上下文）。
  2. 仅在起打首键（`taps.isEmpty`）读取一次左上下文送入引擎；空格拖动光标在 `.began` 一次性快照后本地按 Swift `Character` 步进。
  3. `viewWillDisappear` 失焦瞬间禁止同步读取 `documentContextBeforeInput` 或同步写 `UserDefaults`。

## 2. CoreAnimation 渲染与帧率红线（120Hz ProMotion 零掉帧）
- **铁律**：
  1. **严禁对 `shadowPath == nil` 的图层设置 `shadowOpacity > 0`**——CoreAnimation 会对全部 30 枚键帽每帧执行离屏 Alpha 阴影光栅化，直接拖垮帧率并推高脏内存。
  2. **严禁在 `KeyView.pressed` 热路径上创建 `CABasicAnimation` / `CADisplayLink`**——高频连打与 3,600 键压测会造成渲染管线竞争或主线程抖动。
  3. 键盘收起/离窗（`viewWillDisappear` / `viewDidDisappear` / `didMoveToWindow(nil)`）后必须 **0 后台定时器、0 无限循环动画、0 额外震动引擎保活**。

## 3. 主线程零阻塞与点击必达（防 Watchdog 与“点首选不上屏”）
- **铁律**：
  1. 候选点击路径（`candidateTapped` / `select`）严禁同步等待引擎（由 `Tools/check_no_sync_tap.py` 强制门禁）。
  2. 引擎与词库文件（`lexicon.bin`、`english.bin`、`grammar.gram`、`sentence.gram`）全部在后台串行队列以只读 `mmap`（`PROT_READ, MAP_PRIVATE`）加载，不计入脏内存。
  3. 空格提交的 `decodeWithTimeout` 必须先走锁保护缓存微秒级快路径，超时上限不超过 `25 ms`，冷启动未就绪直接降级 `commitRaw()`。

## 4. 宿主光标与手势隔离（防乱跳光标与破坏宿主滑动）
- **铁律**：
  1. **严禁调用 `setMarkedText("", selectedRange: NSRange(location: 0, length: 0))`**——在 WebView / 富文本编辑器中会把光标拉偏到文档开头；清理组合态应使用 `insertText("")` + `unmarkText()`。
  2. 成对标点在 `.appex` 扩展内禁止同帧 `insertText` 后立刻 `adjustTextPosition(-1)`，必须延迟校验后缀与按键代次后再回退。
  3. **严禁遍历 `view.window` 或 `superview` 篡改系统/宿主手势识别器**，只允许调整键盘自身视图树内的手势。

## 5. Jetsam 45 MB 脏内存与隐私红线
- **铁律**：
  1. 可重建缓存（`emoji_hints.txt`、`compactReadings`、隐藏的 `EmojiPanelView`）必须惰性加载，并在 `didReceiveMemoryWarning` 与 `viewDidDisappear` 主动释放。
  2. 严禁引入 `NSExpression`（Objective-C 异常崩溃风险）、网络 API、剪贴板读取或未授权共享容器（由 `Tools/check_offline.py` 强制门禁）。
  3. 严禁私自修改 `.xcodeproj` 签名配置或新增 `.entitlements`。

## 6. 自动化静态门禁
每次 CI（`.github/workflows/ios.yml`）与本地提交前自动执行：
```sh
python3 Tools/check_no_sync_tap.py Keyboard/KeyboardViewController.swift
python3 Tools/check_offline.py .
python3 Tools/check_ios_keyboard_rules.py Keyboard
```
