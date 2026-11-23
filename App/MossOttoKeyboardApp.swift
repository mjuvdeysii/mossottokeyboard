import SwiftUI

@main
struct MossOttoKeyboardApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// Minimal 2-space companion app: Desk-Lamp Studio (`studio`) + Reference & About (`handbook`).
enum AppTab: Hashable { case studio, handbook }

private struct AppNavigationKey: EnvironmentKey { static let defaultValue: AppNavigation? = nil }
extension EnvironmentValues {
    var appNavigation: AppNavigation? {
        get { self[AppNavigationKey.self] }
        set { self[AppNavigationKey.self] = newValue }
    }
}

@MainActor
final class AppNavigation: ObservableObject {
    @Published var tab: AppTab = .studio
    let playground: PlaygroundModel
    let volume: VolumeMonitor

    init() {
        self.playground = PlaygroundModel()
        self.volume = VolumeMonitor()
    }

    func tryDemo(_ title: String) {
        guard let lesson = demoLessons[title], let i = lessons.firstIndex(where: { $0.title == lesson }) else { return }
        playground.jump(to: i)
        tab = .studio
    }
}

struct ContentView: View {
    @StateObject private var nav = AppNavigation()

    var body: some View {
        TabView(selection: $nav.tab) {
            NavigationStack {
                StudioScreen(model: nav.playground, volume: nav.volume)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.hidden, for: .navigationBar)
            }
            .tabItem { Label("台灯工作台", systemImage: "lamp.desk.fill") }
            .tag(AppTab.studio)

            NavigationStack {
                HandbookScreen(nav: nav)
                    .navigationTitle("手册与关于")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("手册与关于", systemImage: "book.closed.fill") }
            .tag(AppTab.handbook)
        }
        .environment(\.appNavigation, nav)
        .tint(mostoTint)
        .onAppear { nav.volume.startObserving() }
        .modifier(VolumeSheetPresenter(volume: nav.volume, playground: nav.playground))
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
    @ObservedObject var playground: PlaygroundModel

    func body(content: Content) -> some View {
        content.sheet(isPresented: $volume.showSheet) {
            VolumeCheckSheet(monitor: volume) {
                playground.syncKeyboardSettings()
            }
            .presentationDetents([.fraction(0.58), .large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Tab 1: Desk-Lamp Studio (台灯工作台)

private struct StudioScreen: View {
    @ObservedObject var model: PlaygroundModel
    @ObservedObject var volume: VolumeMonitor
    @Environment(\.scenePhase) private var phase
    @State private var added = KeyboardStatus.isAdded()
    @State private var showEnableSheet = false
    @State private var blinkNonce = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StudioHeaderRow(
                        added: added,
                        volume: volume,
                        soundEnabled: model.keySound,
                        onOpenEnable: { showEnableSheet = true }
                    )

                    if volume.showHighBanner && model.keySound {
                        VolumeHighBanner(monitor: volume) {
                            model.keySound = false
                            volume.dismissHighBanner()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    DeskLampStageCard(model: model, volume: volume, externalBlinkNonce: blinkNonce)

                    SwitchTesterToy(volume: volume, mode: model.lampMode, soundEnabled: model.keySound) {
                        blinkNonce += 1
                    }

                    UnifiedTypingBench(model: model, volume: volume)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.never)

            if model.keyboardVisible {
                Rectangle().fill(MossOttoStyle.hairline).frame(height: 0.5)
                BenchKeyboardDock(model: model, volume: volume)
            }
        }
        .background(MossOttoStyle.canvas.ignoresSafeArea())
        .sheet(isPresented: $showEnableSheet) {
            NavigationStack {
                EnableScreen()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showEnableSheet = false }
                                .fontWeight(.semibold)
                        }
                    }
            }
        }
        .onChange(of: phase) { p in if p == .active { added = KeyboardStatus.isAdded() } }
        .animation(.easeOut(duration: 0.2), value: volume.showHighBanner)
    }
}

private struct StudioHeaderRow: View {
    let added: Bool
    @ObservedObject var volume: VolumeMonitor
    let soundEnabled: Bool
    var onOpenEnable: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Mosto键盘")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(MossOttoStyle.inkPrimary)
                Text("OTTOSSOM · 纯离线桌面工作台")
                    .font(.caption)
                    .foregroundStyle(MossOttoStyle.inkSecondary)
            }
            Spacer(minLength: 4)
            VolumeBadgePill(monitor: volume, soundEnabled: soundEnabled)
            Button(action: onOpenEnable) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(added ? MossOttoStyle.moss : MossOttoStyle.lampAmber)
                        .frame(width: 6.5, height: 6.5)
                    Text(added ? "已启用" : "去启用")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MossOttoStyle.inkPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5.5)
                .background(Capsule().fill(MossOttoStyle.surface))
                .overlay(Capsule().strokeBorder(MossOttoStyle.hairline, lineWidth: 0.8))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Unified OTTOSSOM desk-lamp showcase using pure transparent `Mosto` art (zero box-edge crop)
