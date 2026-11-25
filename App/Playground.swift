import SwiftUI
import UIKit
import AudioToolbox

/// Day and night lighting states for the OTTOSSOM IP family desk-lamp room.
enum FamilyAtmosphere: Int, CaseIterable, Identifiable {
    case day = 0
    case night = 1

    var id: Int { rawValue }
    var isNight: Bool { self == .night }
    var toggled: FamilyAtmosphere { self == .day ? .night : .day }

    var label: String {
        switch self {
        case .day: return "日光"
        case .night: return "夜灯"
        }
    }

    var stageCaption: String {
        switch self {
        case .day: return "窗边日光 · Moss、Mosto 与 Otto 都在桌上"
        case .night: return "夜灯亮起 · Otto 灯珠与 Mosto 尾尖同步微光"
        }
    }
}

/// Canonical OTTOSSOM studio IP family members matching `Tools/ip/ip3d.py` & `Tools/ip/mosto3d.py`.
enum FamilyMember: String, CaseIterable, Identifiable {
    case moss
    case mosto
    case otto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .moss: return "Moss"
        case .mosto: return "Mosto"
        case .otto: return "Otto"
        }
    }

    var chineseRole: String {
        switch self {
        case .moss: return "摸索 · 好奇心"
        case .mosto: return "小魔王 · 键盘伙伴"
        case .otto: return "台灯 · 柔和陪伴"
        }
    }

    var bio: String {
        switch self {
        case .moss: return "顶着薄荷嫩芽的绒绿小鹅卵石，像刚学会打字时的那点好奇与轻快。"
        case .mosto: return "Moss 和 Otto 共同的淘气一面，住在系统键盘的候选栏左角，停下输入就会探头。"
        case .otto: return "头顶弯灯珠的深蓝台灯大人，话不多，夜里会把光调暖陪你慢慢打完一句话。"
        }
    }

    var accentColor: Color {
        switch self {
        case .moss: return MossOttoStyle.moss
        case .mosto: return MossOttoStyle.violet
        case .otto: return MossOttoStyle.ottoIndigo
        }
    }

    func spriteName(atmosphere: FamilyAtmosphere, reacting: Bool) -> String {
        switch self {
        case .moss:
            return reacting ? "MossHappy" : "Moss"
        case .mosto:
            if reacting && !atmosphere.isNight { return "MostoBlink" }
            return atmosphere.isNight ? "MostoNight" : "Mosto"
        case .otto:
            return (atmosphere.isNight || reacting) ? "OttoLit" : "Otto"
        }
    }
}

/// Interactive state and volume-gated sensory responses for the OTTOSSOM IP family room.
@MainActor
final class FamilyStageModel: ObservableObject {
    @Published var atmosphere: FamilyAtmosphere = .day
    @Published var activeMember: FamilyMember = .mosto
    @Published var reactingMember: FamilyMember? = nil
    @Published var secondaryReactingMember: FamilyMember? = nil
    @Published var reactionNonce: Int = 0
    @Published var soundEnabled: Bool = KeyboardSettings.shared.keySound
    @Published var statusLine: String = "轻点伙伴打招呼，下拉灯绳换光线"
    @Published var verificationCelebrated: Bool = false

    func interact(with member: FamilyMember, volume: VolumeMonitor? = nil) {
        let perform = { [weak self] in
            guard let self else { return }
            self.activeMember = member
            if member == .otto {
                self.atmosphere = self.atmosphere.toggled
            }
            let secondary: FamilyMember = member == .moss ? .mosto : (member == .mosto ? .otto : .mosto)
            self.triggerReaction(member: member, secondary: secondary)

            if KeyboardSettings.shared.feedback {
                let style: UIImpactFeedbackGenerator.FeedbackStyle = member == .moss ? .light : (member == .mosto ? .soft : .medium)
                let intensity: CGFloat = member == .moss ? 0.66 : (member == .mosto ? 0.82 : 0.72)
                UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: intensity)
            }
            if self.soundEnabled {
                let soundID: SystemSoundID = member == .mosto ? 1156 : 1104
                AudioServicesPlaySystemSound(soundID)
            }

            switch member {
            case .moss:
                self.statusLine = "Moss 蹦了一下，薄荷叶轻轻一晃"
            case .mosto:
                self.statusLine = self.atmosphere.isNight
                    ? "Mosto 尾尖亮起了暖金小灯"
                    : "Mosto 住在候选栏左角，轻点开颜文字"
            case .otto:
                self.statusLine = self.atmosphere.isNight
                    ? "Otto 点亮了暖黄灯珠陪你打字"
                    : "Otto 收起夜灯，换回窗边日光"
            }
        }

