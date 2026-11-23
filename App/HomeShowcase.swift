import SwiftUI
import UIKit
import AVFoundation
import AudioToolbox

/// Full-resolution Mosto sprites from the app asset catalog.
func mostoImage(_ name: String) -> UIImage { UIImage(named: name) ?? UIImage() }

/// Desk-lamp lighting mode shared across the Companion App stage and the embedded R50 keyboard.
enum StudioLampMode: Int, CaseIterable, Identifiable {
    case day = 0
    case night = 1
    case plain = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .day: return "日光"
        case .night: return "夜灯"
        case .plain: return "简洁"
        }
    }

    var caption: String {
        switch self {
        case .day: return "暖瓷桌台 · R50 哑光零重影"
        case .night: return "深曜石夜桌 · 暖灯珠微光"
        case .plain: return "中性陶瓷 · 系统比例"
        }
    }

    static func from(appearance: Int, style: Int) -> StudioLampMode {
        if style == 1 { return .plain }
        return appearance == 2 ? .night : .day
    }
}

/// OTTOSSOM (摸索台灯) studio design tokens aligned with `Tools/ip/ip3d.py` and R50 keycap materials.
enum MossOttoStyle {
    static func dynamic(_ day: UIColor, _ night: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? night : day })
    }

    static func hex(_ v: UInt32, _ a: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: a
        )
    }

    /// Warm ceramic desk paper in Day; deep desk-lamp obsidian in Night.
    static let canvas = dynamic(hex(0xF7F4EE), hex(0x14121D))
    /// Elevated matte vinyl card surface.
    static let surface = dynamic(hex(0xFFFFFF), hex(0x1F1B2E))
    /// Recessed tray / instrument socket surface.
    static let surfaceMuted = dynamic(hex(0xEFEAE0), hex(0x28233B))
    /// Delicate physical 0.5pt contour line.
    static let hairline = dynamic(hex(0xE4DDD0), UIColor.white.withAlphaComponent(0.11))

    /// Shared IP studio family accents: Mosto violet, lamp-bead amber, Moss sprout green, Otto indigo.
    static let violet = dynamic(hex(0x633EBF), hex(0xA78BFA))
    static let lampAmber = dynamic(hex(0xD69A34), hex(0xFFC45A))
    static let moss = dynamic(hex(0x55704A), hex(0x7EA86E))
    static let ottoIndigo = dynamic(hex(0x203872), hex(0x7FA6E8))

    static let inkPrimary = dynamic(hex(0x1E192B), hex(0xF4F1FA))
    static let inkSecondary = dynamic(hex(0x6A6478), hex(0xA7A1B8))

    /// R50 single-layer ceramic/obsidian keycap colors mirrored from `KeyboardLayout.swift`.
    static func keyFace(plain: Bool, night: Bool) -> Color {
        if plain { return night ? Color(uiColor: hex(0x2B2B30)) : Color.white }
        return night ? Color(uiColor: hex(0x262138)) : Color(uiColor: hex(0xFAF8F4))
    }

    static func keyBorder(plain: Bool, night: Bool) -> Color {
        if plain { return Color.white.opacity(night ? 0.14 : 0.70) }
        return night ? Color.white.opacity(0.10) : Color(uiColor: hex(0xD8D0C4))
    }

    static func keyShadow(night: Bool) -> Color {
        night ? Color.black.opacity(0.55) : Color(uiColor: hex(0xCFC7B8)).opacity(0.60)
    }
}

/// Primary tint used across Navigation, Controls, and CI SnapshotRenderer.
let mostoTint = MossOttoStyle.violet

