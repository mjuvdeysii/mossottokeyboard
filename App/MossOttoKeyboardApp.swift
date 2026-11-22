import SwiftUI

@main
struct MossOttoKeyboardApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// Mosto sprites from the app's asset catalog (full resolution; the keyboard carries small copies of its own).
func mostoImage(_ name: String) -> UIImage { UIImage(named: name) ?? UIImage() }

/// Mosto's violet (the app tint), lighter in dark mode so it keeps its contrast.
let mostoTint = Color(UIColor { $0.userInterfaceStyle == .dark
    ? UIColor(red: 0xB7 / 255, green: 0xA2 / 255, blue: 0xF5 / 255, alpha: 1)
    : UIColor(red: 0x55 / 255, green: 0x36 / 255, blue: 0xB0 / 255, alpha: 1) })

/// The companion app: Mosto, how to turn the keyboard on, a field to try it, how it works, and the fine print.
/// Built from plain stacks (not Form), laid out like iOS Settings, so the same view also renders to an image in CI.
struct ContentView: View {
    @StateObject private var nav = AppNavigation()

    var body: some View {
        TabView(selection: $nav.tab) {
            NavigationStack {
                FeaturesHubScreen(model: nav.playground)
                    .navigationTitle("Mosto键盘")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("概览", systemImage: "sparkles") }
            .tag(AppTab.features)
            NavigationStack {
                GuideHubScreen(segment: $nav.guideSegment, model: nav.playground)
                    .navigationTitle("练习")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("练习", systemImage: "hand.tap") }
            .tag(AppTab.guide)
            NavigationStack {
                SettingsHubScreen(model: nav.playground)
                    .navigationTitle("设置")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        .environment(\.appNavigation, nav)
        .tint(mostoTint)
        .task {
            if SnapshotRenderer.requested,
               let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                SnapshotRenderer.run(in: scene)
            }
        }
    }
}

/// The app's three tabs: Features (home) -> Guide (enable + playground) -> Settings.
enum AppTab: Hashable { case features, guide, settings }

@MainActor
final class AppNavigation: ObservableObject {
    @Published var tab: AppTab = .features
    @Published var guideSegment: Int = KeyboardStatus.isAdded() ? 1 : 0
    let playground: PlaygroundModel

    init() { playground = PlaygroundModel() }

    func tryDemo(_ title: String) {
        guard let lesson = demoLessons[title], let i = lessons.firstIndex(where: { $0.title == lesson }) else { return }
        playground.jump(to: i)
        guideSegment = 1
        tab = .guide
    }
}

private struct FeatureItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let stat: String
    let detail: String
    let lessonTitle: String?
}

private let featureItems: [FeatureItem] = [
    FeatureItem(id: "fix", icon: "wand.and.stars", title: "整句纠错", stat: "92.1% 整句 · 0.3ms",
                detail: "按偏、漏键、多按与相邻打反（如 nihoa → 你好、inhc → 你好）自动联句修正，点候选栏 ↩ 或删除即可秒撤回。", lessonTitle: "按错一个键"),
    FeatureItem(id: "scheme", icon: "keyboard", title: "双拼与全拼", stat: "小鹤 2 键 · 九宫格",
                detail: "同时内置全拼、纯小鹤双拼（每字固定 2 键、无形码）与九宫格布局，中英混输自动识别大小写，设置跨版本保留。", lessonTitle: nil),
    FeatureItem(id: "mix", icon: "equal.square", title: "心算与智能日期", stat: "286/4= · 相对日期",
                detail: "输入算式加等号（如 286/4=）候选栏即出精准结果，支持括号与四则运算；输入明天、下周一、今年、本月自动出对应日期。", lessonTitle: "中英混输"),
    FeatureItem(id: "kaomoji", icon: "bolt.horizontal", title: "零卡顿流畅引擎", stat: "WebView 帧合并 · 零乱码",
                detail: "24ms 帧合并行内预编辑与 0-XPC 空格断句，在 Safari 与网页编辑器中丝滑跟手；内置 CoreText 缺字形过滤，永久告别生僻豆腐块。", lessonTitle: nil),
    FeatureItem(id: "glass", icon: "square.on.square", title: "微扁平双风格", stat: "iOS 原生 · Mosto 软胶",
                detail: "简洁模式复刻系统液态玻璃比例与纯净单行候选栏；Mosto 模式采用微扁平哑光软胶底沿与日/夜灯暖金高光，一键切换。", lessonTitle: nil),
    FeatureItem(id: "offline", icon: "lock.shield", title: "纯离线 · 零追踪", stat: "0 联网 · 0 剪贴板",
                detail: "键盘扩展全程本机只读 mmap 计算，不含任何网络请求、剪贴板读取、第三方 SDK 或共享容器，保持默认权限即可完整使用。", lessonTitle: nil),
]

private enum StageMood: Int, CaseIterable {
    case day = 0, night = 1, plain = 2
    var label: String {
        switch self { case .day: return "潮玩日光"; case .night: return "潮玩夜灯"; case .plain: return "原生简洁" }
    }
    var subtitle: String {
        switch self {
        case .day: return "微扁平软胶 · 哑光柔面"
        case .night: return "暗夜绒面 · 暖金细高光"
        case .plain: return "系统比例 · 液态玻璃"
        }
    }
}

/// Custom hand-drawn SwiftUI vector miniature illustrations for each feature card (zero emoji, zero generic symbols).
private struct FeatureGlyphArt: View {
    let id: String
    var large = false