/// and a direct 3-mode lamp switcher (`日光` / `夜灯` / `简洁`) driving the workbench keyboard.
struct DeskLampStageCard: View {
    @ObservedObject var model: PlaygroundModel
    @ObservedObject var volume: VolumeMonitor
    var externalBlinkNonce: Int = 0

    @State private var blinking = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mode: StudioLampMode { model.lampMode }
    private var darkStage: Bool { mode == .night || (mode == .plain && scheme == .dark) }

    var body: some View {
        VStack(spacing: 12) {
            Button {
                triggerBlinkWithFeedback()
            } label: {
                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        Ellipse()
                            .fill(Color.black.opacity(darkStage ? 0.42 : 0.14))
                            .frame(width: 112, height: 18)
                            .blur(radius: 6)
                            .offset(y: 4)

                        Image(uiImage: mostoImage(spriteName))
                            .resizable()
                            .scaledToFit()
                            .frame(height: 118)
                            .scaleEffect(blinking && !reduceMotion ? 0.96 : 1.0)
                    }
                    .frame(height: 126)

                    Text(mode.caption)
                        .font(.caption)
                        .foregroundStyle(darkStage ? Color.white.opacity(0.78) : MossOttoStyle.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("轻点与台灯下的 Mosto 互动")

            HStack(spacing: 6) {
                ForEach(StudioLampMode.allCases) { m in
                    let active = m == mode
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeInOut(duration: 0.22)) { model.applyLampMode(m) }
                    } label: {
                        Text(m.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(active ? (darkStage ? Color.black : Color.white) : (darkStage ? Color.white.opacity(0.84) : MossOttoStyle.inkPrimary))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(
                                    active
                                        ? (darkStage ? Color(uiColor: MossOttoStyle.hex(0xFFC45A)) : MossOttoStyle.violet)
                                        : (darkStage ? Color.white.opacity(0.10) : MossOttoStyle.surface.opacity(0.82))
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(LampConeBackdrop(mode: mode))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(darkStage ? Color.white.opacity(0.12) : MossOttoStyle.hairline, lineWidth: 0.8)
        )
        .onChange(of: externalBlinkNonce) { _ in performVisualBlink() }
    }

    private var spriteName: String {
        if mode == .night { return blinking ? "MostoBlink" : "MostoNight" }
        return blinking ? "MostoBlink" : "Mosto"
    }

    private func performVisualBlink() {
        blinking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) { blinking = false }
    }

    private func triggerBlinkWithFeedback() {
        performVisualBlink()
        volume.gateSoundInteraction(soundEnabled: model.keySound) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.85)
            if model.keySound { volume.playSound(1156) }
        }
    }
}

/// The single unified workspace for free typing, interactive showcases (`手感体验`), and 3-sentence speed rhythm.
struct UnifiedTypingBench: View {
    @ObservedObject var model: PlaygroundModel
    @ObservedObject var volume: VolumeMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mode selector + genuine bench controls (zero misleading fake global switches)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(BenchMode.allCases) { m in
                        let selected = model.benchMode == m
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.easeInOut(duration: 0.18)) {
                                model.benchMode = m
                                if m == .demos && model.step >= lessons.count {
                                    model.jump(to: 0)
                                } else if m != .demos {
                                    model.step = lessons.count
                                }
                                if m == .speed {
                                    model.resetSpeedTest()
                                }
                            }
                        } label: {
                            Text(m.rawValue)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(selected ? Color.white : MossOttoStyle.inkPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7.5)
                                .background(
                                    Capsule().fill(selected ? MossOttoStyle.violet : MossOttoStyle.surfaceMuted)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // In-place live bench toggles (WrapLayout keeps all pills crisp & visible in snapshots too)
                WrapLayout(spacing: 6, lineSpacing: 6) {
                    schemePill(title: "全拼", tag: 0)
                    schemePill(title: "小鹤双拼", tag: 1)
                    schemePill(title: "九宫格", tag: 2)
                    if model.layout == 1 {
                        benchToggle(title: "键位提示", isOn: $model.guide)
                    }
                    benchToggle(title: "触感", isOn: $model.feedback)
                    benchToggle(title: "声效", isOn: $model.keySound)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(MossOttoStyle.surface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(MossOttoStyle.hairline, lineWidth: 0.7))

            // Mode-specific calm helper above the writing paper
            switch model.benchMode {
            case .free:
                WrapLayout(spacing: 6, lineSpacing: 6) {
                    inspirationChip("按错纠错：打 jintianhenrw")
                    inspirationChip("心算：打 365+18=")
                    inspirationChip("上滑，出。 / 轻点 Mosto")
                }
            case .demos:
                WrapLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(Array(lessons.enumerated()), id: \.offset) { idx, l in
                        let current = model.step == idx
                        let done = model.passedTitles.contains(l.title)
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            model.jump(to: idx)
                        } label: {
                            HStack(spacing: 5) {
                                if done {
                                    Circle().fill(MossOttoStyle.moss).frame(width: 6, height: 6)
                                }
                                Text(l.title)
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(current ? Color.white : MossOttoStyle.inkPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(current ? MossOttoStyle.violet : MossOttoStyle.surface))
                            .overlay(Capsule().strokeBorder(current ? Color.clear : MossOttoStyle.hairline, lineWidth: 0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                LessonCard(model: model, index: model.step)
            case .speed:
                SpeedArenaCard(model: model)
            }

            StudioTextPaper(model: model)

            if SnapshotRenderer.requested {
                // Static miniature R50 preview when ImageRenderer captures snapshots (since UIVC cannot draw in ImageRenderer).
                SnapshotKeyRowPreview(night: model.lampMode == .night, plain: model.lampMode == .plain)
            }
        }
    }

    private func schemePill(title: String, tag: Int) -> some View {
        let on = model.layout == tag
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            model.layout = tag
        } label: {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(on ? MossOttoStyle.violet : MossOttoStyle.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5.5)
                .background(Capsule().fill(on ? MossOttoStyle.violet.opacity(0.13) : MossOttoStyle.surfaceMuted))
                .overlay(Capsule().strokeBorder(on ? MossOttoStyle.violet.opacity(0.35) : .clear, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private func benchToggle(title: String, isOn: Binding<Bool>) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(isOn.wrappedValue ? MossOttoStyle.moss : MossOttoStyle.inkSecondary.opacity(0.35))
                    .frame(width: 5.5, height: 5.5)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isOn.wrappedValue ? MossOttoStyle.inkPrimary : MossOttoStyle.inkSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5.5)
            .background(Capsule().fill(MossOttoStyle.surfaceMuted))
        }
        .buttonStyle(.plain)
    }

    private func inspirationChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(MossOttoStyle.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5.5)
            .background(Capsule().fill(MossOttoStyle.surface))
            .overlay(Capsule().strokeBorder(MossOttoStyle.hairline, lineWidth: 0.7))
    }
}

private struct SpeedArenaCard: View {
    @ObservedObject var model: PlaygroundModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("进度 \(min(model.speedIndex + (model.speedFinishedSeconds != nil ? 1 : 0), PlaygroundModel.speedTargets.count))/\(PlaygroundModel.speedTargets.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MossOttoStyle.inkSecondary)
                Spacer()
                Text(model.currentCPM > 0 ? "\(model.currentCPM) 字/分" : "准备开始")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(MossOttoStyle.violet)
                Text("· 最佳 \(model.bestCPM > 0 ? "\(model.bestCPM)" : "--")")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(MossOttoStyle.inkSecondary)
                Button("重测") { model.resetSpeedTest() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MossOttoStyle.violet)
            }

            if let sec = model.speedFinishedSeconds {
                HStack(spacing: 12) {
                    Image(uiImage: mostoImage("Mosto"))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("三句完成 · 均速 \(model.currentCPM) 字/分")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(MossOttoStyle.inkPrimary)
                        Text(String(format: "共 %d 字 · 用时 %.1f 秒", model.speedTotalChars, sec))
                            .font(.caption)
                            .foregroundStyle(MossOttoStyle.inkSecondary)
                    }
                    Spacer()
                    Button("再来一轮") { model.resetSpeedTest() }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(MossOttoStyle.violet))
                        .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 2) {
                    ForEach(Array(model.currentSpeedTarget.enumerated()), id: \.offset) { i, ch in
                        Text(String(ch))
                            .font(.system(size: 21, weight: .semibold, design: .rounded))
                            .foregroundStyle(i < model.matchedSpeedPrefixCount ? MossOttoStyle.violet : MossOttoStyle.inkPrimary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MossOttoStyle.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(MossOttoStyle.hairline, lineWidth: 0.7))
    }
}

private struct SnapshotKeyRowPreview: View {
    let night: Bool
    let plain: Bool
    private let keys = ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(keys, id: \.self) { k in
                    MonolithKeycapView(label: k, plain: plain, forceNight: night, cornerRadius: 8)
                        .frame(height: 40)
                }
            }
            HStack(spacing: 6) {
                MonolithKeycapView(label: "中", plain: plain, forceNight: night, ledColor: MossOttoStyle.moss, cornerRadius: 8)
                    .frame(width: 54, height: 38)
                MonolithKeycapView(label: "空格", plain: plain, forceNight: night, homingNotch: !plain, cornerRadius: 8)
                    .frame(height: 38)
                MonolithKeycapView(label: "确认", plain: plain, forceNight: night, ledColor: MossOttoStyle.lampAmber, cornerRadius: 8)
                    .frame(width: 68, height: 38)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MossOttoStyle.surfaceMuted)
        )
    }
}

/// Real embedded R50 keyboard dock with one-time Volume Check gate before first audible interaction.
private struct BenchKeyboardDock: View {
    @ObservedObject var model: PlaygroundModel
    @ObservedObject var volume: VolumeMonitor

