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
        switch title {
        case "四则心算与相对日期":
            playground.playInspiration(.math)
            tab = .studio
            return
        case "标点上滑副符号":
            playground.playInspiration(.flickAndMosto)
            tab = .studio
            return
        default:
            break
        }
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
                        onSelectProfile: { model.hapticProfile = $0 },
                        onToggleSound: {
                            if model.keySound {
                                model.keySound = false
                            } else {
                                volume.gateSoundInteraction(soundEnabled: true) {
                                    model.keySound = true
                                }
                            }
                        }
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

                // Balanced 2-row hardware strip (Row 1: engine + guide/numberPad, Row 2: core engine toggles + feel + 4-tier height)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        schemePill(title: "全拼", tag: 0)
                        schemePill(title: "小鹤双拼", tag: 1)
                        schemePill(title: "九宫格", tag: 2)
                        if model.layout == 1 {
                            benchToggle(title: "键位提示", isOn: $model.guide)
                        } else if model.layout == 2 {
                            benchToggle(title: "数字", isOn: $model.numberPad)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 5) {
                        benchToggle(title: "纠错", isOn: $model.autocorrect)
                        benchToggle(title: "中英", isOn: $model.english)
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
                                    HStack(spacing: 2) {
                                        RoundedRectangle(cornerRadius: 0.9, style: .continuous)
                                            .fill(active ? Color.white : Color(uiColor: lit ? Theme.statusLedActive : Theme.statusLedMuted))
                                            .frame(width: 2.2, height: CGFloat(5 + tier.rawValue * 2))
                                        Text(tier.shortMark)
                                            .font(.system(size: 10.5, weight: active ? .bold : .semibold, design: .rounded))
                                            .foregroundStyle(active ? Color.white : MossOttoStyle.inkPrimary)
                                    }
                                    .padding(.horizontal, 5.5)
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
                // Single-row symmetrical 7-node Hardware Step Rail (zero 5+2 uneven wrapping)
                HStack(spacing: 3) {
                    ForEach(Array(lessons.enumerated()), id: \.offset) { idx, l in
                        let current = model.step == idx
                        let done = model.passedTitles.contains(l.title)
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            model.jump(to: idx)
                        } label: {
                            HStack(spacing: 2.5) {
                                if done {
                                    Circle()
                                        .fill(current ? MossOttoStyle.lampAmber : MossOttoStyle.moss)
                                        .frame(width: 4.5, height: 4.5)
                                }
                                Text(l.compactTag)
                                    .font(.system(size: 11, weight: current ? .bold : .semibold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(current ? Color.white : MossOttoStyle.inkPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(current ? MossOttoStyle.violet : Color.clear))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(l.title)
                        .accessibilityValue(done ? "已完成" : (current ? "当前" : ""))
                    }
                }
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MossOttoStyle.surface))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(MossOttoStyle.hairline, lineWidth: 0.7))
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
            HStack(spacing: 3.5) {
                Circle()
                    .fill(isOn.wrappedValue ? MossOttoStyle.moss : MossOttoStyle.inkSecondary.opacity(0.35))
                    .frame(width: 5, height: 5)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(isOn.wrappedValue ? MossOttoStyle.inkPrimary : MossOttoStyle.inkSecondary)
            }
            .padding(.horizontal, 8)
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
        let total = PlaygroundModel.speedTargets.count
        let doneCount = model.speedFinishedSeconds != nil ? total : model.speedIndex
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // 3-segment visual progress bead rail
                HStack(spacing: 4) {
                    ForEach(0..<total, id: \.self) { seg in
                        let isDone = seg < doneCount
                        let isActive = seg == model.speedIndex && model.speedFinishedSeconds == nil
                        let frac: CGFloat = isDone ? 1 : (isActive ? CGFloat(model.matchedSpeedPrefixCount) / CGFloat(max(1, model.currentSpeedTarget.count)) : 0)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(MossOttoStyle.surfaceMuted)
                                Capsule()
                                    .fill(isDone ? MossOttoStyle.moss : MossOttoStyle.violet)
                                    .frame(width: max(isActive && frac == 0 ? 4 : 0, g.size.width * min(1, frac)))
                            }
                        }
                        .frame(width: 24, height: 5.5)
                    }
                }

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(MossOttoStyle.violet)
                    Text(model.currentCPM > 0 ? "\(model.currentCPM) 字/分" : "就绪")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(MossOttoStyle.violet)
                    if model.bestCPM > 0 {
                        Text("· 佳 \(model.bestCPM)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(MossOttoStyle.inkSecondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Capsule().fill(MossOttoStyle.surfaceMuted))

                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    model.resetSpeedTest()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MossOttoStyle.violet)
                        .padding(6)
                        .background(Circle().fill(MossOttoStyle.violet.opacity(0.11)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("重测")
            }

            if let sec = model.speedFinishedSeconds {
                HStack(spacing: 12) {
                    Image(uiImage: mostoImage("Mosto"))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("均速 \(model.currentCPM) 字/分")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(MossOttoStyle.inkPrimary)
                        Text(String(format: "%d 句 · %d 字 · %.1f 秒", total, model.speedTotalChars, sec))
                            .font(.caption.monospacedDigit())
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
                HStack(spacing: 3) {
                    ForEach(Array(model.currentSpeedTarget.enumerated()), id: \.offset) { i, ch in
                        let matched = i < model.matchedSpeedPrefixCount
                        let nextChar = i == model.matchedSpeedPrefixCount
                        VStack(spacing: 2) {
                            Text(String(ch))
                                .font(.system(size: 20.5, weight: nextChar ? .bold : .semibold, design: .rounded))
                                .foregroundStyle(matched ? MossOttoStyle.violet : MossOttoStyle.inkPrimary)
                                .padding(.horizontal, nextChar ? 3 : 0.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(nextChar ? MossOttoStyle.violet.opacity(0.12) : Color.clear)
                                )
                            Capsule()
                                .fill(nextChar ? MossOttoStyle.violet : Color.clear)
                                .frame(width: 12, height: 2)
                        }
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
                        elevationMetaChip()
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
                        title: "纯离线架构与 16 条红线",
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

    private func elevationMetaChip() -> some View {
        HStack(spacing: 5) {
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<4, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 0.75, style: .continuous)
                        .fill(MossOttoStyle.moss.opacity(0.45 + Double(step) * 0.18))
                        .frame(width: 2.2, height: CGFloat(4.5 + Double(step) * 2.0))
                }
            }
            Text("四档高度实时调")
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
            GestureAtlasContent(nav: nav)
                .padding(16)
        }
        .background(MossOttoStyle.canvas.ignoresSafeArea())
        .navigationTitle("手势与效率图鉴")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GestureAtlasContent: View {
    var nav: AppNavigation? = nil

    enum MostoPreviewAction: String {
        case tap = "轻点"
        case doubleTap = "双击"
        case longPress = "长按"

        var sprite: String {
            switch self {
            case .tap: return "MostoBlink"
            case .doubleTap: return "MostoNight"
            case .longPress: return "MostoToyBlink"
            }
        }

        var badge: String {
            switch self {
            case .tap: return "(=^･ω･^=)  颜文字弹出"
            case .doubleTap: return "切换台灯暖光 / 暗夜模式"
            case .longPress: return "慵懒打哈欠 · 软触反馈"
            }
        }
    }

    @State private var selectedMosto: MostoPreviewAction? = nil
    @State private var mostoBounce = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "高频核心手势") {
                atlasRow(
                    cap: "，↑。",
                    title: "标点上滑副符号",
                    chips: ["，↑。", "/↑、", "¥↑$", "（↑【"],
                    demoTitle: "标点上滑副符号"
                )
                Divider()
                atlasRow(
                    cap: "123↗",
                    title: "滑键借层与双手和弦",
                    chips: ["按住滑键直出", "松手自动回弹"],
                    demoTitle: nil
                )
                Divider()
                atlasRow(
                    symbol: "arrow.left.and.right",
                    title: "空格横向拖移光标",
                    chips: ["左右滑动游标", "首尾琥珀止点"],
                    demoTitle: nil
                )
                Divider()
                atlasRow(
                    symbol: "delete.left",
                    title: "左划清空与逐词快删",
                    chips: ["左划一键清空", "长按 >1s 删词"],
                    demoTitle: "左划清空与逐词快删"
                )
                Divider()
                atlasRow(
                    symbol: "slider.horizontal.3",
                    title: "长按表情键开控制台",
                    chips: ["轻点选表情", "按住 0.45s 控制台"],
                    demoTitle: nil
                )
            }

            Card(title: "纠错、心算与日期") {
                atlasRow(
                    symbol: "wand.and.stars",
                    title: "整句触点纠错",
                    chips: ["偏键自动读准", "一键撤回还原"],
                    demoTitle: "按错了什么，改成了什么"
                )
                Divider()
                atlasRow(
                    symbol: "plus.forwardslash.minus",
                    title: "四则心算与相对日期",
                    chips: ["286/4= 空格连算", "下周一 联想日期"],
                    demoTitle: "四则心算与相对日期"
                )
                Divider()
                atlasRow(
                    cap: "bzd",
                    title: "首字母简拼与自造词",
                    chips: ["bzd → 不知道", "长按网格词忘词"],
                    demoTitle: "记住你的词"
                )
            }

            Card(title: "候选栏左侧 Mosto") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(uiImage: mostoImage(selectedMosto?.sprite ?? "Mosto"))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .scaleEffect(mostoBounce ? 1.12 : 1.0)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("指尖声光彩蛋")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MossOttoStyle.inkPrimary)
                            Text(selectedMosto?.badge ?? "点按下方手势按钮试玩反馈")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(selectedMosto == nil ? MossOttoStyle.inkSecondary : MossOttoStyle.violet)
                        }
                        Spacer(minLength: 4)
                        Text("200+ 颜文字")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(MossOttoStyle.violet)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Capsule().fill(MossOttoStyle.violet.opacity(0.12)))
                    }
                    HStack(spacing: 6) {
                        mostoActionTile(action: .tap, effect: "颜文字")
                        mostoActionTile(action: .doubleTap, effect: "切换光效")
                        mostoActionTile(action: .longPress, effect: "打哈欠")
                    }
                }
            }
        }
    }

    private func mostoActionTile(action: MostoPreviewAction, effect: String) -> some View {
        let active = selectedMosto == action
        return Button {
            let style: UIImpactFeedbackGenerator.FeedbackStyle = action == .longPress ? .soft : (action == .doubleTap ? .medium : .light)
            UIImpactFeedbackGenerator(style: style).impactOccurred()
            withAnimation(.spring(response: 0.24, dampingFraction: 0.65)) {
                selectedMosto = action
                mostoBounce = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.easeOut(duration: 0.14)) {
                    mostoBounce = false
                }
            }
        } label: {
            VStack(spacing: 2) {
                Text(action.rawValue)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(active ? Color.white : MossOttoStyle.violet)
                Text(effect)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(active ? Color.white : MossOttoStyle.inkPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(active ? MossOttoStyle.violet : MossOttoStyle.surfaceMuted))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func atlasRow(cap: String = "", symbol: String? = nil, title: String, chips: [String], demoTitle: String?) -> some View {
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
        ScrollView {
            PrivacyArchitectureContent()
                .padding(16)
        }
        .background(MossOttoStyle.canvas.ignoresSafeArea())
        .navigationTitle("隐私与工程红线")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyArchitectureContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "零联网与零共享仪表盘") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    telemetryTile(value: "0", label: "网络请求", icon: "wifi.slash", tint: MossOttoStyle.moss)
                    telemetryTile(value: "0", label: "剪贴板读取", icon: "doc.on.clipboard", tint: MossOttoStyle.moss)
                    telemetryTile(value: "0", label: "跨进程共享", icon: "lock.shield.fill", tint: MossOttoStyle.violet)
                    telemetryTile(value: "45 MB", label: "只读词库", icon: "memorychip", tint: MossOttoStyle.lampAmber)
                }
            }

            Card(title: "键盘扩展工程红线") {
                specRow(
                    icon: "cpu",
                    tint: MossOttoStyle.violet,
                    title: "只读 mmap 零脏页",
                    detail: "词库与语言模型按需映射，严守 Jetsam 上限"
                )
                Divider()
                specRow(
                    icon: "bolt.horizontal.fill",
                    tint: MossOttoStyle.lampAmber,
                    title: "全链路 0 阻塞 XPC",
                    detail: "零行内 markedText · 空格零等待 · 首键异步预取"
                )
                Divider()
                specRow(
                    icon: "checkmark.seal.fill",
                    tint: MossOttoStyle.moss,
                    title: "16 条 CI 自动化门禁",
                    detail: "每次构建静态与真机校验离线、帧率与四边防模糊"
                )
            }
        }
    }

    private func telemetryTile(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(MossOttoStyle.inkPrimary)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MossOttoStyle.inkSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MossOttoStyle.surfaceMuted))
        .accessibilityElement(children: .combine)
    }

    private func specRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MossOttoStyle.inkPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(MossOttoStyle.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
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