    var body: some View {
        let s: CGFloat = large ? 64 : 34
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let violet = Color(red: 0.42, green: 0.28, blue: 0.78)
            let gold = Color(red: 0.90, green: 0.68, blue: 0.24)
            let ink = Color.primary.opacity(0.82)
            let softFill = violet.opacity(0.14)
            switch id {
            case "fix":
                let k1 = CGRect(x: w * 0.08, y: h * 0.34, width: w * 0.40, height: h * 0.50)
                let k2 = CGRect(x: w * 0.52, y: h * 0.20, width: w * 0.40, height: h * 0.50)
                ctx.fill(Path(roundedRect: k1, cornerRadius: w * 0.12), with: .color(softFill))
                ctx.stroke(Path(roundedRect: k1, cornerRadius: w * 0.12), with: .color(violet), lineWidth: large ? 2.2 : 1.5)
                ctx.fill(Path(roundedRect: k2, cornerRadius: w * 0.12), with: .color(gold.opacity(0.22)))
                ctx.stroke(Path(roundedRect: k2, cornerRadius: w * 0.12), with: .color(gold), lineWidth: large ? 2.2 : 1.5)
                var arc = Path()
                arc.move(to: CGPoint(x: w * 0.26, y: h * 0.26))
                arc.addQuadCurve(to: CGPoint(x: w * 0.72, y: h * 0.14), control: CGPoint(x: w * 0.48, y: h * 0.02))
                ctx.stroke(arc, with: .color(violet), style: StrokeStyle(lineWidth: large ? 2.2 : 1.5, lineCap: .round))
            case "scheme":
                let box = CGRect(x: w * 0.10, y: h * 0.16, width: w * 0.80, height: h * 0.68)
                let left = CGRect(x: w * 0.10, y: h * 0.16, width: w * 0.40, height: h * 0.68)
                ctx.fill(Path(roundedRect: left, cornerRadius: w * 0.14), with: .color(violet.opacity(0.22)))
                ctx.stroke(Path(roundedRect: box, cornerRadius: w * 0.16), with: .color(violet), lineWidth: large ? 2.2 : 1.5)
                var div = Path()
                div.move(to: CGPoint(x: w * 0.50, y: h * 0.24))
                div.addLine(to: CGPoint(x: w * 0.50, y: h * 0.76))
                ctx.stroke(div, with: .color(gold), style: StrokeStyle(lineWidth: large ? 2.0 : 1.4, lineCap: .round))
            case "mix":
                let back = CGRect(x: w * 0.34, y: h * 0.12, width: w * 0.54, height: h * 0.54)
                let front = CGRect(x: w * 0.12, y: h * 0.34, width: w * 0.54, height: h * 0.54)
                ctx.fill(Path(roundedRect: back, cornerRadius: w * 0.14), with: .color(gold.opacity(0.20)))
                ctx.stroke(Path(roundedRect: back, cornerRadius: w * 0.14), with: .color(gold), lineWidth: large ? 2.0 : 1.4)
                ctx.fill(Path(roundedRect: front, cornerRadius: w * 0.14), with: .color(softFill))
                ctx.stroke(Path(roundedRect: front, cornerRadius: w * 0.14), with: .color(violet), lineWidth: large ? 2.2 : 1.5)
            case "kaomoji":
                var crown = Path()
                crown.move(to: CGPoint(x: w * 0.24, y: h * 0.46))
                crown.addLine(to: CGPoint(x: w * 0.30, y: h * 0.20))
                crown.addLine(to: CGPoint(x: w * 0.44, y: h * 0.34))
                crown.addLine(to: CGPoint(x: w * 0.50, y: h * 0.14))
                crown.addLine(to: CGPoint(x: w * 0.56, y: h * 0.34))
                crown.addLine(to: CGPoint(x: w * 0.70, y: h * 0.20))
                crown.addLine(to: CGPoint(x: w * 0.76, y: h * 0.46))
                crown.closeSubpath()
                ctx.fill(crown, with: .color(gold.opacity(0.32)))
                ctx.stroke(crown, with: .color(gold), style: StrokeStyle(lineWidth: large ? 2.2 : 1.5, lineJoin: .round))
                var wing = Path()
                wing.move(to: CGPoint(x: w * 0.12, y: h * 0.64))
                wing.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.74), control: CGPoint(x: w * 0.30, y: h * 0.88))
                wing.addQuadCurve(to: CGPoint(x: w * 0.88, y: h * 0.64), control: CGPoint(x: w * 0.70, y: h * 0.88))
                ctx.stroke(wing, with: .color(violet), style: StrokeStyle(lineWidth: large ? 2.4 : 1.6, lineCap: .round))
            case "glass":
                let base = CGRect(x: w * 0.10, y: h * 0.34, width: w * 0.56, height: h * 0.52)
                let lip = CGRect(x: w * 0.10, y: h * 0.42, width: w * 0.56, height: h * 0.44)
                let top = CGRect(x: w * 0.34, y: h * 0.14, width: w * 0.56, height: h * 0.52)
                ctx.fill(Path(roundedRect: lip, cornerRadius: w * 0.14), with: .color(violet.opacity(0.32)))
                ctx.fill(Path(roundedRect: base, cornerRadius: w * 0.14), with: .color(softFill))
                ctx.stroke(Path(roundedRect: base, cornerRadius: w * 0.14), with: .color(violet), lineWidth: large ? 2.0 : 1.4)
                ctx.fill(Path(roundedRect: top, cornerRadius: w * 0.18), with: .color(Color.white.opacity(0.55)))
                ctx.stroke(Path(roundedRect: top, cornerRadius: w * 0.18), with: .color(ink.opacity(0.45)), lineWidth: large ? 2.0 : 1.4)
            default:
                var shield = Path()
                shield.move(to: CGPoint(x: w * 0.50, y: h * 0.12))
                shield.addLine(to: CGPoint(x: w * 0.82, y: h * 0.24))
                shield.addLine(to: CGPoint(x: w * 0.78, y: h * 0.58))
                shield.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.88), control: CGPoint(x: w * 0.70, y: h * 0.78))
                shield.addQuadCurve(to: CGPoint(x: w * 0.22, y: h * 0.58), control: CGPoint(x: w * 0.30, y: h * 0.78))
                shield.addLine(to: CGPoint(x: w * 0.18, y: h * 0.24))
                shield.closeSubpath()
                ctx.fill(shield, with: .color(softFill))
                ctx.stroke(shield, with: .color(violet), style: StrokeStyle(lineWidth: large ? 2.2 : 1.5, lineJoin: .round))
                var check = Path()
                check.move(to: CGPoint(x: w * 0.36, y: h * 0.52))
                check.addLine(to: CGPoint(x: w * 0.47, y: h * 0.63))
                check.addLine(to: CGPoint(x: w * 0.66, y: h * 0.40))
                ctx.stroke(check, with: .color(gold), style: StrokeStyle(lineWidth: large ? 2.4 : 1.6, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: s, height: s)
    }
}

/// Tactile miniature 3-keycap specimen showing micro-flat soft-vinyl vs iOS Liquid Glass craft.
private struct MiniKeySpecimen: View {
    let mood: StageMood

