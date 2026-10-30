import SwiftUI

// The home page shows what the keyboard does with the keyboard's own pieces — its candidate strip, its vinyl keys,
// Mosto — drawn small, the way they look while typing; the words stay short. Every note in full is one tap away
// (全部用法).

// MARK: - The keyboard's look, in miniature

/// Colours from the keyboard (Theme), so a demo looks like the keyboard in either light.
private extension Color {
    static let kbText = Color(uiColor: Theme.keyText)
    static let kbSecondary = Color(uiColor: Theme.secondaryText)
    static let kbMark = Color(uiColor: Theme.correctedMark)
    static let kbTint = Color(uiColor: Theme.correctedTint)
    static let kbKey = Color(uiColor: Theme.key)
    static let kbKeyTop = Color(uiColor: Theme.keyTop)
    static let kbLip = Color(uiColor: Theme.keyLip)
    static let kbFunction = Color(uiColor: Theme.functionKey)
    static let kbFunctionLip = Color(uiColor: Theme.functionLip)
}

/// The board the demos sit on: the system keyboard's grey glass, rounded like a phone's lower edge.
private struct Board<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.17, alpha: 1) : UIColor(red: 0.89, green: 0.89, blue: 0.92, alpha: 1) }))
            )
    }
}

/// What the text field shows: committed text, then the keys being typed as marked text (underlined, as iOS draws it).
/// How far a demo has played: the keys type in up to 0.8, the strip answers after (1 = the still picture).
private struct DemoRevealKey: EnvironmentKey { static let defaultValue: Double = 1 }
extension EnvironmentValues {
    var demoReveal: Double {
        get { self[DemoRevealKey.self] }
        set { self[DemoRevealKey.self] = newValue }
    }
}

private struct FieldLine: View {
    var committed = ""
    var marked = ""
    @Environment(\.demoReveal) private var reveal
    var body: some View {
        let shown = String(marked.prefix(Int((Double(marked.count) * min(reveal / 0.8, 1)).rounded(.down))))
        HStack(spacing: 0) {
            Text(committed).foregroundStyle(.primary)
            Text(shown).underline(true, color: .secondary).foregroundStyle(.primary)
            Rectangle().fill(Color.accentColor).frame(width: 2, height: 18).padding(.leading, 1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 15, design: .rounded))
        .lineLimit(1)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(UIColor.systemBackground)))
    }
}

/// One candidate as the strip draws it; the corrected first choice on its tint with "hap→hao" under it.
struct DemoCandidate: Identifiable {
    let id = UUID()
    var text: String
    var typed: String? = nil
    var meant: String? = nil
    var note: String? = nil
    var fixed = false
}

private struct Strip: View {
    var undo: String? = nil
    let items: [DemoCandidate]
    @Environment(\.demoReveal) private var reveal
    var body: some View {
        let answered = reveal >= 0.85
        HStack(spacing: 2) {
            if let undo {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 9, weight: .semibold))
                    Text(undo).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
                }
                .foregroundStyle(Color.kbMark)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(Capsule().fill(Color.kbTint))
                .padding(.trailing, 4)
            }
            ForEach(items) { c in
                VStack(spacing: 0) {
                    Text(c.text).font(.system(size: 16, design: .rounded)).foregroundStyle(Color.kbText).lineLimit(1)
                    if let t = c.typed, let m = c.meant {
                        (Text(t).foregroundColor(.kbSecondary) + Text("→").foregroundColor(.kbSecondary) + Text(m).foregroundColor(.kbMark))
                            .font(.system(size: 9, weight: .semibold, design: .rounded)).lineLimit(1)
                    } else if let n = c.note {
                        Text(n).font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(Color.kbSecondary)
                    }
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(c.fixed ? Color.kbTint : .clear))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 36)
        .opacity(answered ? 1 : 0)
        .offset(y: answered ? 0 : 5)
        .animation(.easeOut(duration: 0.22), value: answered)
    }
}

