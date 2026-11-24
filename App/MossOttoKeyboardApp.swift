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

                    SwitchTesterToy(
                        volume: volume,
                        mode: model.lampMode,
                        soundEnabled: model.keySound,
                        hapticProfile: model.hapticProfile,
                        onSelectProfile: { model.hapticProfile = $0 }
                    ) {
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
    @State private var pullFraction: CGFloat = 0
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
        .background(LampConeBackdrop(mode: mode, dimFactor: pullFraction))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(darkStage ? Color.white.opacity(0.12) : MossOttoStyle.hairline, lineWidth: 0.8)
        )
        .overlay(alignment: .topTrailing) {
            LampPullCordSwitch(mode: mode, darkStage: darkStage, pullFraction: $pullFraction) {
                triggerPullCordCycle()
            }
            .padding(.trailing, 10)
        }
        .onChange(of: externalBlinkNonce) { _ in performVisualBlink() }
    }

    private func triggerPullCordCycle() {
        performVisualBlink()
        let nextMode = mode.next
        withAnimation(.easeInOut(duration: 0.24)) { model.applyLampMode(nextMode) }
        volume.gateSoundInteraction(soundEnabled: model.keySound) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.85)
            if model.keySound { volume.playSound(1156) }
        }
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

                // Balanced 2-row hardware strip (Row 1: engine + guide, Row 2: feel + 4-tier height)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        schemePill(title: "全拼", tag: 0)
                        schemePill(title: "小鹤双拼", tag: 1)
                        schemePill(title: "九宫格", tag: 2)
                        if model.layout == 1 {
                            benchToggle(title: "键位提示", isOn: $model.guide)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 6) {
                        benchToggle(title: "触感", isOn: $model.feedback)
                        benchToggle(title: "声效", isOn: $model.keySound)
                        Spacer(minLength: 4)
                        HStack(spacing: 2) {
                            ForEach(KeyboardHeightPreset.allCases, id: \.rawValue) { tier in
                                let active = model.heightPreset == tier
                                let lit = tier.rawValue <= model.heightPreset.rawValue
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                        model.keyboardHeight = tier.rawValue
                                    }
                                } label: {
                                    HStack(spacing: 2.5) {
                                        RoundedRectangle(cornerRadius: 0.9, style: .continuous)
                                            .fill(active ? Color.white : Color(uiColor: lit ? Theme.statusLedActive : Theme.statusLedMuted))
                                            .frame(width: 2.5, height: CGFloat(5 + tier.rawValue * 2))
                                        Text(tier.shortMark)
                                            .font(.system(size: 11, weight: active ? .bold : .semibold, design: .rounded))
                                            .foregroundStyle(active ? Color.white : MossOttoStyle.inkPrimary)
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4.5)
                                    .background(Capsule().fill(active ? MossOttoStyle.violet : Color.clear))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("键盘高度：\(tier.title)")
                                .accessibilityValue(active ? "已选" : "")
                            }
                        }
                        .padding(2.5)
                        .background(Capsule().fill(MossOttoStyle.surfaceMuted))
                        .overlay(Capsule().strokeBorder(MossOttoStyle.hairline, lineWidth: 0.6))
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(MossOttoStyle.surface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(MossOttoStyle.hairline, lineWidth: 0.7))

            // Mode-specific calm helper above the writing paper
            switch model.benchMode {
            case .free:
                WrapLayout(spacing: 6, lineSpacing: 6) {
                    inspirationChip(model.layout == 1 ? "纠错演示：jbtmtmqohfhc" : "纠错演示：jintianhenrw") {
                        model.playInspiration(.correction)
                    }
                    inspirationChip("心算演示：365+18=") {
                        model.playInspiration(.math)
                    }
                    inspirationChip("试打：你好。 / 轻点 Mosto") {
                        model.playInspiration(.flickAndMosto)
                    }
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
                                Text(l.shortTitle)
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(current ? Color.white : MossOttoStyle.inkPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(current ? MossOttoStyle.violet : MossOttoStyle.surface))
                            .overlay(Capsule().strokeBorder(current ? Color.clear : MossOttoStyle.hairline, lineWidth: 0.7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(l.title)
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

    private func inspirationChip(_ text: String, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(MossOttoStyle.violet)
                Text(text)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MossOttoStyle.inkPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5.5)
            .background(Capsule().fill(MossOttoStyle.surface))
            .overlay(Capsule().strokeBorder(MossOttoStyle.hairline, lineWidth: 0.7))
        }
        .buttonStyle(.plain)
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
        .frame(height: model.preferredKeyboardHeight)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: model.preferredKeyboardHeight)
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
                        title: added ? "Mosto键盘已启用" : "三步启用 Mosto键盘",
                        subtitle: "系统设置引导 · 真机输入框验证"
                    )
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("系统键盘偏好在键盘内调校")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MossOttoStyle.inkPrimary)
                    HStack(spacing: 6) {
                        flowPill(icon: "face.smiling", text: "按住表情键")
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(MossOttoStyle.inkSecondary)
                        flowPill(icon: "slider.horizontal.3", text: "Mosto 控制台", highlight: true)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 6) {
                        metaChip(icon: "lock.fill", text: "进程隔离 · 不写共享容器")
                        metaChip(icon: "rectangle.expand.vertical", text: "四档高度即时生效")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("系统键盘偏好在键盘内按住表情键打开 Mosto 控制台调整，伴侣 App 与键盘扩展进程隔离、完全离线。")
            }

            Card(title: "双拼与手势图鉴") {
                cardLink {
                    XiaoheGuideView(volume: nav?.volume)
                } label: {
                    handbookRow(
                        icon: "square.grid.3x3",
                        iconColor: MossOttoStyle.violet,
                        title: "小鹤双拼图谱与指法",
                        subtitle: "声感琴盘跟练 · 零声母速查"
                    )
                }

                Divider()

                cardLink {
                    GestureAtlasView(nav: nav)
                } label: {
                    handbookRow(
                        icon: "hand.draw",
                        iconColor: MossOttoStyle.ottoIndigo,
                        title: "高效手势与隐藏能力",
                        subtitle: "上滑标点 · 滑键借层 · 心算连算"
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
                        title: "纯离线架构与 15 条红线",
                        subtitle: "0 联网 · 0 剪贴板 · 0 App Group · 45 MB"
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
                            subtitle: nil
                        )
                    }
                }
            }

            StudioVersionFooter()
        }
    }

    private func flowPill(icon: String, text: String, highlight: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(highlight ? MossOttoStyle.violet : MossOttoStyle.inkPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(highlight ? MossOttoStyle.violet.opacity(0.13) : MossOttoStyle.surfaceMuted))
        .overlay(Capsule().strokeBorder(highlight ? MossOttoStyle.violet.opacity(0.32) : .clear, lineWidth: 0.7))
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(MossOttoStyle.moss)
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(MossOttoStyle.inkSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(MossOttoStyle.surfaceMuted))
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

    private func handbookRow(icon: String, iconColor: Color, title: String, subtitle: String?) -> some View {
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
            VStack(alignment: .leading, spacing: 18) {
                Card(title: "高频核心手势") {
                    atlasRow(
                        cap: "，↑。",
                        title: "标点上滑副符号",
                        formula: "，↑ 。  ·  / ↑ 、  ·  ¥ ↑ $  ·  （ ↑ 【",
                        demoTitle: nil
                    )
                    Divider()
                    atlasRow(
                        cap: "123↗",
                        title: "滑键借层与双手和弦",
                        formula: "按住 123 / Shift 滑向目标键直出回弹 · 双指连打",
                        demoTitle: nil
                    )
                    Divider()
                    atlasRow(
                        cap: "←␣→",
                        title: "空格横向拖移光标",
                        formula: "左右滑移光标 · 跨行 / 首尾亮起琥珀止点",
                        demoTitle: nil
                    )
                    Divider()
                    atlasRow(
                        cap: "←⌫↩",
                        title: "左划清空 + 长按删词离合",
                        formula: "左划整词清空留 ↩ · 长按 >1s 逐词快删",
                        demoTitle: nil
                    )
                    Divider()
                    atlasRow(
                        cap: "☺︎⚙",
                        title: "长按表情键开控制台",
                        formula: "轻点选表情 · 长按 0.45s 调高度 / 方案 / 光效",
                        demoTitle: nil
                    )
                }

                Card(title: "纠错、心算与日期") {
                    atlasRow(
                        cap: "eh↔w",
                        title: "整句触点纠错",
                        formula: "偏键 jintianhenrw / 漏键自动整句读准 · ↩ 还原",
                        demoTitle: "按错了什么，改成了什么"
                    )
                    Divider()
                    atlasRow(
                        cap: "365+=",
                        title: "四则心算与相对日期",
                        formula: "286/4= 空格上屏连算 · 明天 / 下周一 联想日期",
                        demoTitle: "中英混输"
                    )
                    Divider()
                    atlasRow(
                        cap: "bzd",
                        title: "首字母简拼与自造词",
                        formula: "bzd → 不知道 · 展开网格长按词条可忘词",
                        demoTitle: "记住你的词"
                    )
                }

                Card(title: "候选栏左侧 Mosto") {
                    HStack(spacing: 12) {
                        Image(uiImage: mostoImage("Mosto"))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("轻点颜文字 · 双击切光效")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MossOttoStyle.inkPrimary)
                            Text("200+ 颜文字分类 · 日光 / 夜灯随手切换 · 长按打哈欠")
                                .font(.caption)
                                .foregroundStyle(MossOttoStyle.inkSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(16)
        }
        .background(MossOttoStyle.canvas.ignoresSafeArea())
        .navigationTitle("手势与效率图鉴")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func atlasRow(cap: String, title: String, formula: String, demoTitle: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            MonolithKeycapView(label: cap, cornerRadius: 9)
                .frame(width: 58, height: 40)
            VStack(alignment: .leading, spacing: 2.5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MossOttoStyle.inkPrimary)
                Text(formula)
                    .font(.caption)
                    .foregroundStyle(MossOttoStyle.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let demoTitle, let nav {
                Button("试试") {
                    nav.tryDemo(demoTitle)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(MossOttoStyle.violet)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(MossOttoStyle.violet.opacity(0.12)))
                .buttonStyle(.plain)
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
                row("15 条 CI 自动化铁律门禁", "每次构建静态与真机校验网络 API、同步等待解码、离屏阴影光栅化、空 setMarkedText、首键热路径 XPC 与 iOS 26 四边滚动防模糊。")
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