    var body: some View {
        let keys = ["m", "o", "中"]
        let isPlain = mood == .plain
        let isNight = mood == .night
        let faceColor: Color = isPlain ? .white : (isNight ? Color(red: 0.27, green: 0.22, blue: 0.55) : Color(red: 0.98, green: 0.97, blue: 1.0))
        let lipColor: Color = isPlain ? Color.black.opacity(0.08) : (isNight ? Color(red: 0.11, green: 0.08, blue: 0.29) : Color(red: 0.81, green: 0.76, blue: 0.93))
        let rimColor: Color = isPlain ? Color.black.opacity(0.06) : (isNight ? Color(red: 1.0, green: 0.89, blue: 0.66).opacity(0.32) : Color.white.opacity(0.88))
        let inkColor: Color = isNight ? Color(red: 1.0, green: 0.95, blue: 0.86) : Color(red: 0.17, green: 0.10, blue: 0.38)
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { label in
                ZStack {
                    RoundedRectangle(cornerRadius: isPlain ? 7 : 9, style: .continuous)
                        .fill(lipColor)
                        .offset(y: isPlain ? 0.8 : 1.7)
                    RoundedRectangle(cornerRadius: isPlain ? 7 : 9, style: .continuous)
                        .fill(faceColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: isPlain ? 7 : 9, style: .continuous)
                                .stroke(rimColor, lineWidth: 0.75)
                        )
                    Text(label)
                        .font(.system(size: label == "中" ? 12 : 14, weight: isPlain ? .regular : .medium, design: isPlain ? .default : .rounded))
                        .foregroundStyle(inkColor)
                }
                .frame(width: 30, height: 32)
            }
        }
    }
}

private struct SandboxPrompt: Identifiable {
    let id: String
    let label: String
    let hint: String
}

/// Tab 1 (首屏): Art-directed Mosto stage, live interactive sandbox (xiaohe/quanpin + dismissible keyboard), and Bento feature cards.
private struct FeaturesHubScreen: View {
    @ObservedObject var model: PlaygroundModel
    @Environment(\.appNavigation) private var nav
    @Environment(\.scenePhase) private var phase
    @State private var added = KeyboardStatus.isAdded()
    @State private var mood: StageMood = .day
    @State private var blink = false
    @State private var hop = false
    @State private var selected: FeatureItem? = nil
    @State private var sandboxKeyboardOpen = false
    @State private var activePromptIndex = 0
    @State private var cursorBlink = true

    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var prompts: [SandboxPrompt] {
        if model.layout == 1 {
            return [
                SandboxPrompt(id: "xh1", label: "误触纠错", hint: "试试打 inhc 空格 → 你好，或 cwui 空格 → 测试"),
                SandboxPrompt(id: "xh2", label: "长句连打", hint: "试试打 jmtmll 空格 → 今天来了"),
                SandboxPrompt(id: "xh3", label: "心算与日期", hint: "试试打 286/4= 算账，或打 mgtm 出明日日期"),
            ]
        } else if model.layout == 2 {
            return [
                SandboxPrompt(id: "t91", label: "九宫格整句", hint: "直接连点九宫格按键，左侧音节栏可精准锁音"),
                SandboxPrompt(id: "t92", label: "智能标点", hint: "长按 ，选《》自动回退，按空格一键跳出"),
                SandboxPrompt(id: "t93", label: "心算与日期", hint: "试试切 123 打 286/4=，或输入「明天」看日期"),
            ]
        } else {
            return [
                SandboxPrompt(id: "qp1", label: "误触纠错", hint: "试试打 nihoa 空格 → 你好"),
                SandboxPrompt(id: "qp2", label: "长句连打", hint: "试试打 jintiantiaqi 空格 → 今天天气"),
                SandboxPrompt(id: "qp3", label: "心算与日期", hint: "试试打 286/4= 算账，或打 mingtian 出明日日期"),
            ]
        }
    }