    var body: some View {
        ZStack {
            if SnapshotRenderer.requested {
                Color.clear
            } else {
                KeyboardHostView(model: model)
            }
            if !volume.hasConfirmedOnce && model.keySound {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        volume.gateSoundInteraction(soundEnabled: model.keySound) {}
                    }
                    .accessibilityLabel("轻点先确认手机音量后开始试用桌面键盘")
            }
        }
        .frame(height: 264)
        .background(
            Color(UIColor {
                $0.userInterfaceStyle == .dark
                    ? UIColor(white: 0.10, alpha: 1)
                    : MossOttoStyle.hex(0xE8E2D7)
            })
        )
    }
}

// MARK: - Tab 2: Handbook & About (手册与关于)

private struct HandbookScreen: View {
    @ObservedObject var nav: AppNavigation
    @Environment(\.scenePhase) private var phase
    @State private var added = KeyboardStatus.isAdded()

    var body: some View {
        ScrollView {
            HandbookContent(added: added, nav: nav)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
        .background(MossOttoStyle.canvas.ignoresSafeArea())
        .onChange(of: phase) { p in if p == .active { added = KeyboardStatus.isAdded() } }
    }
}

/// Clean single-source reference manual & compliance section (shared with CI snapshot `app_home3.png`).
struct HandbookContent: View {
    let added: Bool
    var nav: AppNavigation? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Card(title: "系统键盘与真机启用") {
                cardLink {
                    EnableScreen()
                } label: {
                    handbookRow(
                        icon: added ? "checkmark.seal.fill" : "keyboard.badge.ellipsis",
                        iconColor: added ? MossOttoStyle.moss : MossOttoStyle.lampAmber,
                        title: added ? "Mosto键盘已启用" : "三步在系统设置里启用 Mosto键盘",
                        subtitle: "包含一键前往系统设置与真机切换验证框"
                    )
                }

                Divider()

                Usage(
                    icon: "slider.horizontal.3",
                    title: "系统键盘偏好在哪里调整",
                    text: "出于离线隐私隔离，伴侣 App 不写入系统键盘配置文件；实际输入时的双拼、九宫格、外观与声效，请直接在键盘内按住表情键打开「Mosto 控制台」调整。"
                )
            }