/// A vinyl cap as on the keyboard: a top-lit face on a darker lip; `hit` marks where the finger landed.
private struct MiniKey: View {
    let label: String
    var sub: String? = nil
    var function = false
    var hit = false
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(function ? Color.kbFunctionLip : Color.kbLip)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(function ? AnyShapeStyle(Color.kbFunction) : AnyShapeStyle(LinearGradient(colors: [.kbKeyTop, .kbKey], startPoint: .top, endPoint: .bottom)))
                .padding(.bottom, 2)
            VStack(spacing: 0) {
                Text(label).font(.system(size: sub == nil ? 14 : 12, design: .rounded)).foregroundStyle(Color.kbText)
                if let sub { Text(sub).font(.system(size: 7.5, weight: .semibold, design: .rounded)).foregroundStyle(Color.kbSecondary).lineLimit(2).multilineTextAlignment(.center) }
            }
            .padding(.top, sub == nil ? 5 : 3)
            if hit {
                Circle().fill(Color.kbMark.opacity(0.35)).frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Color.kbMark, lineWidth: 1.2))
                    .offset(x: 9, y: 9)
            }
        }
        .frame(height: sub == nil ? 30 : 40)
    }
}

/// The top letter row (qwertyuiop), with the key the finger actually touched marked.
private struct LetterRow: View {
    var hit: Character? = nil
    @Environment(\.demoReveal) private var reveal
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array("qwertyuiop"), id: \.self) { c in MiniKey(label: String(c), hit: c == hit && reveal >= 0.7) }
        }
    }
}

// MARK: - Showcase

/// A demo with its title and one short line under it.
/// A demo that plays: the keys type into the field one by one, then the strip answers. It plays once when it first
/// appears and again on every tap (still, with Reduce Motion). A demo with a lesson on 上手 (demoLessons) also has
/// 「试一试」 next to the play mark: it opens that lesson with an empty field.
private struct Demo<Visual: View>: View {
    let title: String
    let line: String
    @ViewBuilder var visual: Visual
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appNavigation) private var nav
    @State private var reveal = 1.0
    @State private var run = 0
    @State private var played = false
    private var tryable: Bool { demoLessons[title] != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            visual.environment(\.demoReveal, reveal)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(line).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    if tryable {
                        // its own width, always whole: the title beside it wraps instead
                        Button { tryIt() } label: {
                            Text("试一试").font(.subheadline.weight(.semibold)).foregroundStyle(mostoTint)
                                .lineLimit(1).fixedSize()
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Capsule().fill(mostoTint.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHidden(true)   // VoiceOver: one of the card's actions (the card reads as one)
                    }
                    if !reduceMotion {
                        Image(systemName: "play.circle.fill").font(.system(size: 26)).foregroundStyle(mostoTint.opacity(reveal < 1 ? 0.35 : 1))
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
        .contentShape(Rectangle())
        .onTapGesture { play() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("再演示一次")
        .accessibilityActions {
            if tryable { Button("试一试") { tryIt() } }
        }
        .onAppear { if !played { played = true; play() } }
        .task(id: run) {
            guard run > 0, !reduceMotion else { reveal = 1; return }
            reveal = 0
            for i in 1...32 {
                try? await Task.sleep(nanoseconds: 42_000_000)
                if Task.isCancelled { return }
                reveal = Double(i) / 32
            }
        }
    }
    private func play() { run += 1 }
    private func tryIt() { nav?.tryDemo(title) }
}

struct FeatureShowcase: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "打字时你会看到", subtitle: "以下画面就是键盘上的样子")
            Demo(title: "按错了什么，改成了什么", line: "手指落在 w 靠 e 的一边：首选浅色底，下方写着 rw→re；第二个“原键”是照按下的读。") {
                Board {
                    FieldLine(marked: "jintianhenrw")
                    Strip(items: [
                        DemoCandidate(text: "今天很热", typed: "rw", meant: "re", fixed: true),
                        DemoCandidate(text: "今天很入味", note: "原键"),
                        DemoCandidate(text: "今天"),
                    ])
                    LetterRow(hit: "w")
                }
            }
            Demo(title: "长句多按、漏按一个键", line: "中间少按了 n，整句照样读对；多按一个键也一样。") {
                Board {
                    FieldLine(marked: "jintiantiaqihenhao")
                    Strip(items: [
                        DemoCandidate(text: "今天天气很好", typed: "tia", meant: "tian", fixed: true),
                        DemoCandidate(text: "今天提啊起很好", note: "原键"),
                    ])
                }
            }
            Demo(title: "一键撤回", line: "纠错上屏后，左边出现刚才按的字母，点一下或按删除就恢复。") {
                Board {
                    FieldLine(committed: "今天天气很好")
                    Strip(undo: "jintiantiaqi", items: [
                        DemoCandidate(text: "的"), DemoCandidate(text: "很好"), DemoCandidate(text: "哦"),
                    ])
                }
            }
            Demo(title: "中英混输", line: "句子里夹英文词照打；拼音拼得出的词（women）仍先给中文。") {
                Board {
                    FieldLine(marked: "woyongiphonedazi")
                    Strip(items: [
                        DemoCandidate(text: "我用iPhone打字"), DemoCandidate(text: "我用"), DemoCandidate(text: "我"),
                    ])
                }
            }
            Demo(title: "联想", line: "上屏后接着给常用的下一个词，点一下直接上屏。") {
                Board {
                    FieldLine(committed: "你好")
                    Strip(items: ["好的", "我", "想你", "有"].map { DemoCandidate(text: $0) })
                }
            }
            Demo(title: "记住你的词", line: "词库里没有的名字、说法，选出一次就记住，只打声母也排第一。") {
                Board {
                    FieldLine(marked: "mstd")
                    Strip(items: [
                        DemoCandidate(text: "摸索台灯"), DemoCandidate(text: "美食天地"), DemoCandidate(text: "模式特点"),
                    ])
                }
            }
            HStack(alignment: .top, spacing: 12) {
                SmallDemo(title: "九宫格", line: "左列选拼音，两种方案都能用") {
                    VStack(spacing: 4) {
                        ForEach([["，", "ABC", "DEF"], ["GHI", "JKL", "MNO"], ["PQRS", "TUV", "WXYZ"]], id: \.self) { row in
                            HStack(spacing: 4) { ForEach(row, id: \.self) { MiniKey(label: $0, function: $0 == "，") } }
                        }
                    }
                }
                SmallDemo(title: "小鹤键位提示", line: "键上写声母韵母，记熟可关") {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            MiniKey(label: "u", sub: "sh\nu")
                            MiniKey(label: "i", sub: "ch\ni")
                            MiniKey(label: "o", sub: "uo\no")
                        }
                        HStack(spacing: 4) {
                            MiniKey(label: "s", sub: "ong\niong")
                            MiniKey(label: "h", sub: "ang")
                            MiniKey(label: "v", sub: "zh\nui ü")
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 12) {
                LightCard(image: "Mosto", title: "日光", text: "瞪大眼睛看你打字，不打字时待在候选栏左边，偶尔眨眼。", night: false)
                LightCard(image: "MostoNight", title: "夜灯", text: "眯眼坏笑，尾巴尖亮起灯珠的金光，待在候选栏左边；键盘闲下来，他会慢慢打个哈欠。", night: true)
            }
        }
    }
}