    private var stageBg: LinearGradient {
        switch mood {
        case .day:
            return LinearGradient(colors: [Color(red: 0.98, green: 0.95, blue: 0.89), Color(red: 0.94, green: 0.91, blue: 0.97)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .night:
            return LinearGradient(colors: [Color(red: 0.15, green: 0.11, blue: 0.27), Color(red: 0.24, green: 0.18, blue: 0.40)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .plain:
            return LinearGradient(colors: [Color(red: 0.93, green: 0.94, blue: 0.96), Color(red: 0.88, green: 0.90, blue: 0.94)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var stageInk: Color { mood == .night ? Color(red: 1.0, green: 0.96, blue: 0.88) : Color(red: 0.16, green: 0.12, blue: 0.28) }
    private var stageSub: Color { mood == .night ? Color.white.opacity(0.72) : Color.black.opacity(0.56) }

    private func syncMoodToModel(_ m: StageMood) {
        switch m {
        case .day:
            model.style = 0; model.appearance = 1
        case .night:
            model.style = 0; model.appearance = 2
        case .plain:
            model.style = 1; model.appearance = 0
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            ZStack {
                                RadialGradient(colors: [Color(red: 1.0, green: 0.89, blue: 0.66).opacity(mood == .night ? 0.28 : 0.42), .clear], center: .center, startRadius: 4, endRadius: 42)
                                    .frame(width: 82, height: 82)
                                Image(uiImage: mostoImage(mood == .night ? "MostoToyNight" : (blink ? "MostoToyBlink" : "MostoToy")))
                                    .resizable().scaledToFit()
                                    .frame(width: 78, height: 78)
                                    .scaleEffect(x: hop ? 1.06 : 1, y: hop ? 0.94 : 1, anchor: .bottom)
                                    .offset(y: hop ? -4 : 0)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.45)) { hop = true; blink = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { hop = false }
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { blink = false }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("按偏了，也能打对")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(stageInk)
                                Text(mood.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(stageSub)
                                MiniKeySpecimen(mood: mood)
                                    .padding(.top, 2)
                            }
                            Spacer(minLength: 0)
                        }

                        HStack(spacing: 6) {
                            ForEach(StageMood.allCases, id: \.self) { m in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { mood = m }
                                    syncMoodToModel(m)
                                } label: {
                                    Text(m.label)
                                        .font(.caption.weight(mood == m ? .semibold : .regular))
                                        .foregroundStyle(mood == m ? (mood == .night ? Color(red: 0.15, green: 0.11, blue: 0.27) : .white) : stageSub)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(mood == m ? (mood == .night ? Color(red: 1.0, green: 0.89, blue: 0.66) : mostoTint) : Color.black.opacity(mood == .night ? 0.18 : 0.05)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(stageBg)
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(mood == .night ? 0.12 : 0.65), lineWidth: 1))
                    )

                    // Top status capsule: clear setup prompt when not enabled, compact green-dot pill once ready.
                    Button {
                        nav?.guideSegment = added ? 2 : 0
                        nav?.tab = .guide
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(added ? Color.green : mostoTint).frame(width: 8, height: 8)
                            Text(added ? "系统键盘已就绪 · 纯离线运行" : "尚未启用系统键盘 · 30 秒完成添加")
                                .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                            Spacer()
                            Text(added ? "去测速" : "去开启")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(added ? Color.green : mostoTint)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
                    }
                    .buttonStyle(.plain)

                    // Playable 10-second live sandbox: 3 layouts + 2 styles + 3 pain-point prompts + dismissible keyboard.
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Label("10 秒手感试打沙盒", systemImage: "keyboard")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                model.style = model.style == 0 ? 1 : 0
                            } label: {
                                Text(model.style == 0 ? "Mosto" : "简洁")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(Capsule().fill(Color(UIColor.tertiarySystemFill)))
                            }
                            .buttonStyle(.plain)
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                                    sandboxKeyboardOpen.toggle()
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: sandboxKeyboardOpen ? "keyboard.chevron.compact.down" : "keyboard")
                                    Text(sandboxKeyboardOpen ? "收起" : "试打")
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(mostoTint)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Capsule().fill(mostoTint.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }

                        Picker("输入方案", selection: $model.layout) {
                            Text("全拼").tag(0)
                            Text("小鹤").tag(1)
                            Text("九宫格").tag(2)
                        }
                        .pickerStyle(.segmented)

                        // Built-in 3 short scenario prompts (wraps cleanly, zero horizontal scroll)
                        HStack(spacing: 6) {
                            ForEach(Array(prompts.enumerated()), id: \.element.id) { idx, p in
                                Button {
                                    activePromptIndex = idx
                                    if !sandboxKeyboardOpen {
                                        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                                            sandboxKeyboardOpen = true
                                        }
                                    }
                                } label: {
                                    Text(p.label)
                                        .font(.caption2.weight(activePromptIndex == idx ? .semibold : .medium))
                                        .foregroundStyle(activePromptIndex == idx ? .white : .secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 5)
                                        .background(Capsule().fill(activePromptIndex == idx ? mostoTint : Color(UIColor.tertiarySystemFill)))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        let activePrompt = prompts[min(activePromptIndex, prompts.count - 1)]
                        VStack(alignment: .leading, spacing: 6) {
                            (Text(model.before) + Text(model.marked).underline() + Text(sandboxKeyboardOpen && cursorBlink ? "|" : " ").foregroundColor(mostoTint))
                                .font(.system(size: 18, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
                                .overlay(alignment: .topLeading) {
                                    if model.before.isEmpty && model.marked.isEmpty {
                                        Text(activePrompt.hint)
                                            .font(.system(size: 14, design: .rounded))
                                            .foregroundStyle(.tertiary)
                                            .allowsHitTesting(false)
                                    }
                                }
                            if !model.before.isEmpty || !model.marked.isEmpty {
                                HStack {
                                    Text(activePrompt.hint)
                                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                    Spacer()
                                    Button("清空") { model.clear() }
                                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(11)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(UIColor.tertiarySystemGroupedBackground)))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !sandboxKeyboardOpen {
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                                    sandboxKeyboardOpen = true
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.primary.opacity(0.05), lineWidth: 0.8))
                    )

                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(featureItems) { item in
                            Button { selected = item } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .top) {
                                        FeatureGlyphArt(id: item.id)
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer(minLength: 2)
                                    Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Text(item.stat).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.05), lineWidth: 0.8))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .background(Color(UIColor.systemGroupedBackground))

            if sandboxKeyboardOpen && !SnapshotRenderer.requested {
                Divider()
                KeyboardHostView(model: model)
                    .frame(height: 264)
                    .background(Color(UIColor {
                        $0.userInterfaceStyle == .dark
                            ? UIColor(white: 0.10, alpha: 1)
                            : UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
                    }))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: phase) { p in if p == .active { added = KeyboardStatus.isAdded() } }
        .onChange(of: nav?.tab) { newTab in
            if newTab != .features && sandboxKeyboardOpen { sandboxKeyboardOpen = false }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 530_000_000)
                if sandboxKeyboardOpen { cursorBlink.toggle() }
            }
        }
        .sheet(item: $selected) { item in
            NavigationStack {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 16) {
                        FeatureGlyphArt(id: item.id, large: true)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(mostoTint.opacity(0.08)))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.title3.weight(.bold))
                            Text(item.stat).font(.caption.weight(.medium)).foregroundStyle(mostoTint)
                        }
                    }
                    Text(item.detail).font(.body).fixedSize(horizontal: false, vertical: true)
                    if item.id == "scheme" {
                        NavigationLink("查看完整小鹤双拼键位表与练习") { XiaoheGuideView() }
                            .buttonStyle(.borderedProminent).tint(mostoTint)
                    } else if let lessonTitle = item.lessonTitle {
                        HStack(spacing: 10) {
                            Button("在互动练手中试一试") {
                                selected = nil
                                nav?.tryDemo(lessonTitle)
                            }
                            .buttonStyle(.borderedProminent).tint(mostoTint)
                            if item.id == "fix" {
                                NavigationLink("拇指落点热力图") { TouchDriftHeatmapView() }
                                    .buttonStyle(.bordered).tint(mostoTint)
                            }
                        }
                    } else {
                        NavigationLink("查看全部键盘用法") { UsageDetailView() }
                            .buttonStyle(.borderedProminent).tint(mostoTint)
                    }
                    Spacer()
                }
                .padding(20)
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { selected = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

/// Tab 2 (中间): Segmented single-screen hub switching between Enable and Interactive Playground.
private struct GuideHubScreen: View {
    @Binding var segment: Int
    @ObservedObject var model: PlaygroundModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $segment) {
                Text("启用键盘").tag(0)
                Text("互动练手").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color(UIColor.systemGroupedBackground))

            if segment == 0 {
                EnableScreen()
            } else {
                PlaygroundScreen(model: model)
            }
        }
    }
}

/// Tab 3 (设置): Real interactive Settings center for core typing & feel preferences (no App Group required).
private struct SettingsHubScreen: View {
    @ObservedObject var model: PlaygroundModel
    @Environment(\.scenePhase) private var phase
    @State private var added = KeyboardStatus.isAdded()

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(uiImage: mostoImage(model.appearance == 2 ? "MostoToyNight" : "MostoToy"))
                        .resizable().scaledToFit()
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mosto键盘 1.0").font(.headline)
                        Text("纯离线 · 零 AI · 零共享容器").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(added ? "已启用" : "待启用")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(added ? Color.green : mostoTint)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill((added ? Color.green : mostoTint).opacity(0.14)))
                }
                .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("输入方案与布局", systemImage: "character.textbox")
                        Spacer()
                        Text(model.layout == 1 ? "纯小鹤 2 键" : (model.layout == 2 ? "九宫格" : "全拼"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("输入方案", selection: $model.layout) {
                        Text("全拼").tag(0)
                        Text("小鹤双拼").tag(1)
                        Text("九宫格").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 2)

                if model.layout == 1 {
                    Toggle(isOn: $model.guide) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("小鹤键位助记提示")
                            Text("在字母键帽下标注声韵母，熟练后可关闭").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(mostoTint)
                }

                HStack {
                    Label("123 数字键盘", systemImage: "number.square")
                    Spacer()
                    Picker("123", selection: $model.numberPad) {
                        Text("完整页").tag(false)
                        Text("九宫格").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 136)
                }
            } header: {
                Text("输入方案")
            }

            Section {
                HStack {
                    Label("键盘风格", systemImage: "paintbrush.pointed")
                    Spacer()
                    Picker("风格", selection: $model.style) {
                        Text("Mosto").tag(0)
                        Text("简洁").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 136)
                }

                HStack {
                    Label("光线模式", systemImage: "sun.max")
                    Spacer()
                    Picker("光线", selection: $model.appearance) {
                        Text("自动").tag(0)
                        Text("日光").tag(1)
                        Text(model.style == 1 ? "夜光" : "夜灯").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 162)
                }
            } header: {
                Text("外观质感")
            }

            Section {
                Toggle(isOn: $model.autocorrect) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("按触点位置自动纠错")
                        Text("默认最优档，自动修正邻键误触与长句漏键").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(mostoTint)

                Toggle(isOn: $model.english) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("中英混输与成对标点")
                        Text("中文态直出 iOS / OK，成对括号按空格跳出").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(mostoTint)

                Toggle(isOn: $model.feedback) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("按键触感震动")
                        Text("按下瞬间轻脆反馈（系统键盘需开启完全访问）").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(mostoTint)

                Toggle(isOn: $model.keySound) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("系统按键音")
                        Text("跟随静音开关播放原声按键音").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(mostoTint)
            } header: {
                Text("纠错与手感")
            } footer: {
                Text("Mosto 坚持零 App Group 共享容器：以上开关即时生效于 App 内沙盒；系统键盘内偏好可在任意 App 长按表情键或点击候选栏快捷按钮独立调整，全程离线保存。")
            }

            Section("系统键盘与用法") {
                HStack {
                    Label("系统键盘状态", systemImage: added ? "checkmark.circle.fill" : "keyboard")
                        .foregroundStyle(added ? .green : mostoTint)
                    Spacer()
                    Text(added ? "已添加" : "未添加").foregroundStyle(.secondary)
                }
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: url) {
                        Label("打开系统设置添加或管理键盘", systemImage: "arrow.up.forward.app")
                    }
                }
                NavigationLink {
                    UsageDetailView()
                } label: {
                    Label("全部手势与键盘用法说明", systemImage: "slider.horizontal.3")
                }
            }

            Section("输入方案与隐私") {
                NavigationLink {
                    SpeedChallengeView()
                } label: {
                    Label("手感测速靶场（3 句实时计速）", systemImage: "gauge.with.dots.needle.67percent")
                }
                NavigationLink {
                    TouchDriftHeatmapView()
                } label: {
                    Label("拇指落点热力图（高斯触点学习）", systemImage: "scope")
                }
                NavigationLink {
                    XiaoheGuideView()
                } label: {
                    Label("小鹤双拼键位表与学习成本", systemImage: "square.grid.3x3")
                }
                ForEach(LegalText.docs, id: \.id) { doc in
                    NavigationLink {
                        LegalView(doc: doc)
                    } label: {
                        Label(doc.title, systemImage: aboutIcon(doc.id))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .onChange(of: phase) { p in if p == .active { added = KeyboardStatus.isAdded() } }
    }
}

/// R38 Signature Feature: 3-sentence live typing speed & accuracy arena running on the real embedded Mosto keyboard.
struct SpeedChallengeView: View {
    @StateObject private var model: PlaygroundModel = {
        let m = PlaygroundModel()
        m.step = lessons.count
        return m
    }()
    @State private var index = 0
    @State private var startedAt: Date? = nil
    @State private var finishedSeconds: Double? = nil
    @State private var totalChars = 0

    private let targets = [
        "今天天气真不错",
        "按偏了也能打对",
        "下周一准时开会",
    ]

    private var currentTarget: String { targets[min(index, targets.count - 1)] }
    private var isFinished: Bool { finishedSeconds != nil }

    private var cpm: Int {
        guard let elapsed = finishedSeconds ?? startedAt.map({ Date().timeIntervalSince($0) }), elapsed > 0.4 else { return 0 }
        let chars = isFinished ? totalChars : (totalChars + matchedPrefixCount)
        return Int((Double(chars) / elapsed * 60.0).rounded())
    }

    private var matchedPrefixCount: Int {
        let typed = Array(model.before)
        let target = Array(currentTarget)
        var n = 0
        while n < typed.count && n < target.count && typed[n] == target[n] { n += 1 }
        return n
    }

    private func resetChallenge() {
        index = 0
        startedAt = nil
        finishedSeconds = nil
        totalChars = 0
        model.clear()
        model.keyboardVisible = true
    }

    private func evaluateProgress() {
        guard !isFinished else { return }
        if startedAt == nil && (!model.before.isEmpty || !model.marked.isEmpty) {
            startedAt = Date()
        }
        if model.before.contains(currentTarget) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            totalChars += currentTarget.count
            if index + 1 < targets.count {
                index += 1
                model.clear()
            } else {
                finishedSeconds = max(0.5, Date().timeIntervalSince(startedAt ?? Date()))
                model.keyboardVisible = false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        metricTile(title: "进度", value: "\(min(index + (isFinished ? 1 : 0), targets.count))/\(targets.count)")
                        metricTile(title: "实时速度", value: cpm > 0 ? "\(cpm) 字/分" : "待开始")
                        metricTile(title: "方案", value: model.layout == 1 ? "小鹤" : (model.layout == 2 ? "九宫格" : "全拼"))
                    }

                    if isFinished, let sec = finishedSeconds {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(uiImage: mostoImage("MostoToy"))
                                    .resizable().scaledToFit()
                                    .frame(width: 60, height: 60)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("三句挑战完成").font(.title3.weight(.bold))
                                    Text(String(format: "共 %d 字 · 用时 %.1f 秒 · 均速 %d 字/分", totalChars, sec, cpm))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            HStack(spacing: 10) {
                                Button("再来一轮") { resetChallenge() }
                                    .buttonStyle(.borderedProminent).tint(mostoTint)
                                NavigationLink("查看落点热力图") { TouchDriftHeatmapView() }
                                    .buttonStyle(.bordered).tint(mostoTint)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("第 \(index + 1) 句 · 直接盲打").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Spacer()
                                Picker("方案", selection: Binding(
                                    get: { model.layout == 1 ? 1 : 0 },
                                    set: { model.layout = $0 }
                                )) {
                                    Text("全拼").tag(0)
                                    Text("小鹤").tag(1)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 112)
                            }
                            HStack(spacing: 2) {
                                ForEach(Array(currentTarget.enumerated()), id: \.offset) { i, ch in
                                    Text(String(ch))
                                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                                        .foregroundStyle(i < matchedPrefixCount ? mostoTint : Color.primary)
                                }
                            }
                            Text("支持按偏自动纠错；打完本句自动切下一句。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))

                        TextArea(model: model)
                    }
                }
                .padding(16)
            }
            .background(Color(UIColor.systemGroupedBackground))

            if model.keyboardVisible && !isFinished && !SnapshotRenderer.requested {
                Divider()
                KeyboardHostView(model: model)
                    .frame(height: 264)
                    .background(Color(UIColor {
                        $0.userInterfaceStyle == .dark
                            ? UIColor(white: 0.10, alpha: 1)
                            : UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
                    }))
            }
        }
        .navigationTitle("手感测速靶场")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("重置") { resetChallenge() }
            }
        }
        .onChange(of: model.before) { _ in evaluateProgress() }
        .onChange(of: model.marked) { _ in evaluateProgress() }
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
    }
}