/// The desk lamp's overhead beam cone in the OTTOSSOM stage.
struct LampCone: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX - 42, y: 0))
        p.addLine(to: CGPoint(x: r.midX + 42, y: 0))
        p.addLine(to: CGPoint(x: r.maxX + 24, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX - 24, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Studio desk-lamp overhead cone + subtle ambient wash matching OTTOSSOM photography.
struct LampConeBackdrop: View {
    let mode: StudioLampMode
    @Environment(\.colorScheme) private var scheme

    private var darkLook: Bool {
        mode == .night || (mode == .plain && scheme == .dark)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(stageBg)
            LampCone()
                .fill(
                    LinearGradient(
                        colors: coneColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: haloColors,
                        center: .center,
                        startRadius: 2,
                        endRadius: 110
                    )
                )
                .frame(width: 210, height: 64)
                .offset(y: -26)
        }
    }

    private var stageBg: Color {
        switch mode {
        case .day:
            return scheme == .dark ? Color(uiColor: MossOttoStyle.hex(0x231E33)) : Color(uiColor: MossOttoStyle.hex(0xFFFDF9))
        case .night:
            return Color(uiColor: MossOttoStyle.hex(0x191529))
        case .plain:
            return darkLook ? Color(uiColor: MossOttoStyle.hex(0x1E1E24)) : Color(uiColor: MossOttoStyle.hex(0xF5F4F0))
        }
    }

    private var coneColors: [Color] {
        switch mode {
        case .day:
            let c = Color(uiColor: MossOttoStyle.hex(0xF7CD7A))
            return [c.opacity(scheme == .dark ? 0.22 : 0.24), c.opacity(0.03), .clear]
        case .night:
            let c = Color(uiColor: MossOttoStyle.hex(0xFFC45A))
            return [c.opacity(0.28), c.opacity(0.08), .clear]
        case .plain:
            let c = Color.white
            return [c.opacity(darkLook ? 0.08 : 0.45), .clear]
        }
    }

    private var haloColors: [Color] {
        switch mode {
        case .day:
            return [Color(uiColor: MossOttoStyle.hex(0xFFD678)).opacity(0.55), .clear]
        case .night:
            return [Color(uiColor: MossOttoStyle.hex(0xFFC45A)).opacity(0.65), .clear]
        case .plain:
            return [Color.white.opacity(darkLook ? 0.14 : 0.40), .clear]
        }
    }
}

/// R50 Single-Layer Matte Monolith Keycap for Companion App specimens, Switch Tester & Xiaohe charts.
struct MonolithKeycapView: View {
    let label: String
    var secondary: String? = nil
    var initialMark: String? = nil
    var finals: [String] = []
    var pressed: Bool = false
    var plain: Bool = false
    var forceNight: Bool? = nil
    var homingNotch: Bool = false
    var ledColor: Color? = nil
    var cornerRadius: CGFloat = 11

    @Environment(\.colorScheme) private var scheme

    private var isNight: Bool { forceNight ?? (scheme == .dark) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(MossOttoStyle.keyFace(plain: plain, night: isNight))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(MossOttoStyle.keyBorder(plain: plain, night: isNight), lineWidth: 0.6)
                )
                .shadow(color: pressed ? .clear : MossOttoStyle.keyShadow(night: isNight), radius: 0, x: 0, y: 1.5)

            if let ledColor {
                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(ledColor)
                            .frame(width: 4.5, height: 4.5)
                    }
                    Spacer()
                }
                .padding(6)
            }

            if !finals.isEmpty || initialMark != nil {
                VStack(spacing: 1) {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(isNight ? Color.white : MossOttoStyle.inkPrimary)
                    if let initialMark {
                        Text(initialMark)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(MossOttoStyle.violet)
                    }
                    ForEach(finals, id: \.self) { f in
                        Text(f)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(MossOttoStyle.inkSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 5)
            } else {
                VStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 17, weight: .medium, design: plain ? .default : .rounded))
                        .foregroundStyle(isNight ? Color.white : MossOttoStyle.inkPrimary)
                    if let secondary {
                        Text(secondary)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(MossOttoStyle.inkSecondary)
                    }
                }
                .padding(.horizontal, 6)
            }

            if homingNotch {
                VStack {
                    Spacer()
                    Capsule()
                        .fill(MossOttoStyle.inkSecondary.opacity(0.32))
                        .frame(width: 22, height: 2.5)
                        .padding(.bottom, 6)
                }
            }
        }
        .scaleEffect(pressed ? 0.96 : 1.0)
        .offset(y: pressed ? 1.0 : 0)
        .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

// MARK: - Live Hardware Volume Monitor & Smart Non-Nagging Gate

enum VolumeZone: Equatable {
    case muted
    case comfortable
    case loud