private struct SmallDemo<Visual: View>: View {
    let title: String
    let line: String
    @ViewBuilder var visual: Visual
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Board { visual }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(line).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
    }
}

/// Mosto in one of his two lights, on that light's own ground.
private struct LightCard: View {
    let image: String, title: String, text: String
    let night: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(uiImage: mostoImage(image)).resizable().scaledToFit().frame(height: 96)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            Text(title).font(.headline).foregroundStyle(night ? Color(red: 1.0, green: 0.86, blue: 0.55) : Color(red: 0.33, green: 0.21, blue: 0.69))
            Text(text).font(.caption).foregroundStyle(night ? Color.white.opacity(0.78) : Color(red: 0.36, green: 0.31, blue: 0.24))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(night ? LinearGradient(colors: [Color(red: 0.20, green: 0.14, blue: 0.42), Color(red: 0.09, green: 0.07, blue: 0.22)], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [Color(red: 1.0, green: 0.97, blue: 0.89), Color(red: 0.98, green: 0.88, blue: 0.68)], startPoint: .top, endPoint: .bottom))
        )
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.bold))
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Setup

/// 启用键盘: the three steps as the Settings path they are (tappable crumbs, not prose), and one clear button.
struct SetupCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "启用键盘")
            VStack(alignment: .leading, spacing: 14) {
                SetupStep(n: 1, title: "添加键盘") {
                    Crumbs(items: ["设置", "通用", "键盘", "键盘", "添加新键盘", "Mosto键盘"])
                }
                SetupStep(n: 2, title: "切换过来") {
                    HStack(spacing: 6) {
                        Text("打字时长按或轻点").font(.subheadline).foregroundStyle(.secondary)
                        Image(systemName: "globe").font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(uiColor: Theme.functionKey)))
                    }
                }
                SetupStep(n: 3, title: "震动与按键音（可选）") {
                    Text("在键盘列表中点 Mosto键盘，开启“允许完全访问”。键盘始终只在手机上运行。")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Text("打开系统设置").font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(mostoTint))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
        }
    }
}