/// R37 Signature Feature: Pure vector SwiftUI Canvas visualizing Mosto's Gaussian touch-offset model.
/// Shows real learned per-key thumb landing drift (or a realistic right-thumb demo preview before enough typing).
struct TouchDriftHeatmapView: View {
    @State private var showDemo = false
    @State private var globalOffset: (Double, Double) = KeyboardSettings.shared.touchOffset
    @State private var keyOffsets: [String: [Double]] = KeyboardSettings.shared.keyOffsets

    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    private static let demoGlobal: (Double, Double) = (0.09, 0.06)
    private static let demoKeys: [String: [Double]] = [
        "q": [0.16, 0.14], "w": [0.10, 0.11], "e": [0.06, 0.08], "i": [-0.09, 0.09], "o": [-0.14, 0.12], "p": [-0.18, 0.15],
        "a": [0.12, 0.05], "s": [0.07, 0.04], "j": [-0.06, 0.04], "k": [-0.08, 0.05], "l": [-0.12, 0.07],
        "z": [0.10, -0.06], "n": [-0.09, -0.05], "m": [-0.13, -0.07]
    ]

    private var hasRealData: Bool {
        abs(globalOffset.0) > 0.005 || abs(globalOffset.1) > 0.005 || !keyOffsets.isEmpty
    }
    private var activeGlobal: (Double, Double) { (showDemo || !hasRealData) ? Self.demoGlobal : globalOffset }
    private var activeKeys: [String: [Double]] { (showDemo || !hasRealData) ? Self.demoKeys : keyOffsets }