        if let volume {
            volume.gateSoundInteraction(soundEnabled: soundEnabled, action: perform)
        } else {
            perform()
        }
    }

    func toggleAtmosphere(volume: VolumeMonitor? = nil) {
        let perform = { [weak self] in
            guard let self else { return }
            self.atmosphere = self.atmosphere.toggled
            self.activeMember = self.atmosphere.isNight ? .otto : .mosto
            self.triggerReaction(member: self.atmosphere.isNight ? .otto : .moss, secondary: .mosto)
            if KeyboardSettings.shared.feedback {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.72)
            }
            if self.soundEnabled {
                AudioServicesPlaySystemSound(1104)
            }
            self.statusLine = self.atmosphere.stageCaption
        }

        if let volume {
            volume.gateSoundInteraction(soundEnabled: soundEnabled, action: perform)
        } else {
            perform()
        }
    }

    func focusFromRoster(_ member: FamilyMember) {
        activeMember = member
        triggerReaction(member: member)
        statusLine = "\(member.displayName)（\(member.chineseRole)）：\(member.bio)"
    }

    func celebrateVerification() {
        verificationCelebrated = true
        activeMember = .moss
        triggerReaction(member: .moss, secondary: .mosto, duration: 1.25)
        statusLine = "真机键盘已验通，Moss、Otto 和 Mosto 都准备好了"
    }

    func syncSoundFromSettings() {
        soundEnabled = KeyboardSettings.shared.keySound
    }

    private func triggerReaction(member: FamilyMember, secondary: FamilyMember? = nil, duration: TimeInterval = 0.85) {
        reactingMember = member
        secondaryReactingMember = secondary
        reactionNonce += 1
        let expected = reactionNonce
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.reactionNonce == expected else { return }
            self.reactingMember = nil
            self.secondaryReactingMember = nil
        }
    }
}

/// Interactive OTTOSSOM IP family desk-lamp room showcasing Moss, Mosto, and Otto side by side.
struct FamilyLampStageView: View {
    @ObservedObject var model: FamilyStageModel
    @ObservedObject var volume: VolumeMonitor

    @State private var pullFraction: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var darkStage: Bool { model.atmosphere.isNight || scheme == .dark }

    @MainActor
    static func renderSnapshotSizeForTests(width: CGFloat) -> CGSize {
        let model = FamilyStageModel()
        let vol = VolumeMonitor(defaults: .standard, observeSystem: false, initialVolume: 0.42)
        let r = ImageRenderer(content: FamilyLampStageView(model: model, volume: vol).frame(width: width))
        r.scale = 2.0
        return r.uiImage?.size ?? .zero
    }