    var label: String {
        switch self {
        case .muted: return "当前静音 · 将仅保留触感"
        case .comfortable: return "音量舒适 · 适合轻敲试听"
        case .loud: return "音量偏高 · 建议用侧键调低一点"
        }
    }

    var accent: Color {
        switch self {
        case .muted: return MossOttoStyle.inkSecondary
        case .comfortable: return MossOttoStyle.moss
        case .loud: return MossOttoStyle.lampAmber
        }
    }
}

/// Observes `AVAudioSession.outputVolume` locally (zero network) and guards the first audible toy interaction
/// with a tactile volume check sheet, plus a non-blocking banner when a fresh session starts above 70%.
@MainActor
final class VolumeMonitor: NSObject, ObservableObject {
    @Published var volume: Float
    @Published var hasConfirmedOnce: Bool {
        didSet { defaults.set(hasConfirmedOnce, forKey: Self.confirmedKey) }
    }
    @Published var showSheet = false
    @Published var showHighBanner = false

    private let defaults: UserDefaults
    private let observeSystem: Bool
    private static let confirmedKey = "mosto.volume.checked.v1"
    private var sessionBannerDismissed = false
    private var started = false
    private var pendingAction: (() -> Void)?
    private var observation: NSKeyValueObservation?

    init(defaults: UserDefaults = .standard, observeSystem: Bool = true, initialVolume: Float? = nil) {
        self.defaults = defaults
        self.observeSystem = observeSystem
        let confirmed = defaults.bool(forKey: Self.confirmedKey)
        self.hasConfirmedOnce = confirmed
        self.volume = initialVolume ?? (observeSystem ? AVAudioSession.sharedInstance().outputVolume : 0.45)
        super.init()
    }

    deinit {
        observation?.invalidate()
    }

    nonisolated static func zone(for volume: Float) -> VolumeZone {
        if volume <= 0.01 { return .muted }
        if volume <= 0.65 { return .comfortable }
        return .loud
    }

    var zone: VolumeZone { Self.zone(for: volume) }

    var percentage: Int {
        max(0, min(100, Int((volume * 100).rounded())))
    }

    var symbolName: String {
        if volume <= 0.01 { return "speaker.slash.fill" }
        if volume < 0.35 { return "speaker.wave.1.fill" }
        if volume <= 0.65 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    func startObserving() {
        guard observeSystem, !started else { return }
        started = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        volume = session.outputVolume
        evaluateHighBannerOnSessionStart()
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            let next = session.outputVolume
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.volume = next
                if self.showHighBanner && next <= 0.65 {
                    self.showHighBanner = false
                }
            }
        }
    }

    private func evaluateHighBannerOnSessionStart() {
        if hasConfirmedOnce && volume > 0.70 && !sessionBannerDismissed && KeyboardSettings.shared.keySound {
            showHighBanner = true
        }
    }

    /// Gates audible interactive toys: silent interactions run immediately; first audible use presents the
    /// live dimmer check sheet once, then persists confirmation and only whispers a non-blocking banner if >70%.
    func gateSoundInteraction(soundEnabled: Bool, action: @escaping () -> Void) {
        if !soundEnabled {
            action()
            return
        }
        if !hasConfirmedOnce {
            pendingAction = action
            showSheet = true
            return
        }
        if volume > 0.70 && !sessionBannerDismissed {
            showHighBanner = true
        }
        action()
    }

    func confirmAndProceed() {
        hasConfirmedOnce = true
        showSheet = false
        if volume > 0.70 {
            sessionBannerDismissed = true
            showHighBanner = false
        } else {
            showHighBanner = false
        }
        let act = pendingAction
        pendingAction = nil
        act?()
    }

    func dismissHighBanner() {
        sessionBannerDismissed = true
        showHighBanner = false
    }

    func playSound(_ id: SystemSoundID) {
        AudioServicesPlaySystemSound(id)
    }

    func playTestClick() {
        playSound(1104)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.66)
    }
}