            Card(title: "双拼与手势图鉴") {
                cardLink {
                    XiaoheGuideView(volume: nav?.volume)
                } label: {
                    handbookRow(
                        icon: "square.grid.3x3",
                        iconColor: MossOttoStyle.violet,
                        title: "小鹤双拼图谱与声感指法",
                        subtitle: "声母韵母分布、零声母打法、交互指法练习与版权声明"
                    )
                }

                Divider()

                cardLink {
                    GestureAtlasView(nav: nav)
                } label: {
                    handbookRow(
                        icon: "hand.draw",
                        iconColor: MossOttoStyle.ottoIndigo,
                        title: "高效手势与隐藏能力一页图鉴",
                        subtitle: "标点上滑副符号、空格滑移光标、删键左划清空、心算与日期"
                    )
                }
            }

            Card(title: "离线隐私与开源合规") {
                cardLink {
                    PrivacyArchitectureView()
                } label: {
                    handbookRow(
                        icon: "lock.shield",
                        iconColor: MossOttoStyle.moss,
                        title: "纯离线架构与 14 条工程红线",
                        subtitle: "0 联网 · 0 剪贴板 · 0 跨进程共享 · 45 MB 只读词库"
                    )
                }

                ForEach(LegalText.docs, id: \.id) { doc in
                    Divider()
                    cardLink {
                        LegalView(doc: doc)
                    } label: {
                        handbookRow(
                            icon: aboutIcon(doc.id),
                            iconColor: MossOttoStyle.inkSecondary,
                            title: doc.title,
                            subtitle: "离线完整文本"
                        )
                    }
                }
            }