        var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)

                    // 3-figure studio stage grounded softly onto a warm desk surface
                    HStack(alignment: .bottom, spacing: 6) {
                        characterFigure(
                            member: .moss,
                            height: 82,
                            hopOffset: -9,
                            warmBeadGlow: false
                        )

                        characterFigure(
                            member: .mosto,
                            height: 98,
                            hopOffset: -5,
                            warmBeadGlow: model.atmosphere.isNight
                        )
                        .zIndex(2)

                        characterFigure(
                            member: .otto,
                            height: 108,
                            hopOffset: -3,
                            warmBeadGlow: model.atmosphere.isNight || model.reactingMember == .otto || model.secondaryReactingMember == .otto
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 184)

                HStack(spacing: 6) {
                    Circle()
                        .fill(model.activeMember.accentColor)
                        .frame(width: 6, height: 6)
                    Text("OTTOSSOM 桌面伙伴")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(darkStage ? Color.white.opacity(0.66) : MossOttoStyle.inkSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 13)
                .accessibilityHidden(true)
            }
            .overlay(alignment: .topTrailing) {
                LampPullCordSwitch(
                    isNight: model.atmosphere.isNight,
                    darkStage: darkStage,
                    pullFraction: $pullFraction
                ) {
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.26)) {
                        model.toggleAtmosphere(volume: volume)
                    }
                }
                .padding(.trailing, 8)
            }

            Rectangle()
                .fill(darkStage ? Color.white.opacity(0.08) : MossOttoStyle.hairline)
                .frame(height: 0.5)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    footerText
                    Spacer(minLength: 6)
                    footerLampButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    footerText
                    HStack {
                        Spacer(minLength: 0)
                        footerLampButton
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                darkStage
                    ? Color(uiColor: MossOttoStyle.hex(0x161224)).opacity(0.72)
                    : MossOttoStyle.surface.opacity(0.78)
            )
        }
        .background(LampConeBackdrop(isNight: model.atmosphere.isNight, dimFactor: pullFraction))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(darkStage ? Color.white.opacity(0.12) : MossOttoStyle.hairline, lineWidth: 0.5)
        )
    }

    private var footerText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.activeMember.displayName + " · " + model.activeMember.chineseRole)
                .font(.caption.weight(.semibold))
                .foregroundStyle(darkStage ? Color.white.opacity(0.92) : MossOttoStyle.inkPrimary)
            Text(model.statusLine)
                .font(.caption2)
                .foregroundStyle(darkStage ? Color.white.opacity(0.68) : MossOttoStyle.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footerLampButton: some View {
        Button {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.26)) {
                model.toggleAtmosphere(volume: volume)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.atmosphere.isNight ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(model.atmosphere.label)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(
                model.atmosphere.isNight
                    ? Color(uiColor: MossOttoStyle.hex(0x191529))
                    : (darkStage ? Color.white : MossOttoStyle.inkPrimary)
            )
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(
                Capsule().fill(
                    model.atmosphere.isNight
                        ? Color(uiColor: MossOttoStyle.hex(0xFFC45A))
                        : (darkStage ? Color.white.opacity(0.14) : MossOttoStyle.surfaceMuted)
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换桌面光线，当前\(model.atmosphere.label)")
    }

    @ViewBuilder
    private func characterFigure(
        member: FamilyMember,
        height: CGFloat,
        hopOffset: CGFloat,
        warmBeadGlow: Bool
    ) -> some View {
        let isPrimary = model.reactingMember == member
        let isSecondary = model.secondaryReactingMember == member
        let reacting = isPrimary || isSecondary
        let selected = model.activeMember == member
        let sprite = member.spriteName(atmosphere: model.atmosphere, reacting: reacting)
        let motionScale: CGFloat = reduceMotion ? 1.0 : (isPrimary ? (member == .moss ? 1.05 : 1.03) : (isSecondary ? 1.015 : 1.0))
        let motionY: CGFloat = reduceMotion ? 0 : (isPrimary ? hopOffset : (isSecondary ? hopOffset * 0.35 : 0))

        Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.30, dampingFraction: 0.64)) {
                model.interact(with: member, volume: volume)
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .bottom) {
                    if warmBeadGlow {
                        let base = Color(uiColor: MossOttoStyle.hex(0xFFC66E))
                        let peakOpacity = member == .otto ? 0.30 : 0.22
                        Circle()
                            .fill(
                                RadialGradient(
                                    stops: [
                                        .init(color: base.opacity(peakOpacity), location: 0.0),
                                        .init(color: base.opacity(peakOpacity * 0.48), location: 0.38),
                                        .init(color: base.opacity(peakOpacity * 0.12), location: 0.72),
                                        .init(color: .clear, location: 1.0),
                                    ],
                                    center: .center,
                                    startRadius: 1,
                                    endRadius: height * 0.42
                                )
                            )
                            .frame(width: height * 0.88, height: height * 0.88)
                            .offset(
                                x: member == .otto ? -height * 0.18 : height * 0.22,
                                y: member == .otto ? -height * 0.42 : -height * 0.22
                            )
                            .allowsHitTesting(false)
                    }

                    Ellipse()
                        .fill(Color.black.opacity(darkStage ? 0.44 : 0.13))
                        .frame(width: height * 0.68, height: 11)
                        .blur(radius: 4)
                        .offset(y: 3)

                    Image(uiImage: mostoImage(sprite))
                        .resizable()
                        .scaledToFit()
                        .frame(height: height)
                        .scaleEffect(motionScale, anchor: .bottom)
                        .offset(y: motionY)
                }
                .frame(height: height + 4, alignment: .bottom)

                VStack(spacing: 3) {
                    Text(member.displayName)
                        .font(.system(size: 10.5, weight: selected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(
                            selected
                                ? (darkStage ? Color.white.opacity(0.92) : member.accentColor)
                                : (darkStage ? Color.white.opacity(0.50) : MossOttoStyle.inkSecondary.opacity(0.75))
                        )
                    Capsule()
                        .fill(selected ? member.accentColor : Color.clear)
                        .frame(width: 14, height: 2.5)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(member.displayName)，\(member.chineseRole)")
        .accessibilityHint("轻点与 \(member.displayName) 互动")
    }
}