/// Compact header capsule showing live volume state; tap at any time to re-open the dimmer check card.
struct VolumeBadgePill: View {
    @ObservedObject var monitor: VolumeMonitor
    var soundEnabled: Bool

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            monitor.showSheet = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: soundEnabled ? monitor.symbolName : "speaker.slash")
                    .font(.system(size: 11, weight: .semibold))
                Text(soundEnabled ? (monitor.zone == .muted ? "静音" : "\(monitor.percentage)%") : "声效关")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(soundEnabled ? monitor.zone.accent : MossOttoStyle.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5.5)
            .background(Capsule().fill(MossOttoStyle.surface))
            .overlay(Capsule().strokeBorder(MossOttoStyle.hairline, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("检查当前手机音量")
    }
}

/// Non-blocking banner shown on a fresh session only if confirmed before AND system volume exceeds 70%.
struct VolumeHighBanner: View {
    @ObservedObject var monitor: VolumeMonitor
    var onMuteSound: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MossOttoStyle.lampAmber)
            VStack(alignment: .leading, spacing: 1) {
                Text("当前音量 \(monitor.percentage)% 偏高")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MossOttoStyle.inkPrimary)
                Text("互动声效可能偏响，建议按侧边键调低或暂关闭")
                    .font(.caption2)
                    .foregroundStyle(MossOttoStyle.inkSecondary)
            }
            Spacer(minLength: 4)
            Button("静音", action: onMuteSound)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MossOttoStyle.violet)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(MossOttoStyle.violet.opacity(0.12)))
                .buttonStyle(.plain)
            Button {
                monitor.dismissHighBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(MossOttoStyle.inkSecondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MossOttoStyle.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(MossOttoStyle.lampAmber.opacity(0.45), lineWidth: 0.9)
        )
    }
}

/// Desk-lamp dimmer inspired volume confirmation card (live hardware volume KVO + tactile try-click keycap).
struct VolumeCheckSheet: View {
    @ObservedObject var monitor: VolumeMonitor
    var onSoundChanged: () -> Void = {}
    @State private var soundEnabled = KeyboardSettings.shared.keySound
    @State private var samplePressed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(uiImage: mostoImage("Mosto"))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .padding(4)
                    .background(Circle().fill(MossOttoStyle.lampAmber.opacity(0.16)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("先看一眼手机音量")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(MossOttoStyle.inkPrimary)
                    Text("按机身侧边音量键，下方光条会实时跟随")
                        .font(.caption)
                        .foregroundStyle(MossOttoStyle.inkSecondary)
                }
                Spacer(minLength: 0)
            }

            // Live 12-segment OTTOSSOM desk-lamp volume gauge
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: monitor.symbolName)
                        .foregroundStyle(monitor.zone.accent)
                    Text(monitor.zone.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MossOttoStyle.inkPrimary)
                    Spacer()
                    Text("\(monitor.percentage)%")
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(monitor.zone.accent)
                }

                GeometryReader { _ in
                    HStack(spacing: 6) {
                        ForEach(0..<12, id: \.self) { i in
                            let threshold = Float(i + 1) / 12.0
                            let lit = monitor.volume >= threshold - 0.04 && monitor.volume > 0.01
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(lit ? barColor(index: i) : MossOttoStyle.surfaceMuted)
                                .frame(height: lit ? 24 : 18)
                                .animation(.spring(response: 0.22, dampingFraction: 0.8), value: monitor.volume)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 28)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(MossOttoStyle.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(MossOttoStyle.hairline, lineWidth: 0.7)
            )

            // Sample tap + inline sound switch
            HStack(spacing: 12) {
                Button {
                    samplePressed = true
                    monitor.playTestClick()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) { samplePressed = false }
                } label: {
                    MonolithKeycapView(
                        label: "轻敲试听",
                        secondary: "1104 清脆声",
                        pressed: samplePressed,
                        ledColor: soundEnabled ? MossOttoStyle.moss : MossOttoStyle.inkSecondary
                    )
                    .frame(height: 60)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("互动与按键音", isOn: $soundEnabled)
                        .font(.subheadline.weight(.semibold))
                        .tint(MossOttoStyle.violet)
                        .onChange(of: soundEnabled) { enabled in
                            KeyboardSettings.shared.keySound = enabled
                            onSoundChanged()
                        }
                    Text(soundEnabled ? "已开启 · 如在安静环境可先关掉" : "已静音 · 仅保留轻触震动反馈")
                        .font(.caption2)
                        .foregroundStyle(MossOttoStyle.inkSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MossOttoStyle.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(MossOttoStyle.hairline, lineWidth: 0.7)
                )
            }

            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                monitor.confirmAndProceed()
                dismiss()
            } label: {
                Text("音量合适，开始体验")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MossOttoStyle.violet))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(MossOttoStyle.canvas.ignoresSafeArea())
        .onAppear {
            soundEnabled = KeyboardSettings.shared.keySound
            monitor.startObserving()
        }
    }

    private func barColor(index: Int) -> Color {
        if index >= 8 { return MossOttoStyle.lampAmber }
        return MossOttoStyle.moss
    }
}