    private var driftSummary: String {
        let gx = activeGlobal.0, gy = activeGlobal.1
        let h = abs(gx) < 0.02 ? "水平居中" : (gx > 0 ? String(format: "右偏 %.0f%% 键宽", gx * 100) : String(format: "左偏 %.0f%% 键宽", -gx * 100))
        let v = abs(gy) < 0.02 ? "垂直居中" : (gy > 0 ? String(format: "偏下 %.0f%% 键高", gy * 100) : String(format: "偏上 %.0f%% 键高", -gy * 100))
        return "\(h) · \(v)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("高斯触点偏移热力图").font(.headline.weight(.bold))
                            Text(hasRealData && !showDemo ? "基于你已积累的本机落点学习" : "示意模式：展示右手拇指典型偏移补偿")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("视图", selection: $showDemo) {
                            Text("我的").tag(false)
                            Text("示意").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 112)
                    }

                    Canvas { ctx, size in
                        let kw = size.width / 10
                        let rowH = size.height / 3
                        let gapX: CGFloat = 4
                        let gapY: CGFloat = 6
                        let violet = Color(red: 0.39, green: 0.24, blue: 0.75)
                        let gold = Color(red: 0.90, green: 0.68, blue: 0.24)
                        let gx = activeGlobal.0, gy = activeGlobal.1

                        for (r, row) in Self.rows.enumerated() {
                            let startX = r == 0 ? 0.0 : (r == 1 ? 0.5 : 1.5)
                            for (cIdx, ch) in row.enumerated() {
                                let rect = CGRect(
                                    x: (startX + Double(cIdx)) * kw + gapX / 2,
                                    y: Double(r) * rowH + gapY / 2,
                                    width: kw - gapX,
                                    height: rowH - gapY
                                )
                                let ko = activeKeys[String(ch)]
                                let dx = max(-0.35, min(0.35, gx + (ko?.first ?? 0)))
                                let dy = max(-0.35, min(0.35, gy + (ko?.last ?? 0)))
                                let mag = hypot(dx, dy)
                                let intensity = min(1.0, mag / 0.28)

                                let keyPath = Path(roundedRect: rect, cornerRadius: 7)
                                ctx.fill(keyPath, with: .color(violet.opacity(0.06 + intensity * 0.22)))
                                ctx.stroke(keyPath, with: .color(violet.opacity(0.18 + intensity * 0.35)), lineWidth: 0.8)

                                let center = CGPoint(x: rect.midX, y: rect.midY)
                                let landed = CGPoint(x: center.x + dx * rect.width * 1.15, y: center.y + dy * rect.height * 1.15)

                                if mag > 0.03 {
                                    var vec = Path()
                                    vec.move(to: center)
                                    vec.addLine(to: landed)
                                    ctx.stroke(vec, with: .color(gold.opacity(0.85)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                                    let dot = CGRect(x: landed.x - 3, y: landed.y - 3, width: 6, height: 6)
                                    ctx.fill(Path(ellipseIn: dot), with: .color(gold))
                                }

                                ctx.draw(
                                    Text(String(ch))
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color.primary.opacity(0.82)),
                                    at: CGPoint(x: rect.midX, y: rect.minY + 12)
                                )
                            }
                        }
                    }
                    .frame(height: 168)

                    HStack(spacing: 12) {
                        Label(driftSummary, systemImage: "hand.point.up.left")
                            .font(.caption.weight(.medium)).foregroundStyle(mostoTint)
                        Spacer()
                        Text("已学 \(activeKeys.count) 键").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))

