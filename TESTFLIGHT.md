本版要点 (Mosto键盘 1.0 · R43 Safari / 网页富文本零卡顿与零跳光标终极优化版)
· 彻底攻克 Safari / 手机网页版 Antigravity / WKWebView 富文本输入框打字卡顿与光标移位：
  1. 候选栏内聚拼音预编辑（0 次 setMarkedText XPC）：在真机键盘扩展中采用与微信输入法 / 仓输入法（Hamster）一致的候选栏顶部拼音预编辑架构，打拼音、改拼音、退格删拼音全程 100% 在键盘进程内 < 1ms 完成，不再每按一字母就跨 3 个进程（键盘 ↔ Safari ↔ WebContent DOM）触发网页 compositionupdate 重排与光标偏移；仅在点击候选或空格确认上屏时发送单次干净的 insertText。
  2. 消除连续打词间 6–11 次 XPC 回声风暴：新增 lastHostWriteTime（180ms 写入回声过滤）与 lastCommittedContext 本地上下文复用，连续中文输入从起手到上屏全程 0 次同步 documentContextBeforeInput/AfterInput XPC 阻塞。
  3. 消除每词上屏后的缓存重解析风暴：移除 select() 热路径上误触发磁盘写入与 1,200 行 emoji_hints.txt 重解析的 engine.trim()，仅在离屏与内存警告时回收缓存。
· 候选栏全高度（42pt）满血触控热区 + 按键渲染零分配：
  1. 即使顶部显示 10.5pt 拼音预编辑行，CandidateStrip 依然保持 0..42pt 全高度触控命中，点击首选上半区也 100% 必上屏。
  2. KeyView 按下/抬起热路径复用 CGPath（缓存 lastCapSize），0 次 UIBezierPath / CABasicAnimation 分配；设置页诊断新增“引擎就绪 XX ms”冷启动观测。
· 9 条 iOS 26/27 键盘扩展工程铁律（Tools/check_ios_keyboard_rules.py）已接入 CI 静态门禁。

真机重点测试项 (R43 · iOS 27)
1. 在手机网页版 Antigravity、Safari 网页富文本编辑器、备忘录、微信中高速连续输入长句与退格重输，确认跟手零卡顿、光标零跳动。
2. 连续快打并点击候选栏第 1 个字（含偏上边缘点击），确认首选 100% 稳定上屏。
3. 体验离线行内心算（286/4=）、相对日期（明天 / 下周一 / 今年 / 本月）与成对标点联动双删。
