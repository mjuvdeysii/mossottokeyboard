import SwiftUI
import UIKit

@main
struct MossOttoKeyboardApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// Focused 3-tab Companion architecture: Companion Home (`companion`), Guide (`guide`), and About (`about`).
enum AppTab: Int, CaseIterable, Hashable {
    case companion
    case guide
    case about
}

private struct AppNavigationKey: EnvironmentKey { static let defaultValue: AppNavigation? = nil }
extension EnvironmentValues {
    var appNavigation: AppNavigation? {
        get { self[AppNavigationKey.self] }
        set { self[AppNavigationKey.self] = newValue }
    }
}

@MainActor
final class AppNavigation: ObservableObject {
    @Published var tab: AppTab = .companion
    let family: FamilyStageModel
    let volume: VolumeMonitor

    init() {
        self.family = FamilyStageModel()
        self.volume = VolumeMonitor()
    }

    func focusFamilyMember(_ member: FamilyMember) {
        family.focusFromRoster(member)
        tab = .companion
    }
}

struct ContentView: View {
    @StateObject private var nav = AppNavigation()

    var body: some View {
        TabView(selection: $nav.tab) {
            NavigationStack {
                CompanionHomeScreen(family: nav.family, volume: nav.volume)
                    .navigationTitle("Mosto键盘")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem { Label("伴侣", systemImage: "lamp.desk.fill") }
            .tag(AppTab.companion)

            NavigationStack {
                GuideScreen(volume: nav.volume)
                    .navigationTitle("使用指南")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem { Label("指南", systemImage: "book.pages.fill") }
            .tag(AppTab.guide)

            NavigationStack {
                AboutScreen(nav: nav)
                    .navigationTitle("关于")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem { Label("关于", systemImage: "info.circle.fill") }
            .tag(AppTab.about)
        }
        .environment(\.appNavigation, nav)
        .tint(mostoTint)
        .onAppear { nav.volume.startObserving() }
        .modifier(VolumeSheetPresenter(volume: nav.volume, family: nav.family))
        .task {
            if SnapshotRenderer.requested,
               let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                SnapshotRenderer.run(in: scene)
            }
        }
    }
}

private struct VolumeSheetPresenter: ViewModifier {
    @ObservedObject var volume: VolumeMonitor
    @ObservedObject var family: FamilyStageModel

    func body(content: Content) -> some View {
        content.sheet(isPresented: $volume.showSheet) {
            VolumeCheckSheet(monitor: volume) {
                family.syncSoundFromSettings()
            }
            .presentationDetents([.fraction(0.58), .large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Tab 1: Companion Home (伴侣)

private struct CompanionHomeScreen: View {
    @ObservedObject var family: FamilyStageModel
    @ObservedObject var volume: VolumeMonitor
    @Environment(\.scenePhase) private var phase
    @State private var added = KeyboardStatus.isAdded()
    @State private var verifyText = ""
    @FocusState private var typing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if volume.showHighBanner && family.soundEnabled {
                    VolumeHighBanner(monitor: volume) {
                        family.soundEnabled = false
                        KeyboardSettings.shared.keySound = false
                        volume.dismissHighBanner()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                FamilyLampStageView(model: family, volume: volume)

                CompanionEnableCard(
                    added: added,
                    verifyText: $verifyText,
                    typing: $typing,
                    onVerified: { family.celebrateVerification() }
                )

                CompanionCapabilitiesSection()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(
            MossOttoStyle.canvas
                .ignoresSafeArea()
                .onTapGesture { typing = false }
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                VolumeBadgePill(monitor: volume, soundEnabled: family.soundEnabled)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("收起") { typing = false }
                    .fontWeight(.semibold)
            }
        }
        .onChange(of: phase) { nextPhase in
            if nextPhase == .active {
                added = KeyboardStatus.isAdded()
            }
        }
        .animation(.easeOut(duration: 0.2), value: volume.showHighBanner)
    }
}

/// Real system-keyboard enablement guidance and native `TextField` verification (no fake typing sandbox).
struct CompanionEnableCard: View {
    let added: Bool
    @Binding var verifyText: String
    var typing: FocusState<Bool>.Binding
    var onVerified: () -> Void = {}

    private var verified: Bool {
        EnableContent.isVerificationPassed(verifyText)
    }

    var body: some View {
        Card(title: "系统键盘") {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill((verified ? MossOttoStyle.moss : (added ? MossOttoStyle.moss : MossOttoStyle.lampAmber)).opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: verified || added ? "checkmark.circle.fill" : "keyboard.badge.ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(verified || added ? MossOttoStyle.moss : MossOttoStyle.lampAmber)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(verified ? "系统键盘已验通" : (added ? "已添加到系统键盘" : "三步启用 Mosto键盘"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MossOttoStyle.inkPrimary)
                    Text(added ? "在任意输入框长按地球键即可切换" : "设置 › 通用 › 键盘 › 添加新键盘")
                        .font(.caption)
                        .foregroundStyle(MossOttoStyle.inkSecondary)
                }

                Spacer(minLength: 4)

                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: url) {
                        Text(added ? "系统设置" : "去添加")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(added ? MossOttoStyle.violet : MossOttoStyle.onViolet)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(added ? MossOttoStyle.violet.opacity(0.12) : MossOttoStyle.violet)
                            )
                    }
                }
            }

            if !added {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    stepRow(index: "1", text: "打开 系统设置 › 通用 › 键盘 › 键盘")
                    stepRow(index: "2", text: "轻点 添加新键盘，选择 Mosto键盘")
                    stepRow(index: "3", text: "不开启“允许完全访问”也能正常打字；开启后仅用于按键震动与声效")
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("真机键盘验证")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MossOttoStyle.inkSecondary)
                    Spacer()
                    if verified {
                        Label("已验通", systemImage: "checkmark.circle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(MossOttoStyle.moss)
                    } else if typing.wrappedValue {
                        Button("收起键盘") { typing.wrappedValue = false }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MossOttoStyle.violet)
                    } else {
                        NavigationLink {
                            EnableScreen()
                        } label: {
                            HStack(spacing: 3) {
                                Text("详细步骤")
                                Image(systemName: "chevron.right")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(MossOttoStyle.inkSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Group {
                    if SnapshotRenderer.requested {
                        Text("切换到 Mosto 系统键盘，打一句“你好”试试")
                            .font(.subheadline)
                            .foregroundStyle(MossOttoStyle.inkSecondary.opacity(0.68))
                            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    } else {
                        HStack(spacing: 8) {
                            TextField("切换到 Mosto 系统键盘，打一句“你好”试试", text: $verifyText)
                                .focused(typing)
                                .font(.subheadline)
                                .frame(minHeight: 34)
                            if !verifyText.isEmpty {
                                Button("清空") {
                                    verifyText = ""
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MossOttoStyle.violet)
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MossOttoStyle.surfaceMuted)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(verified ? MossOttoStyle.moss.opacity(0.55) : Color.clear, lineWidth: 1)
                )
                .onChange(of: verified) { passed in
                    if passed {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onVerified()
                    }
                }
            }
        }
    }

    private func stepRow(index: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(index)
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(MossOttoStyle.violet)
                .frame(width: 16, height: 16)
                .background(Circle().fill(MossOttoStyle.violet.opacity(0.12)))
            Text(text)
                .font(.caption)
                .foregroundStyle(MossOttoStyle.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Concise commercial overview of what Mosto键盘 does and where real settings live.
struct CompanionCapabilitiesSection: View {
    struct Item: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let title: String
        let detail: String
    }

    static let items: [Item] = [
        Item(
            id: "schemes",
            icon: "keyboard",
            tint: MossOttoStyle.violet,
            title: "小鹤双拼与全拼",
            detail: "支持小鹤双拼（两键一字）、标准全拼与九宫格，按偏相邻键也能自动纠正。"
        ),
        Item(
            id: "gestures",
            icon: "character.cursor.ibeam",
            tint: MossOttoStyle.ottoIndigo,
            title: "中英混输与快捷手势",
            detail: "中文模式下可直接打出常见英文词，标点轻上滑出副符号，空格左右滑移光标。"
        ),
        Item(
            id: "settings",
            icon: "slider.horizontal.3",
            tint: MossOttoStyle.lampAmber,
            title: "键盘设置就在键盘内",
            detail: "为保护隐私，本应用与系统键盘彼此独立；方案、外观与声效请在键盘内按住表情键调整。"
        ),
        Item(
            id: "offline",
            icon: "lock.shield",
            tint: MossOttoStyle.moss,
            title: "纯本机离线",
            detail: "不联网、不读取剪贴板，也不用登录账号，词库与个人输入习惯只留在你的手机上。"
        ),
    ]

    var body: some View {
        Card(title: "伴侣说明") {
            ForEach(Array(Self.items.enumerated()), id: \.element.id) { idx, item in
                if idx > 0 { Divider() }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(item.tint)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(item.tint.opacity(0.12)))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MossOttoStyle.inkPrimary)
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(MossOttoStyle.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Tab 2: Guide (指南 — 双拼图谱 & 手势图鉴)

private enum GuideSection: Int, CaseIterable, Identifiable {
    case xiaohe
    case atlas

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .xiaohe: return "双拼图谱"
        case .atlas: return "手势图鉴"
        }
    }
}

private struct GuideScreen: View {
    @ObservedObject var volume: VolumeMonitor
    @State private var section: GuideSection = .xiaohe

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("指南分类", selection: $section) {
                    ForEach(GuideSection.allCases) { sec in
                        Text(sec.title).tag(sec)
                    }
                }
                .pickerStyle(.segmented)

                switch section {
                case .xiaohe:
                    XiaoheGuideContent(volume: volume)
                case .atlas:
                    GestureAtlasContent()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(MossOttoStyle.canvas.ignoresSafeArea())
    }
}

struct GestureAtlasContent: View {
    enum MostoPreviewAction: String, CaseIterable {
        case kaomoji = "左侧 Mosto"
        case toggleLight = "右侧日月"
        case yawn = "长按 Mosto"

        var shortEffect: String {
            switch self {
            case .kaomoji: return "颜文字"
            case .toggleLight: return "换光效"
            case .yawn: return "打哈欠"
            }
        }

        var badge: String {
            switch self {
            case .kaomoji: return "(=^･ω･^=)  无框轻点 · 200+ 颜文字"
            case .toggleLight: return "日光与夜灯一键切换 · Mosto 同步亮尾"
            case .yawn: return "按住 0.4s 慵懒打哈欠 · 软触反馈"
            }
        }
    }

    @State private var selectedMosto: MostoPreviewAction? = nil
    @State private var mostoBounce = false
    @State private var nightOverride: Bool? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var previewNight: Bool { nightOverride ?? (colorScheme == .dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "高频核心手势") {
                atlasRow(
                    cap: "，↑。",
                    title: "标点上滑副符号",
                    chips: ["，↑。", "/↑、", "¥↑$", "（↑【"]
                )
                Divider()
                atlasRow(
                    cap: "123↗",
                    title: "滑键借层与双手和弦",
                    chips: ["按住滑键直出", "松手自动回弹"]
                )
                Divider()
                atlasRow(
                    symbol: "arrow.left.and.right",
                    title: "空格游标与智能跳出",
                    chips: ["左右滑移游标", "括号空格跳出"]
                )
                Divider()
                atlasRow(
                    symbol: "delete.left",
                    title: "左划清空与逐词快删",
                    chips: ["左划一键清空", "长按 >1s 删词"]
                )
                Divider()
                atlasRow(
                    symbol: "slider.horizontal.3",
                    title: "长按表情键开控制台",
                    chips: ["轻点选表情", "按住打开设置"]
                )
            }

            Card(title: "纠错、心算与日期") {
                atlasRow(
                    symbol: "wand.and.stars",
                    title: "整句触点纠错",
                    chips: ["偏键自动读准", "空格后 \u{21A9}\u{FE0E} 撤回"]
                )
                Divider()
                atlasRow(
                    symbol: "plus.forwardslash.minus",
                    title: "四则心算与相对日期",
                    chips: ["286/4= 空格连算", "下周一 联想日期"]
                )
                Divider()
                atlasRow(
                    cap: "bzd",
                    title: "首字母简拼与自造词",
                    chips: ["bzd → 不知道", "长按候选可忘词"]
                )
            }

            Card(title: "空闲顶栏与声光彩蛋") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(uiImage: mostoImage(activePreviewSprite))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .scaleEffect((mostoBounce && !reduceMotion) ? 1.16 : 1.0)
                            .onTapGesture { triggerMostoPreview(.kaomoji) }
                            .onLongPressGesture(minimumDuration: 0.4) { triggerMostoPreview(.yawn) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("迷你顶栏 Mosto，轻点颜文字，长按打哈欠")

                        Text(selectedMosto?.badge ?? "轻点左侧 Mosto 或右侧日月图标试玩")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(previewNight ? Color.white.opacity(0.74) : MossOttoStyle.inkSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer(minLength: 4)

                        Button {
                            triggerMostoPreview(.toggleLight)
                        } label: {
                            Image(systemName: previewNight ? "moon.fill" : "sun.max.fill")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(
                                    previewNight
                                        ? Color(uiColor: MossOttoStyle.hex(0xE0BE74))
                                        : MossOttoStyle.inkSecondary
                                )
                                .frame(width: 34, height: 28)
                                .background(
                                    Capsule().fill(
                                        previewNight
                                            ? Color.white.opacity(0.14)
                                            : Color(uiColor: MossOttoStyle.hex(0x633EBF, 0.10))
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("迷你顶栏切换日光与夜灯")

                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14.5, weight: .regular))
                            .foregroundStyle(previewNight ? Color.white.opacity(0.68) : MossOttoStyle.inkSecondary)
                            .frame(width: 26, height: 28)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(previewNight ? Color(uiColor: MossOttoStyle.hex(0x211E2D)) : Color(uiColor: MossOttoStyle.hex(0xECEAF3)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(previewNight ? Color.white.opacity(0.10) : MossOttoStyle.hairline, lineWidth: 0.7)
                    )

                    HStack(spacing: 6) {
                        ForEach(MostoPreviewAction.allCases, id: \.rawValue) { act in
                            mostoActionTile(action: act, effect: act.shortEffect)
                        }
                    }
                }
            }
        }
    }

    private var activePreviewSprite: String {
        if selectedMosto == .yawn { return "MostoYawn" }
        if previewNight { return "MostoNight" }
        if selectedMosto == .kaomoji { return "MostoBlink" }
        return "Mosto"
    }

    private func triggerMostoPreview(_ action: MostoPreviewAction) {
        let style: UIImpactFeedbackGenerator.FeedbackStyle = action == .yawn ? .soft : (action == .toggleLight ? .medium : .light)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        withAnimation(reduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.65)) {
            if action == .toggleLight { nightOverride = !previewNight }
            selectedMosto = action
            mostoBounce = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.easeOut(duration: 0.14)) {
                mostoBounce = false
            }
        }
    }

    private func mostoActionTile(action: MostoPreviewAction, effect: String) -> some View {
        let active = selectedMosto == action
        return Button {
            triggerMostoPreview(action)
        } label: {
            VStack(spacing: 2) {
                Text(action.rawValue)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(active ? MossOttoStyle.onViolet : MossOttoStyle.violet)
                Text(effect)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(active ? MossOttoStyle.onViolet : MossOttoStyle.inkPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(active ? MossOttoStyle.violet : MossOttoStyle.surfaceMuted))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func atlasRow(cap: String = "", symbol: String? = nil, title: String, chips: [String]) -> some View {
        HStack(alignment: .center, spacing: 12) {
            MonolithKeycapView(label: cap, symbol: symbol, cornerRadius: 9)
                .frame(width: 58, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MossOttoStyle.inkPrimary)
                WrapLayout(spacing: 5, lineSpacing: 4) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(MossOttoStyle.inkSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(MossOttoStyle.surfaceMuted))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Tab 3: About & IP Family (关于)

private struct AboutScreen: View {
    @ObservedObject var nav: AppNavigation
    @Environment(\.scenePhase) private var phase
    @State private var added = KeyboardStatus.isAdded()

    var body: some View {
        ScrollView {
            AboutCompanionContent(added: added, nav: nav)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
        .background(MossOttoStyle.canvas.ignoresSafeArea())
        .onChange(of: phase) { nextPhase in
            if nextPhase == .active { added = KeyboardStatus.isAdded() }
        }
    }
}

/// Commercial About page highlighting the OTTOSSOM IP family, plain-language privacy promise, and legal docs.
struct AboutCompanionContent: View {
    let added: Bool
    var nav: AppNavigation? = nil

    @MainActor
    static func renderSnapshotSizeForTests(width: CGFloat) -> CGSize {
        let r = ImageRenderer(content: AboutCompanionContent(added: true).frame(width: width))
        r.scale = 2.0
        return r.uiImage?.size ?? .zero
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "OTTOSSOM 家族") {
                ForEach(Array(FamilyMember.allCases.enumerated()), id: \.element.id) { idx, member in
                    if idx > 0 { Divider() }
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        nav?.focusFamilyMember(member)
                    } label: {
                        HStack(spacing: 12) {
                            Image(uiImage: mostoImage(member.spriteName(atmosphere: .day, reacting: false)))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44, height: 44)
                                .padding(4)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(MossOttoStyle.surfaceMuted)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(member.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(MossOttoStyle.inkPrimary)
                                    Text(member.chineseRole)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(member.accentColor)
                                }
                                Text(member.bio)
                                    .font(.caption)
                                    .foregroundStyle(MossOttoStyle.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MossOttoStyle.inkSecondary.opacity(0.45))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Card(title: "隐私承诺") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    trustTile(icon: "wifi.slash", tint: MossOttoStyle.moss, title: "全程不联网", subtitle: "零网络请求")
                    trustTile(icon: "doc.on.clipboard", tint: MossOttoStyle.moss, title: "不读剪贴板", subtitle: "也不读通讯录")
                    trustTile(icon: "hand.raised.fill", tint: MossOttoStyle.violet, title: "无需完全访问", subtitle: "不授权照常打字")
                    trustTile(icon: "iphone", tint: MossOttoStyle.lampAmber, title: "只留在手机里", subtitle: "随删随清")
                }

                Divider()

                cardLink {
                    PrivacyCommitmentView()
                } label: {
                    aboutRow(
                        icon: "lock.shield",
                        iconColor: MossOttoStyle.moss,
                        title: "本机数据与隐私说明",
                        subtitle: added ? "当前系统键盘已启用 · 独立存放于键盘内" : "启用后可在系统键盘设置内管理学习记录"
                    )
                }
            }

            Card(title: "条款与开源许可") {
                ForEach(Array(LegalText.docs.enumerated()), id: \.element.id) { idx, doc in
                    if idx > 0 { Divider() }
                    cardLink {
                        LegalView(doc: doc)
                    } label: {
                        aboutRow(
                            icon: aboutIcon(doc.id),
                            iconColor: MossOttoStyle.inkSecondary,
                            title: doc.title,
                            subtitle: nil
                        )
                    }
                }
            }

            StudioVersionFooter()
        }
    }

    private func trustTile(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MossOttoStyle.inkPrimary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(MossOttoStyle.inkSecondary)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MossOttoStyle.surfaceMuted))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func cardLink<Dest: View, Label: View>(
        @ViewBuilder destination: () -> Dest,
        @ViewBuilder label: () -> Label
    ) -> some View {
        if SnapshotRenderer.requested {
            label()
        } else {
            NavigationLink(destination: destination(), label: label)
                .buttonStyle(.plain)
        }
    }

    private func aboutRow(icon: String, iconColor: Color, title: String, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(iconColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MossOttoStyle.inkPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(MossOttoStyle.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MossOttoStyle.inkSecondary.opacity(0.5))
        }
        .contentShape(Rectangle())
    }
}

private struct StudioVersionFooter: View {
    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "Mosto键盘 \(short)（Build \(build)）"
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(versionLine)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MossOttoStyle.inkSecondary)
            Text("OTTOSSOM 家族 · 纯离线中文输入法")
                .font(.caption2)
                .foregroundStyle(MossOttoStyle.inkSecondary.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

// MARK: - Consumer Privacy Detail & Legal Views

private struct PrivacyCommitmentView: View {
    var body: some View {
        ScrollView {
            PrivacyCommitmentContent()
                .padding(16)
        }
        .background(MossOttoStyle.canvas.ignoresSafeArea())
        .navigationTitle("隐私说明")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyCommitmentContent: View {
    @MainActor
    static func renderSnapshotSizeForTests(width: CGFloat) -> CGSize {
        let r = ImageRenderer(content: PrivacyCommitmentContent().frame(width: width))
        r.scale = 2.0
        return r.uiImage?.size ?? .zero
    }

    struct RowItem: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let title: String
        let detail: String
    }

    static let items: [RowItem] = [
        RowItem(
            id: "local-only",
            icon: "cpu",
            tint: MossOttoStyle.violet,
            title: "全部计算都在手机本地完成",
            detail: "词库和语料模型直接随应用安装在设备里，不依赖云端，也不接入第三方大模型。"
        ),
        RowItem(
            id: "independent",
            icon: "lock.shield",
            tint: MossOttoStyle.moss,
            title: "键盘与伴侣应用彼此独立",
            detail: "系统键盘的学习记录与输入设置只存放在键盘扩展自己的本机空间，不会跨应用读写。"
        ),
        RowItem(
            id: "full-access",
            icon: "hand.raised",
            tint: MossOttoStyle.lampAmber,
            title: "“允许完全访问”只用于声效与震动",
            detail: "不开启也能使用全部输入、双拼、全拼与自动纠错功能；开启后也绝不联网或读取剪贴板。"
        ),
        RowItem(
            id: "clear-anytime",
            icon: "trash",
            tint: MossOttoStyle.ottoIndigo,
            title: "随时可一键清空",
            detail: "你可以在系统键盘内打开设置，前往“学习”页面一键清空已学词语与触点习惯，或卸载应用彻底移除。"
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "你的输入只属于你自己") {
                ForEach(Array(Self.items.enumerated()), id: \.element.id) { idx, item in
                    if idx > 0 { Divider() }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(item.tint)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(item.tint.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MossOttoStyle.inkPrimary)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(MossOttoStyle.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

struct LegalView: View {
    let doc: LegalText.Doc

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("生效日期：\(LegalText.effective)")
                    .font(.footnote)
                    .foregroundStyle(MossOttoStyle.inkSecondary)
                ForEach(Array(doc.sections.enumerated()), id: \.offset) { _, section in
                    Card(title: section.0) {
                        ForEach(Array(section.1.enumerated()), id: \.offset) { _, item in
                            switch item {
                            case .text(let t):
                                Text(linked(t))
                                    .foregroundStyle(MossOttoStyle.inkPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            case .bullets(let list):
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(list.enumerated()), id: \.offset) { _, b in
                                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                                            Text("•").foregroundStyle(MossOttoStyle.inkSecondary)
                                            Text(linked(b))
                                                .foregroundStyle(MossOttoStyle.inkPrimary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if let u = URL(string: LegalText.site + "/" + doc.id + ".html") {
                    Link("网页版：" + u.absoluteString, destination: u)
                        .font(.footnote)
                }
            }
            .padding(16)
        }
        .background(MossOttoStyle.canvas.ignoresSafeArea())
        .navigationTitle(doc.title)
        .navigationBarTitleDisplayMode(.inline)
    }

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