                Card(title: "原理说明") {
                    Usage(icon: "scope", title: "只移边缘，不改键心", text: "金色圆点代表你的拇指相对键心的实际落点方向。Mosto 的二维高斯模型会自动把热区边缘向你的落点微调，同时保持键心绝对准确。")
                    Divider()
                    Usage(icon: "lock.shield", title: "100% 本机学习", text: "落点参数只以坐标数字保存在本机，不含任何输入文本内容，可随时在键盘设置中一键清空。")
                }
            }
            .padding(16)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("拇指落点热力图")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            globalOffset = KeyboardSettings.shared.touchOffset
            keyOffsets = KeyboardSettings.shared.keyOffsets
        }
    }
}

/// The app's navigation, for the demo cards (none in the CI snapshot: the cards draw the same, their 试一试 does nothing).
private struct AppNavigationKey: EnvironmentKey { static let defaultValue: AppNavigation? = nil }
extension EnvironmentValues {
    var appNavigation: AppNavigation? {
        get { self[AppNavigationKey.self] }
        set { self[AppNavigationKey.self] = newValue }
    }
}

/// Everything on the home screen (shared by the app and the CI snapshot of it).
struct HomeContent: View {
    @Binding var text: String
    var snapshot = false

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            MostoHero()
            FeatureShowcase()
            MoreList(snapshot: snapshot)
            HomeFooter()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }
}

/// Every usage note, word for word, on a page of its own (the home page shows them as pictures).
struct UsageDetailContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
                        Card(title: "打字与纠错") {
                Usage(icon: "keyboard", title: "两种输入方案", text: "两种输入方案，在键盘设置里切换：全拼（默认；完整拼写，也可只打声母，如 bzd → 不知道）与小鹤双拼（每个字两个键，纯双拼，无形码）。选过的方案、九宫格等设置会一直记住，更新版本也不会被重置。")
                Divider()
                Usage(icon: "space", title: "空格、回车、删除", text: "空格：上屏首选　回车：上屏字母　删除：逐键回退，按住会加速，再久一点按词删除。")
                Divider()
                Usage(icon: "wand.and.stars", title: "按触点自动纠错", text: "首选浅色底 = 已按触点位置自动纠错，字下方小字写着改了哪里（如 hap→hao：按的是 hap，读作 hao）；第二个候选下标“原键”，是按原样读的结果。上屏后候选栏左侧出现 ↩ 和刚才按的字母，点它或立刻按删除都可撤回纠错。长句中间多按或漏按了一个键（全拼：jintiantiaqi → 今天天气），整句照样读对，后面的字继续连上。")
                Divider()
                Usage(icon: "text.append", title: "联想", text: "联想：中文上屏后，候选栏给出接下来常用的字词，点一下直接上屏并继续联想；按任意键即收起。")
                Divider()
                Usage(icon: "person.text.rectangle", title: "记住你的词", text: "词库里没有的名字、说法，分几次选出来一次后就记住了：下次完整拼出或只打声母（mstd → 摸索台灯）排第一，只打前半截排第二。")
                Divider()
                Usage(icon: "chevron.down", title: "全部候选", text: "候选栏右侧 ⌄ 展开全部候选；长按自己学过的词可以删掉它。")
            }
            Card(title: "中英混输与英文") {
                Usage(icon: "character.bubble", title: "中英混输", text: "中英混输：打 ok、ios、iphone 直接出 OK、iOS、iPhone；句子里夹英文词（woyongiphonedazi → 我用iPhone打字）也能读出。拼音本身拼得出的词（women、zhang）仍先给中文。")
                Divider()
                Usage(icon: "a.circle", title: "英文模式", text: "英文模式（中/英 切到“英”）也按触点纠错并给出候选：teh → the、dont → don't、im → I'm；空格时替换，删除可撤回；首字母自动大写，双击空格出句号。")
            }
            Card(title: "键盘与布局") {
                Usage(icon: "square.grid.3x3", title: "九宫格", text: "中文键盘可选全键盘或九宫格；九宫格两种方案都能用：打字时左列列出可能的拼音，点一下就定下这几个键，“分词”切开音节。")
                Divider()
                Usage(icon: "arrow.left.and.right", title: "光标、数字与标点", text: "按住空格左右拖动移动光标。123 打开数字符号页或九宫格数字键盘（键盘设置里选；用九宫格打字时默认九宫格数字，数字输入框也自动换成它）；长按“，”键可选：。？！、…：")
                Divider()
                Usage(icon: "face.smiling", title: "表情与键盘设置", text: "表情键：常用与八个分类，上下滑动，底栏一点跳到分类。按住表情键打开键盘设置：输入方案、九宫格、数字键盘、中英混输、自动纠错、震动与按键音、外观。")
            }
            Card(title: "Mosto 与外观") {
                Usage(icon: "hand.tap", title: "候选栏左边的 Mosto", text: "候选栏左边的 Mosto：轻点一下打开他的颜文字（右下角“返回”回到键盘），轻点两下切换日光 / 夜灯。")
                Divider()
                Usage(icon: "circle.lefthalf.filled", title: "外观", text: "外观：自动跟随系统浅色 / 深色；也可固定日光或夜灯（按键与 Mosto 换光，候选栏跟随系统，始终看得清）。")
            }
        }
    }
}