private struct SetupStep<Detail: View>: View {
    let n: Int
    let title: String
    @ViewBuilder var detail: Detail
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Circle().fill(mostoTint))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                detail
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A Settings path as small chips that wrap onto the next line (never scroll sideways).
private struct Crumbs: View {
    let items: [String]
    var body: some View {
        WrapLayout(spacing: 4, lineSpacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, t in
                HStack(spacing: 4) {
                    Text(t).font(.caption.weight(.semibold))
                        .foregroundStyle(i == items.count - 1 ? Color.white : Color.primary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(i == items.count - 1 ? mostoTint : Color(UIColor.tertiarySystemFill)))
                    if i < items.count - 1 { Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary) }
                }
            }
        }
    }
}

/// Lays its children out left to right, starting a new line when the next one does not fit.
struct WrapLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxW { y += lineH + lineSpacing; x = 0; lineH = 0 }
            x += s.width + spacing; lineH = max(lineH, s.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxW), height: y + lineH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { y += lineH + lineSpacing; x = bounds.minX; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; lineH = max(lineH, s.height)
        }
    }
}

// MARK: - Try, more, footer

struct TryField: View {
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "试打")
            TextField("全拼 nihao 或小鹤 nihc → 你好", text: $text, axis: .vertical)
                .lineLimit(3...8)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
        }
    }
}

/// The rest as a Settings-style list: every usage note, the 小鹤双拼 guide, the legal pages, feedback.
struct MoreList: View {
    let snapshot: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "更多")
            VStack(spacing: 0) {
                row("全部用法", detail: "每个键、每个手势的完整说明", icon: "book.pages", color: .indigo) { UsageDetailView() }
                Divider().padding(.leading, 56)
                row("小鹤双拼", detail: "每个字固定两键的双拼方案。两种方案在这个键盘上功能相同，全拼用户继续用全拼就好；想换之前，先看清学习成本。", icon: "keyboard", color: .purple) { XiaoheGuideView() }
                ForEach(Array(LegalText.docs.enumerated()), id: \.offset) { _, doc in
                    Divider().padding(.leading, 56)
                    row(doc.title, detail: nil, icon: aboutIcon(doc.id), color: .gray) { LegalView(doc: doc) }
                }
                Divider().padding(.leading, 56)
                if let u = URL(string: "https://github.com/mjuvdeysii/mossottokeyboard/issues") {
                    Link(destination: u) { RowLabel(title: "问题与建议", detail: nil, icon: "bubble.left.and.text.bubble.right", color: .teal, external: true) }
                        .buttonStyle(.plain)
                }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
        }
    }

    @ViewBuilder
    private func row<D: View>(_ title: String, detail: String?, icon: String, color: Color, @ViewBuilder destination: () -> D) -> some View {
        if snapshot {
            RowLabel(title: title, detail: detail, icon: icon, color: color)
        } else {
            NavigationLink { destination() } label: { RowLabel(title: title, detail: detail, icon: icon, color: color) }
                .buttonStyle(.plain)
        }
    }
}

/// A Settings row: a white glyph on a coloured rounded square, the title, an optional line under it, a chevron.
private struct RowLabel: View {
    let title: String
    let detail: String?
    let icon: String
    let color: Color
    var external = false
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(.primary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 4)
            Image(systemName: external ? "arrow.up.right" : "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

struct HomeFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("测试版：功能可能变动，发送重要内容前请核对上屏文字。在 TestFlight 中截图即可提交反馈。", systemImage: "testtube.2")
            Text("纯粹的输入法：候选全部来自装在 App 里的开源词库与统计数据（按词语在公开语料里出现的次数排序），在手机上算出来，全程离线。整个键盘只靠词库和统计工作。")
            Text("词库、你学过的词和触点习惯都只存在这台设备上。")
        }
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 6)
    }
}
