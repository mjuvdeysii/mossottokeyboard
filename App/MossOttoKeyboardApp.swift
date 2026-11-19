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
                FeaturesHubScreen()
                    .navigationTitle("Mosto键盘")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("特性", systemImage: "sparkles") }
            .tag(AppTab.features)
            NavigationStack {
                GuideHubScreen(segment: $nav.guideSegment, model: nav.playground)
                    .navigationTitle("上手")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("上手", systemImage: "hand.tap") }
            .tag(AppTab.guide)
            NavigationStack {
                SettingsHubScreen()
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
    FeatureItem(id: "scheme", icon: "keyboard", title: "双拼与全拼", stat: "小鹤 2 键 · 全拼默认",
                detail: "同时内置全拼与纯小鹤双拼（每字固定 2 键、无形码），设置跨版本保留；可在键盘设置里随时切换并开启键位提示。", lessonTitle: nil),
    FeatureItem(id: "mix", icon: "character.bubble", title: "混输与九宫格", stat: "免切英文 · 九宫格",
                detail: "句子中直接夹打 ok、iOS、iPhone 自动识别大小写；中文全键盘与九宫格均支持完整纠错与联想。", lessonTitle: "中英混输"),
    FeatureItem(id: "kaomoji", icon: "face.smiling", title: "颜文字与彩蛋", stat: "126 款 · 情绪联动",
                detail: "内置 8 大情绪 126 款颜文字；输入日期、时间、星期自动动态输出，输入晚安、开心、可爱、宝宝等触发 Mosto 彩蛋。", lessonTitle: nil),
    FeatureItem(id: "glass", icon: "square.on.square", title: "双风格质感", stat: "iOS 原生 · Mosto 潮玩",
                detail: "简洁模式 1:1 复刻系统液态玻璃高度与纯净键帽；Mosto 模式采用 3D 软胶厚底沿与日/夜灯双光，一键切换。", lessonTitle: nil),
    FeatureItem(id: "offline", icon: "lock.shield", title: "纯离线 · 零 AI", stat: "0 联网 · 0 追踪",
                detail: "键盘扩展全程本机计算，不含任何网络请求、剪贴板读取或第三方 SDK，保持默认权限即可正常打字。", lessonTitle: nil),
]

/// Tab 1 (首屏): Zero-scroll single-screen Bento hub showcasing all keyboard features via tap-to-drill.
private struct FeaturesHubScreen: View {
    @Environment(\.appNavigation) private var nav
    @Environment(\.scenePhase) private var phase
    @State private var added = KeyboardStatus.isAdded()
    @State private var previewPlain = false
    @State private var selected: FeatureItem? = nil

    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(uiImage: mostoImage(previewPlain ? "MostoToyBlink" : "MostoToy"))
                    .resizable().scaledToFit()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("按偏了，也能打对").font(.headline)
                    Text(previewPlain ? "简洁模式 · 1:1 原生液态玻璃" : "Mosto 潮玩 · 3D 软胶双光")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Picker("", selection: $previewPlain) {
                    Text("潮玩").tag(false)
                    Text("简洁").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 104)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))

            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(featureItems) { item in
                    Button { selected = item } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: item.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(mostoTint)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 2)
                            Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(item.stat).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxHeight: .infinity)

            Button {
                nav?.guideSegment = added ? 1 : 0
                nav?.tab = .guide
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: added ? "checkmark.circle.fill" : "keyboard.badge.ellipsis")
                        .foregroundStyle(added ? Color.green : mostoTint)
                    Text(added ? "Mosto键盘已就绪 · 点击进入互动练手" : "尚未启用键盘 · 30 秒去完成添加")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(mostoTint)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
        .onChange(of: phase) { p in if p == .active { added = KeyboardStatus.isAdded() } }
        .sheet(item: $selected) { item in
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: item.icon).font(.title2.weight(.semibold)).foregroundStyle(mostoTint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.title3.weight(.bold))
                            Text(item.stat).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(item.detail).font(.body).fixedSize(horizontal: false, vertical: true)
                    if item.id == "scheme" {
                        NavigationLink("查看完整小鹤双拼键位表与练习") { XiaoheGuideView() }
                            .buttonStyle(.borderedProminent).tint(mostoTint)
                    } else if let lessonTitle = item.lessonTitle {
                        Button("在互动练手中试一试") {
                            selected = nil
                            nav?.tryDemo(lessonTitle)
                        }
                        .buttonStyle(.borderedProminent).tint(mostoTint)
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

/// Tab 3 (设置): Zero-scroll native Settings center with direct drill-downs.
private struct SettingsHubScreen: View {
    @Environment(\.scenePhase) private var phase
    @State private var added = KeyboardStatus.isAdded()

    var body: some View {
        List {
            Section("键盘状态与快捷设置") {
                HStack {
                    Label("键盘启用状态", systemImage: added ? "checkmark.circle.fill" : "keyboard")
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
                    Label("键盘内偏好与全部用法（风格 / 方案 / 震动）", systemImage: "slider.horizontal.3")
                }
            }

            Section("输入方案与隐私") {
                NavigationLink {
                    XiaoheGuideView()
                } label: {
                    Label("小鹤双拼键位表与学习成本", systemImage: "square.grid.3x3")
                }
                ForEach(LegalText.docs, id: \.id) {
                    doc in
                    NavigationLink {
                        LegalView(doc: doc)
                    } label: {
                        Label(doc.title, systemImage: aboutIcon(doc.id))
                    }
                }
            }

            Section {
                HStack {
                    Text("Mosto键盘 1.0").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Text("纯离线 · 零 AI · 零共享容器").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .onChange(of: phase) { p in if p == .active { added = KeyboardStatus.isAdded() } }
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
                Usage(icon: "face.smiling", title: "表情与键盘设置", text: "😊 表情：常用与八个分类，上下滑动，底栏一点跳到分类。按住 😊 打开键盘设置：输入方案、九宫格、数字键盘、中英混输、自动纠错、震动与按键音、外观。")
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