struct UsageDetailView: View {
    var body: some View {
        ScrollView { UsageDetailContent().padding(16) }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("全部用法")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Mosto at the top of the app, as a poster: the designer toy of the app icon (Mosto on the keyboard's own key with
/// the A and 中 keys) standing in the warm cone of a desk lamp — Moss & Otto's light — then the name set large, one
/// line on what it does, the schemes, and who Mosto is. Pictures and type only.
struct MostoHero: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blink = false
    @State private var hop = false

    private var night: Bool { scheme == .dark }
    /// Secondary text on the poster: ≥ 4.5:1 on the cream by day and on the violet at night.
    private var soft: Color { night ? Color.white.opacity(0.74) : Color(red: 0.36, green: 0.31, blue: 0.24) }
    private var ink: Color { night ? Color(red: 1.0, green: 0.95, blue: 0.86) : Color(red: 0.17, green: 0.10, blue: 0.38) }
    private var accent: Color { night ? Color(red: 1.0, green: 0.78, blue: 0.40) : Color(red: 0.39, green: 0.24, blue: 0.75) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(uiImage: mostoImage(night ? "MostoToyNight" : (blink ? "MostoToyBlink" : "MostoToy")))
                .resizable().scaledToFit()
                .frame(width: 250, height: 250)
                .scaleEffect(x: hop ? 1.05 : 1, y: hop ? 0.95 : 1, anchor: .bottom)
                .offset(y: hop ? -5 : 0)
                .frame(maxWidth: .infinity)
                .padding(.top, 6).padding(.bottom, -18)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !reduceMotion else { return }
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) { hop = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { hop = false }
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("MOSTO KEYBOARD")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).tracking(2.4)
                    .foregroundStyle(accent)
                Text("Mosto键盘")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(ink)
                Text("按偏了，也能打对。")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink.opacity(0.88))
                Text("全拼 · 小鹤双拼 · 九宫格")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(soft)
                Rectangle().fill(accent.opacity(0.35)).frame(width: 28, height: 2).padding(.vertical, 6)
                Text("Mosto，念快了像“魔头”：Moss 与 Otto 共同的另一面，住在键盘里的小魔王，歪戴小金冠。")
                    .font(.footnote).foregroundStyle(soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22).padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                LinearGradient(colors: night
                               ? [Color(red: 0.20, green: 0.13, blue: 0.42), Color(red: 0.08, green: 0.06, blue: 0.20)]
                               : [Color(red: 1.0, green: 0.96, blue: 0.86), Color(red: 0.98, green: 0.85, blue: 0.62)],
                               startPoint: .top, endPoint: .bottom)
                // the desk lamp's cone of light from above, falling on him
                LampCone()
                    .fill(LinearGradient(colors: [Color.white.opacity(night ? 0.0 : 0.55), Color(red: 1.0, green: 0.85, blue: 0.5).opacity(night ? 0.22 : 0.25), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .blur(radius: 14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color(red: 0.17, green: 0.10, blue: 0.38).opacity(night ? 0 : 0.12), radius: 16, y: 6)
        )
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .task {
            // by day an occasional quick blink (5–9 s), as in the keyboard; never with Reduce Motion
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 5...9) * 1_000_000_000))
                blink = true
                try? await Task.sleep(nanoseconds: 110_000_000)
                blink = false
            }
        }
    }
}

/// A lamp's cone of light: narrow at the top centre, widening down to the floor.
struct LampCone: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX - r.width * 0.06, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX + r.width * 0.06, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX + r.width * 0.42, y: r.minY + r.height * 0.62))
        p.addLine(to: CGPoint(x: r.midX - r.width * 0.42, y: r.minY + r.height * 0.62))
        p.closeSubpath()
        return p
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                        .shadow(color: Color(red: 0.17, green: 0.10, blue: 0.38).opacity(scheme == .dark ? 0 : 0.06), radius: 10, y: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(scheme == .dark ? Color.white.opacity(0.07) : Color(red: 0.17, green: 0.10, blue: 0.38).opacity(0.06), lineWidth: 0.5)
                )
        }
    }
}

struct Step: View {
    let n: Int
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(mostoTint))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Usage: View {
    let icon: String
    var title: String? = nil
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: icon)
            VStack(alignment: .leading, spacing: 3) {
                if let title { Text(title).font(.subheadline.weight(.semibold)) }
                Text(text).font(.subheadline).foregroundStyle(title == nil ? Color.primary : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A symbol on a small tinted vinyl tile (the keyboard's violet), as iOS Settings marks its rows.
struct IconTile: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(mostoTint)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [mostoTint.opacity(0.10), mostoTint.opacity(0.20)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(mostoTint.opacity(0.18), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

struct LightTile: View {
    let image: String
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 6) {
            Image(uiImage: mostoImage(image)).resizable().scaledToFit().frame(height: 84)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(image.hasSuffix("Night") ? Color(red: 0.11, green: 0.13, blue: 0.27) : Color(red: 0.99, green: 0.93, blue: 0.80)))
                .accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

func aboutIcon(_ id: String) -> String {
    switch id { case "privacy": return "hand.raised"; case "terms": return "doc.text"; default: return "shippingbox" }
}

/// One legal page (隐私政策 / 用户协议与免责声明 / 开源许可): the same text as the hosted page, readable offline.
struct LegalView: View {
    let doc: LegalText.Doc
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("生效日期：\(LegalText.effective)").font(.footnote).foregroundStyle(.secondary)
                ForEach(Array(doc.sections.enumerated()), id: \.offset) { _, section in
                    Card(title: section.0) {
                        ForEach(Array(section.1.enumerated()), id: \.offset) { _, item in
                            switch item {
                            case .text(let t):
                                Text(linked(t)).fixedSize(horizontal: false, vertical: true)
                            case .bullets(let list):
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(list.enumerated()), id: \.offset) { _, b in
                                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                                            Text("•").foregroundStyle(.secondary)
                                            Text(linked(b)).fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if let u = URL(string: LegalText.site + "/" + doc.id + ".html") {
                    Link("网页版：" + u.absoluteString, destination: u).font(.footnote)
                }
            }
            .padding(16)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle(doc.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Plain text with its web addresses made tappable.
    private func linked(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return a }
        for m in det.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let url = m.url, let r = Range(m.range, in: s), let ar = Range(r, in: a) else { continue }
            a[ar].link = url
        }
        return a
    }
}