            StudioVersionFooter()
        }
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

    private func handbookRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
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
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(MossOttoStyle.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        VStack(spacing: 4) {
            Text(versionLine)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MossOttoStyle.inkSecondary)
            Text("OTTOSSOM Studio · 纯本地中文输入法")
                .font(.caption2)
                .foregroundStyle(MossOttoStyle.inkSecondary.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

// MARK: - Gesture & Feature Atlas

private struct GestureAtlasView: View {
    var nav: AppNavigation? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Card(title: "高频核心手势") {
                    atlasRow(
                        cap: "，↑。",
                        title: "任意标点轻上滑直出副符号",
                        detail: "从 ，轻向上滑立刻输出 。；数符页 /→、 、¥→$、（→【 等均支持无延迟直出，无需长按等待。",
                        demoTitle: nil
                    )
                    Divider()
                    atlasRow(
                        cap: "← ␣ →",
                        title: "空格横向拖移光标",
                        detail: "在空格键上左右滑动即可细腻移动输入光标，按键字面自动隐去减少干扰，按距离触发分段震动。",
                        demoTitle: nil
                    )
                    Divider()
                    atlasRow(
                        cap: "←⌫ ↩",
                        title: "删键左划一次清空 + ↩ 找回",
                        detail: "输入拼音时从删除键向左一划直接清空整串拼音，候选栏左侧立刻留下 ↩，轻点可完整恢复。",
                        demoTitle: nil
                    )
                    Divider()
                    atlasRow(
                        cap: "☺︎ ⚙",
                        title: "按住表情键直达系统键盘设置",
                        detail: "轻点进入 Emoji / 200+ 颜文字分类；按住 0.45 秒打开键盘面板，切换全拼/小鹤/九宫格、外观与音震。",
                        demoTitle: nil
                    )
                }

                Card(title: "纠错、心算与日期") {
                    atlasRow(
                        cap: "eh↔w",
                        title: "整句触点纠错与长句容错",
                        detail: "按偏邻键（如 jintianhenrw）、漏键（jintiantiaqi）、相邻倒序都能整句读准；点首选左 ↩ 可一键恢复原键。",
                        demoTitle: "按错了什么，改成了什么"
                    )
                    Divider()
                    atlasRow(
                        cap: "365+=",
                        title: "四则心算与相对日期直出",
                        detail: "直接敲 286/4= 或带括号算式在候选栏直出结果；打 明天 / 下周一 / 今年 / 本月 自动联想对应日期。",
                        demoTitle: "中英混输"
                    )
                    Divider()
                    atlasRow(
                        cap: "mstd",
                        title: "首字母缩写与自造词记忆",
                        detail: "常见短语只敲声母（bzd → 不知道），选过一次的新词次次记住；在展开网格中长按任意学习词可删去。",
                        demoTitle: "记住你的词"
                    )
                }

                Card(title: "候选栏左侧 Mosto") {
                    Usage(
                        icon: "sparkles",
                        title: "一点颜文字 · 两点切换日光/夜灯",
                        text: "轻点一次打开 Mosto 收藏的表情与颜文字；连续轻点两下在日光与夜灯间切换，长按可复制诊断信息。"
                    )
                }
            }
            .padding(16)
        }
        .background(MossOttoStyle.canvas.ignoresSafeArea())
        .navigationTitle("手势与效率图鉴")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func atlasRow(cap: String, title: String, detail: String, demoTitle: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MonolithKeycapView(label: cap, cornerRadius: 9)
                .frame(width: 58, height: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MossOttoStyle.inkPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(MossOttoStyle.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let demoTitle, let nav {
                    Button("去台灯工作台试试") {
                        nav.tryDemo(demoTitle)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MossOttoStyle.violet)
                    .padding(.top, 2)
                }
            }
        }
    }
}

// MARK: - Privacy & Legal Views

private struct PrivacyArchitectureView: View {
    var body: some View {
        List {
            Section("零联网与零共享隔离") {
                row("0 次网络请求", "键盘扩展与伴侣 App 不包含 URLSession、WebView 埋点或任何第三方统计 SDK。")
                row("0 次剪贴板读取", "不访问 UIPasteboard，保持系统默认权限即可使用完整中文输入、双拼与心算。")
                row("0 App Group 容器", "伴侣 App 与系统键盘扩展各自隔离，不跨进程同步按键或词库数据。")
            }
            Section("iOS 键盘扩展工程红线") {
                row("45 MB Jetsam 只读映射", "词库与语言模型以只读 mmap 加载，零脏内存常驻，保留热缓存的同时严控内存上限。")
                row("全链路 0 阻塞 XPC 守则", "扩展内零行内 setMarkedText XPC、空格 0-XPC，首键复用异步预取上下文，候选条宽度跨词保留缓存。")
                row("14 条 CI 自动化铁律门禁", "每次构建静态与真机校验网络 API、同步等待解码、离屏阴影光栅化、空 setMarkedText 与首键热路径 XPC。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("隐私与工程红线")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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