// MARK: - 3-Key Physical Switch Tester Toy

struct SwitchTesterToy: View {
    @ObservedObject var volume: VolumeMonitor
    var mode: StudioLampMode
    var soundEnabled: Bool
    var onMostoBlink: () -> Void

    @State private var pressedKey: Int? = nil
    @State private var readout = "轻触 3 枚实体试轴，感受 R50 分级触感与原声"

    private var forceNight: Bool? {
        switch mode {
        case .night: return true
        case .day: return false
        case .plain: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("台灯下 · 3 枚试轴器")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MossOttoStyle.inkSecondary)
                Spacer()
                Text(readout)
                    .font(.caption2)
                    .foregroundStyle(MossOttoStyle.inkSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                Button {
                    trigger(id: 0, sound: 1104, style: .light, intensity: 0.66, desc: "轻脆字母 · Light 0.66")
                } label: {
                    MonolithKeycapView(
                        label: "A",
                        secondary: "轻脆字母",
                        pressed: pressedKey == 0,
                        plain: mode == .plain,
                        forceNight: forceNight
                    )
                    .frame(height: 60)
                }
                .buttonStyle(.plain)

                Button {
                    trigger(id: 1, sound: 1104, style: .rigid, intensity: 0.78, desc: "沉稳定位 · Rigid 0.78")
                } label: {
                    MonolithKeycapView(
                        label: "空格",
                        secondary: "盲打凹痕",
                        pressed: pressedKey == 1,
                        plain: mode == .plain,
                        forceNight: forceNight,
                        homingNotch: mode != .plain
                    )
                    .frame(height: 60)
                }
                .buttonStyle(.plain)

                Button {
                    trigger(id: 2, sound: 1156, style: .soft, intensity: 0.85, desc: "软弹彩蛋 · Soft 0.85")
                } label: {
                    MonolithKeycapView(
                        label: "Mosto",
                        secondary: "彩蛋轻捏",
                        pressed: pressedKey == 2,
                        plain: mode == .plain,
                        forceNight: forceNight,
                        ledColor: MossOttoStyle.lampAmber
                    )
                    .frame(height: 60)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(MossOttoStyle.surfaceMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(MossOttoStyle.hairline, lineWidth: 0.7)
            )
        }
    }

    private func trigger(id: Int, sound: SystemSoundID, style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat, desc: String) {
        pressedKey = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            if pressedKey == id { pressedKey = nil }
        }
        volume.gateSoundInteraction(soundEnabled: soundEnabled) {
            UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: intensity)
            if soundEnabled {
                AudioServicesPlaySystemSound(sound)
            }
            if id == 2 {
                onMostoBlink()
            }
            readout = desc
        }
    }
}

// MARK: - Shared OTTOSSOM Layout Primitives

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

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MossOttoStyle.inkSecondary)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(MossOttoStyle.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(MossOttoStyle.hairline, lineWidth: 0.7)
                )
        }
    }
}

struct IconTile: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(MossOttoStyle.violet)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MossOttoStyle.violet.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(MossOttoStyle.violet.opacity(0.20), lineWidth: 0.6)
            )
            .accessibilityHidden(true)
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
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MossOttoStyle.inkPrimary)
                }
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(title == nil ? MossOttoStyle.inkPrimary : MossOttoStyle.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

func aboutIcon(_ id: String) -> String {
    switch id {
    case "privacy": return "hand.raised"
    case "terms": return "doc.text"
    default: return "shippingbox"
    }
}
