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
        case .mosto: return "Moss 和 Otto 共同的淘气一面，住在键盘底栏的 Mosto 超级键里，连点 3 下有惊喜。"
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

/// Interactive state and sensory responses for the OTTOSSOM IP family room.
@MainActor
final class FamilyStageModel: ObservableObject {
    @Published var atmosphere: FamilyAtmosphere = .day
    @Published var activeMember: FamilyMember = .mosto
    @Published var reactingMember: FamilyMember? = nil
    @Published var secondaryReactingMember: FamilyMember? = nil
    @Published var reactionNonce: Int = 0
    @Published var soundEnabled: Bool = KeyboardSettings.shared.keySound
    @Published var statusLine: String = "轻点伙伴打招呼，下拉灯绳换光线 · 连点 Mosto 3 下有彩蛋"
    @Published var verificationCelebrated: Bool = false
    @Published var showMostoRun: Bool = false
    private var mostoTapStreak: Int = 0
    private var lastMostoTapTime: Date = .distantPast

    func interact(with member: FamilyMember) {
        activeMember = member
        if member == .otto {
            atmosphere = atmosphere.toggled
        }
        let secondary: FamilyMember = member == .moss ? .mosto : (member == .mosto ? .otto : .mosto)
        triggerReaction(member: member, secondary: secondary)

        if KeyboardSettings.shared.feedback {
            let style: UIImpactFeedbackGenerator.FeedbackStyle = member == .moss ? .light : (member == .mosto ? .soft : .medium)
            let intensity: CGFloat = member == .moss ? 0.66 : (member == .mosto ? 0.82 : 0.72)
            UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: intensity)
        }
        if soundEnabled {
            let soundID: SystemSoundID = member == .mosto ? 1156 : 1104
            AudioServicesPlaySystemSound(soundID)
        }

        switch member {
        case .moss:
            statusLine = "Moss 蹦了一下，薄荷叶轻轻一晃"
        case .mosto:
            let now = Date()
            mostoTapStreak = now.timeIntervalSince(lastMostoTapTime) < 1.6 ? (mostoTapStreak + 1) : 1
            lastMostoTapTime = now
            if mostoTapStreak >= 3 {
                mostoTapStreak = 0
                showMostoRun = true
                statusLine = "彩蛋已唤醒：陪 Mosto 跑一局桌边夜行"
            } else if mostoTapStreak == 2 {
                statusLine = "再轻点 Mosto 一下，唤醒桌边夜行彩蛋"
            } else {
                statusLine = atmosphere.isNight
                    ? "Mosto 尾尖亮起了暖金小灯（连点 3 下玩彩蛋）"
                    : "Mosto 住在底栏超级键：单击表情 · 双击颜文字 · 长按设置"
            }
        case .otto:
            statusLine = atmosphere.isNight
                ? "Otto 点亮了暖黄灯珠陪你打字"
                : "Otto 收起夜灯，换回窗边日光"
        }
    }

    func toggleAtmosphere() {
        atmosphere = atmosphere.toggled
        activeMember = atmosphere.isNight ? .otto : .mosto
        triggerReaction(member: atmosphere.isNight ? .otto : .moss, secondary: .mosto)
        if KeyboardSettings.shared.feedback {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.72)
        }
        if soundEnabled {
            AudioServicesPlaySystemSound(1104)
        }
        statusLine = atmosphere.stageCaption
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
        statusLine = "真机键盘已验通，随时来《摸索台灯》找 Moss 和 Otto 玩"
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

    @State private var pullFraction: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var darkStage: Bool { model.atmosphere.isNight || scheme == .dark }

    @MainActor
    static func renderSnapshotSizeForTests(width: CGFloat) -> CGSize {
        let model = FamilyStageModel()
        let r = ImageRenderer(content: FamilyLampStageView(model: model).frame(width: width))
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
                        model.toggleAtmosphere()
                    }
                }
                .padding(.trailing, 8)
            }

            Rectangle()
                .fill(darkStage ? Color.white.opacity(0.08) : MossOttoStyle.hairline)
                .frame(height: 0.5)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 8) {
                    Text(model.activeMember.displayName + " · " + model.activeMember.chineseRole)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(darkStage ? Color.white.opacity(0.94) : MossOttoStyle.inkPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    footerLampButton
                }
                Text(model.statusLine)
                    .font(.caption2)
                    .foregroundStyle(darkStage ? Color.white.opacity(0.72) : MossOttoStyle.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var footerLampButton: some View {
        Button {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.26)) {
                model.toggleAtmosphere()
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
                model.interact(with: member)
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


// MARK: - R96/R100.5: Offline Easter Egg Game — 桌边夜行 (Mosto Run)

/// Pure-Swift offline endless runner state machine (zero network, zero SpriteKit bloat, 100% unit-testable).
struct MostoRunEngine {
    struct Obstacle: Identifiable {
        let id: Int
        var x: CGFloat
        var y: CGFloat = 0
        let width: CGFloat
        let height: CGFloat
        let kind: Int // 0 = pencil, 1 = wooden block, 2 = hardcover book, 3 = gliding paper airplane (200+ pts)
    }
    struct Bead: Identifiable {
        let id: Int
        var x: CGFloat
        var y: CGFloat
        var collected: Bool = false
    }
    struct ShieldPickup: Identifiable {
        let id: Int
        var x: CGFloat
        var y: CGFloat
        var collected: Bool = false
    }
    struct Particle: Identifiable {
        let id: Int
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat
        var vy: CGFloat
        var life: CGFloat
        let maxLife: CGFloat
        let size: CGFloat
        let kind: Int // 0 = violet double-jump star, 1 = gold bead sparkle, 2 = mint shield burst
    }
    struct FloatingPopup: Identifiable {
        let id: Int
        var x: CGFloat
        var y: CGFloat
        let text: String
        var age: CGFloat = 0
        let kind: Int // 0 = gold, 1 = mint, 2 = violet combo
    }

    static let highScoreKey = "mosto.run.highscore.v1"

    var playerY: CGFloat = 0          // height above desk ground (0 = grounded)
    var velocityY: CGFloat = 0
    var speed: CGFloat = 230          // pt / sec
    var distance: CGFloat = 0
    var bonusScore: Int = 0
    var running: Bool = false
    var gameOver: Bool = false
    var jumpsRemaining: Int = 2
    var isDoubleJumping: Bool = false
    var isHoldingJump: Bool = false
    var landingSquash: CGFloat = 0
    var combo: Int = 0
    var maxCombo: Int = 0
    var hasShield: Bool = false
    var shieldFlash: CGFloat = 0
    var reached100: Bool = false
    var reached200: Bool = false
    var reached300: Bool = false
    var obstacles: [Obstacle] = []
    var beads: [Bead] = []
    var shieldPickups: [ShieldPickup] = []
    var particles: [Particle] = []
    var popups: [FloatingPopup] = []
    private var nextID: Int = 1
    private var spawnCooldown: CGFloat = 0.9
    private var pendingDoubleJumpFX: Bool = false

    var score: Int { Int(distance / 14) + bonusScore }
    /// Seamless Day ⇄ Night desk-lamp cycle every 100 points.
    var isNight: Bool { (score / 100) % 2 == 1 }

    mutating func start() {
        playerY = 0
        velocityY = 0
        speed = 230
        distance = 0
        bonusScore = 0
        running = true
        gameOver = false
        jumpsRemaining = 2
        isDoubleJumping = false
        isHoldingJump = false
        landingSquash = 0
        combo = 0
        maxCombo = 0
        hasShield = false
        shieldFlash = 0
        reached100 = false
        reached200 = false
        reached300 = false
        obstacles = []
        beads = []
        shieldPickups = []
        particles = []
        popups = []
        spawnCooldown = 0.85
        pendingDoubleJumpFX = false
    }

    @discardableResult
    mutating func jump(strong: Bool = false) -> Bool {
        if gameOver {
            start()
            velocityY = strong ? 560 : 510
            jumpsRemaining = 1
            isHoldingJump = true
            return true
        }
        if !running {
            start()
        }
        if playerY <= 1.5 {
            velocityY = strong ? 560 : 510
            jumpsRemaining = 1
            isDoubleJumping = false
            isHoldingJump = true
            return true
        }
        if jumpsRemaining > 0 {
            velocityY = 470
            jumpsRemaining = 0
            isDoubleJumping = true
            isHoldingJump = true
            pendingDoubleJumpFX = true
            spawnBurst(x: 64, y: playerY + 6, count: 7, kind: 0, speedScale: 1.0)
            return true
        }
        return false
    }

    mutating func releaseJump() {
        isHoldingJump = false
        if velocityY > 240 {
            velocityY = 240
        }
    }

    private mutating func spawnBurst(x: CGFloat, y: CGFloat, count: Int, kind: Int, speedScale: CGFloat) {
        for i in 0..<count {
            nextID += 1
            let angle = -0.35 + CGFloat(i) * (3.8 / CGFloat(max(1, count - 1)))
            let spd = (60 + CGFloat((nextID * 29) % 70)) * speedScale
            let vx = (kind == 0 ? -abs(cos(angle)) : cos(angle)) * spd - 35
            let vy = sin(angle) * spd * 0.7 - 20
            let maxLife: CGFloat = kind == 2 ? 0.55 : 0.42
            particles.append(Particle(
                id: nextID,
                x: x,
                y: y,
                vx: vx,
                vy: vy,
                life: maxLife,
                maxLife: maxLife,
                size: kind == 0 ? 5.5 : 4.5,
                kind: kind
            ))
        }
    }

    private mutating func addPopup(x: CGFloat, y: CGFloat, text: String, kind: Int) {
        nextID += 1
        popups.append(FloatingPopup(id: nextID, x: x, y: y, text: text, age: 0, kind: kind))
        if popups.count > 8 { popups.removeFirst() }
    }

    /// Advances physics by `dt` seconds.
    @discardableResult
    mutating func step(dt rawDt: CGFloat, trackWidth: CGFloat = 360) -> (collected: Bool, died: Bool, doubleJumped: Bool, shieldPicked: Bool, shieldBlocked: Bool) {
        guard running, !gameOver else { return (false, false, false, false, false) }
        let dt = min(max(rawDt, 0.001), 0.05)
        speed = min(430, 230 + CGFloat(score) * 0.45)
        distance += speed * dt
        landingSquash = max(0, landingSquash - dt * 5.2)
        shieldFlash = max(0, shieldFlash - dt * 2.8)

        let djFX = pendingDoubleJumpFX
        pendingDoubleJumpFX = false

        // Particle & popup lifetimes
        for i in particles.indices {
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            particles[i].vy -= 380 * dt
            particles[i].life -= dt
        }
        particles.removeAll { $0.life <= 0 }
        for i in popups.indices {
            popups[i].y += 28 * dt
            popups[i].age += dt
        }
        popups.removeAll { $0.age >= 0.85 }

        // Gravity & ground clamp
        let wasAirborne = playerY > 1.5
        let gravity: CGFloat = 1480
        velocityY -= gravity * dt
        playerY += velocityY * dt
        if playerY <= 0 {
            playerY = 0
            velocityY = 0
            jumpsRemaining = 2
            isDoubleJumping = false
            if wasAirborne { landingSquash = 1.0 }
        }

        // Milestones
        let sNow = score
        if sNow >= 100 { reached100 = true }
        if sNow >= 200 { reached200 = true }
        if sNow >= 300 { reached300 = true }

        // Spawn obstacles, beads & rare Moss mint shield pickups
        spawnCooldown -= dt
        if spawnCooldown <= 0 {
            let kind: Int
            let w: CGFloat
            let h: CGFloat
            let y: CGFloat
            if sNow >= 200 && nextID % 4 == 0 {
                kind = 3 // paper airplane gliding low
                w = 30; h = 18; y = 24
            } else {
                kind = nextID % 3
                switch kind {
                case 0: w = 16; h = 34; y = 0
                case 1: w = 26; h = 26; y = 0
                default: w = 30; h = 22; y = 0
                }
            }
            obstacles.append(Obstacle(id: nextID, x: trackWidth + 28, y: y, width: w, height: h, kind: kind))
            if nextID % 2 == 1 {
                let beadY = kind == 3 ? 68 : h + 40
                beads.append(Bead(id: nextID + 10000, x: trackWidth + 28 + w * 0.5, y: beadY))
            }
            if nextID % 11 == 0 && !hasShield && shieldPickups.isEmpty {
                shieldPickups.append(ShieldPickup(id: nextID + 20000, x: trackWidth + 92, y: 62))
            }
            nextID += 1
            let pace = max(0.70, 1.38 - (speed - 230) / 420)
            spawnCooldown = pace + CGFloat((nextID * 37) % 10) * 0.045
        }

        // Move & prune
        let dx = speed * dt
        for i in obstacles.indices {
            obstacles[i].x -= (obstacles[i].kind == 3 ? dx * 1.16 : dx)
        }
        obstacles.removeAll { $0.x + $0.width < -36 }
        for i in beads.indices { beads[i].x -= dx }
        if beads.contains(where: { !$0.collected && $0.x < 28 }) {
            combo = 0
        }
        beads.removeAll { $0.x < 28 || $0.collected }
        for i in shieldPickups.indices { shieldPickups[i].x -= dx }
        shieldPickups.removeAll { $0.x < -24 || $0.collected }

        // Player hitbox centered at x = 66, size 26x28
        let pRect = CGRect(x: 52, y: playerY + 2, width: 26, height: 28)
        var gotBead = false
        for i in beads.indices where !beads[i].collected {
            let bRect = CGRect(x: beads[i].x - 10, y: beads[i].y - 10, width: 20, height: 20)
            if pRect.intersects(bRect) {
                beads[i].collected = true
                combo += 1
                maxCombo = max(maxCombo, combo)
                let base = combo >= 3 ? 20 : (combo == 2 ? 15 : 10)
                let gain = base + (sNow >= 300 ? 5 : 0)
                bonusScore += gain
                gotBead = true
                spawnBurst(x: beads[i].x, y: beads[i].y, count: 6, kind: 1, speedScale: 0.8)
                addPopup(x: beads[i].x, y: beads[i].y + 10, text: combo >= 2 ? "+\(gain) x\(min(combo, 3))" : "+\(gain)", kind: combo >= 2 ? 2 : 0)
            }
        }

        var gotShield = false
        for i in shieldPickups.indices where !shieldPickups[i].collected {
            let sRect = CGRect(x: shieldPickups[i].x - 12, y: shieldPickups[i].y - 12, width: 24, height: 24)
            if pRect.intersects(sRect) {
                shieldPickups[i].collected = true
                hasShield = true
                gotShield = true
                spawnBurst(x: shieldPickups[i].x, y: shieldPickups[i].y, count: 8, kind: 2, speedScale: 0.9)
                addPopup(x: 68, y: playerY + 42, text: "薄荷护盾", kind: 1)
            }
        }

        var blockedByShield = false
        for idx in obstacles.indices {
            let o = obstacles[idx]
            let oRect = CGRect(x: o.x + 3, y: o.y + 2, width: max(8, o.width - 6), height: max(10, o.height - 5))
            if pRect.intersects(oRect) {
                if hasShield {
                    hasShield = false
                    shieldFlash = 1.0
                    blockedByShield = true
                    spawnBurst(x: o.x + o.width * 0.5, y: o.y + o.height * 0.5, count: 10, kind: 2, speedScale: 1.25)
                    addPopup(x: 70, y: playerY + 40, text: "护盾抵挡", kind: 1)
                    obstacles.remove(at: idx)
                    break
                }
                gameOver = true
                running = false
                return (gotBead, true, djFX, gotShield, false)
            }
        }
        return (gotBead, false, djFX, gotShield, blockedByShield)
    }

    static func loadHighScore(defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: highScoreKey)
    }

    @discardableResult
    static func recordHighScore(_ score: Int, defaults: UserDefaults = .standard) -> Int {
        let best = max(score, defaults.integer(forKey: highScoreKey))
        defaults.set(best, forKey: highScoreKey)
        return best
    }
}

/// High-frequency non-publishing game controller so TimelineView + Canvas runs at native 60/120fps
/// without triggering SwiftUI View-tree invalidation, per-frame image decoding, or Taptic Engine hitches.
final class MostoRunController: ObservableObject {
    var engine = MostoRunEngine()
    private var lastTimestamp: TimeInterval? = nil
    private var jumpBufferRemaining: CGFloat = 0
    private var lastPublishedScore: Int = 0
    private var lastPublishedRunning: Bool = false
    private var lastPublishedGameOver: Bool = false
    private var lastPublishedNight: Bool = false
    private var lastPublishedCombo: Int = 0
    private var lastPublishedMaxCombo: Int = 0
    private var lastPublishedShield: Bool = false
    private var lastPublishedMilestone: String = ""

    @Published var displayedScore: Int = 0
    @Published var bestScore: Int = MostoRunEngine.loadHighScore()
    @Published var isRunning: Bool = false
    @Published var isGameOver: Bool = false
    @Published var isNight: Bool = false
    @Published var displayedCombo: Int = 0
    @Published var maxCombo: Int = 0
    @Published var hasShield: Bool = false
    @Published var milestoneText: String = ""

    // Pre-downsampled sprites (120x120 px = 40pt @3x) cached once so Canvas never decodes PNGs per frame.
    let mostoDayImage: Image
    let mostoNightImage: Image
    let ottoLitImage: Image
    let mossHappyImage: Image

    // Pre-warmed haptic generators to eliminate main-thread XPC stutter on jump/pickup.
    private let jumpHaptic = UIImpactFeedbackGenerator(style: .light)
    private let doubleJumpHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let beadHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let shieldHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let crashHaptic = UINotificationFeedbackGenerator()

    init() {
        self.mostoDayImage = Image(uiImage: Self.cachedSprite("Mosto", side: 120))
        self.mostoNightImage = Image(uiImage: Self.cachedSprite("MostoNight", side: 120))
        self.ottoLitImage = Image(uiImage: Self.cachedSprite("OttoLit", side: 120))
        self.mossHappyImage = Image(uiImage: Self.cachedSprite("MossHappy", side: 120))
    }

    private static func cachedSprite(_ name: String, side: CGFloat) -> UIImage {
        let raw = mostoImage(name)
        guard raw.size.width > 0, raw.size.height > 0 else { return raw }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            raw.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    func prepareHaptics() {
        jumpHaptic.prepare()
        doubleJumpHaptic.prepare()
        beadHaptic.prepare()
        shieldHaptic.prepare()
        crashHaptic.prepare()
    }

    func handleTouchDown() {
        let wasRunning = engine.running
        let wasGameOver = engine.gameOver
        let wasAirborne = engine.playerY > 1.5 && wasRunning && !wasGameOver
        if engine.jump() {
            jumpBufferRemaining = 0
            if !wasRunning || wasGameOver {
                lastTimestamp = nil
                prepareHaptics()
            }
            if KeyboardSettings.shared.feedback {
                if wasAirborne {
                    doubleJumpHaptic.impactOccurred(intensity: 0.85)
                    doubleJumpHaptic.prepare()
                } else {
                    jumpHaptic.impactOccurred(intensity: 0.72)
                    jumpHaptic.prepare()
                }
            }
            if KeyboardSettings.shared.keySound {
                AudioServicesPlaySystemSound(wasAirborne ? 1156 : 1104)
            }
            syncHUDIfNeeded(immediate: true)
        } else if engine.running && !engine.gameOver {
            // Buffer rapid tap slightly before landing so consecutive jumps never feel dropped.
            jumpBufferRemaining = 0.11
        }
    }

    func handleTouchUp() {
        engine.releaseJump()
    }

    /// Steps physics in-place inside Canvas render pass (zero @State churn per frame).
    func advance(to timestamp: TimeInterval, trackWidth: CGFloat) {
        guard engine.running, !engine.gameOver else {
            lastTimestamp = timestamp
            return
        }
        guard let prev = lastTimestamp else {
            lastTimestamp = timestamp
            return
        }
        lastTimestamp = timestamp
        let dt = CGFloat(timestamp - prev)
        guard dt > 0.0005 else { return }

        if jumpBufferRemaining > 0 {
            jumpBufferRemaining = max(0, jumpBufferRemaining - min(dt, 0.05))
            if engine.playerY <= 1.5, engine.jump() {
                jumpBufferRemaining = 0
                if KeyboardSettings.shared.feedback {
                    jumpHaptic.impactOccurred(intensity: 0.72)
                    jumpHaptic.prepare()
                }
            }
        }

        let res = engine.step(dt: dt, trackWidth: max(260, trackWidth))
        if res.collected {
            if KeyboardSettings.shared.feedback {
                beadHaptic.impactOccurred(intensity: 0.8)
                beadHaptic.prepare()
            }
            if KeyboardSettings.shared.keySound {
                AudioServicesPlaySystemSound(1156)
            }
        }
        if res.shieldPicked || res.shieldBlocked {
            if KeyboardSettings.shared.feedback {
                shieldHaptic.impactOccurred(intensity: 0.9)
                shieldHaptic.prepare()
            }
            if KeyboardSettings.shared.keySound {
                AudioServicesPlaySystemSound(1155)
            }
        }
        if res.died {
            let newBest = MostoRunEngine.recordHighScore(engine.score)
            if KeyboardSettings.shared.feedback {
                crashHaptic.notificationOccurred(.warning)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.bestScore = newBest
                self.syncHUDIfNeeded(immediate: true)
            }
            return
        }
        syncHUDIfNeeded(immediate: false)
    }

    private func currentMilestoneText() -> String {
        if engine.reached300 { return "Moss 欢呼 · 光珠 +5" }
        if engine.reached200 { return "纸飞机出没 · 二段跳规避" }
        if engine.reached100 { return "Otto 已点亮桌面夜灯" }
        return ""
    }

    private func syncHUDIfNeeded(immediate: Bool) {
        let s = engine.score
        let r = engine.running
        let g = engine.gameOver
        let n = engine.isNight
        let c = engine.combo
        let mc = engine.maxCombo
        let sh = engine.hasShield
        let ms = currentMilestoneText()
        guard s != lastPublishedScore || r != lastPublishedRunning || g != lastPublishedGameOver
                || n != lastPublishedNight || c != lastPublishedCombo || mc != lastPublishedMaxCombo
                || sh != lastPublishedShield || ms != lastPublishedMilestone else {
            return
        }
        lastPublishedScore = s
        lastPublishedRunning = r
        lastPublishedGameOver = g
        lastPublishedNight = n
        lastPublishedCombo = c
        lastPublishedMaxCombo = mc
        lastPublishedShield = sh
        lastPublishedMilestone = ms
        let apply = { [weak self] in
            guard let self else { return }
            self.displayedScore = s
            self.isRunning = r
            self.isGameOver = g
            self.isNight = n
            self.displayedCombo = c
            self.maxCombo = mc
            self.hasShield = sh
            self.milestoneText = ms
        }
        if immediate && Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
}

/// Interactive Chrome-Dino-inspired offline desk runner starring Mosto, with natural handoff to 摸索台灯.
struct MostoRunEasterEggView: View {
    var onOpenMossling: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = MostoRunController()
    @State private var isPressing = false

    private var subtitleLine: String {
        if !controller.milestoneText.isEmpty && controller.isRunning {
            return controller.milestoneText
        }
        return controller.isNight
            ? "夜灯模式 · 二段跳躲纸飞机，连击接暖金光珠"
            : "短按小跳 · 长按高跳 · 空中再点可二段跳"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("桌边夜行 · Mosto Run")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(MossOttoStyle.inkPrimary)
                            if controller.hasShield {
                                Label("护盾", systemImage: "leaf.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(MossOttoStyle.moss)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(MossOttoStyle.moss.opacity(0.15)))
                            }
                            if controller.displayedCombo >= 2 && controller.isRunning {
                                Text("连击 x\(min(controller.displayedCombo, 3))")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(MossOttoStyle.violet)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(MossOttoStyle.violet.opacity(0.14)))
                            }
                        }
                        Text(subtitleLine)
                            .font(.caption)
                            .foregroundStyle(MossOttoStyle.inkSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(controller.displayedScore)")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(MossOttoStyle.violet)
                        Text("最高 \(controller.bestScore)")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(MossOttoStyle.inkSecondary)
                    }
                }

                TimelineView(.animation(paused: !controller.isRunning)) { timeline in
                    Canvas(opaque: true, rendersAsynchronously: false) { ctx, size in
                        controller.advance(to: timeline.date.timeIntervalSinceReferenceDate, trackWidth: size.width)
                        let eng = controller.engine
                        let night = eng.isNight
                        let groundY = size.height - 34

                        // Layer 1: Day/Night desk backdrop
                        let bgTop = night ? Color(uiColor: MossOttoStyle.hex(0x130F23)) : Color(uiColor: MossOttoStyle.hex(0xF6F2EA))
                        let bgBot = night ? Color(uiColor: MossOttoStyle.hex(0x231C3E)) : Color(uiColor: MossOttoStyle.hex(0xEAE3D4))
                        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                                 with: .linearGradient(Gradient(colors: [bgTop, bgBot]),
                                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

                        // Layer 2: Distant window & moon/stars/clouds (0.12x parallax)
                        let winRect = CGRect(x: 22, y: 18, width: 64, height: 50)
                        ctx.fill(Path(roundedRect: winRect, cornerRadius: 10),
                                 with: .color(night ? Color.white.opacity(0.05) : Color.white.opacity(0.45)))
                        ctx.stroke(Path(roundedRect: winRect, cornerRadius: 10),
                                   with: .color(night ? Color.white.opacity(0.10) : Color(uiColor: MossOttoStyle.hex(0xD8CFC0, 0.7))),
                                   lineWidth: 0.8)
                        if night {
                            ctx.fill(Path(ellipseIn: CGRect(x: 34, y: 27, width: 12, height: 12)),
                                     with: .color(Color(uiColor: MossOttoStyle.hex(0xFFE092, 0.85))))
                            ctx.fill(Path(ellipseIn: CGRect(x: 39, y: 25, width: 11, height: 11)),
                                     with: .color(Color(uiColor: MossOttoStyle.hex(0x18132B))))
                            for sIdx in 0..<6 {
                                let sx = 28 + CGFloat((sIdx * 47 + 17) % Int(max(80, size.width - 40)))
                                let sy = 20 + CGFloat((sIdx * 23) % 44)
                                let pulse = 0.35 + 0.45 * abs(sin(eng.distance * 0.02 + CGFloat(sIdx)))
                                ctx.fill(Path(ellipseIn: CGRect(x: sx, y: sy, width: 2.2, height: 2.2)),
                                         with: .color(Color.white.opacity(pulse)))
                            }
                        } else {
                            let drift = (eng.distance * 0.12).truncatingRemainder(dividingBy: 56)
                            ctx.fill(Path(ellipseIn: CGRect(x: 42 - drift * 0.15, y: 34, width: 22, height: 10)),
                                     with: .color(Color.white.opacity(0.75)))
                        }

                        // Layer 3: Midground desk book silhouette (0.35x parallax)
                        let midStride: CGFloat = 180
                        let midOffset = (eng.distance * 0.35).truncatingRemainder(dividingBy: midStride)
                        let silColor = night ? Color.white.opacity(0.05) : Color(uiColor: MossOttoStyle.hex(0x2B1961, 0.05))
                        var mx = -midOffset
                        while mx < size.width {
                            ctx.fill(Path(roundedRect: CGRect(x: mx + 12, y: groundY - 14, width: 42, height: 14), cornerRadius: 3), with: .color(silColor))
                            ctx.fill(Path(roundedRect: CGRect(x: mx + 22, y: groundY - 24, width: 26, height: 10), cornerRadius: 2.5), with: .color(silColor))
                            mx += midStride
                        }

                        // 100-pt milestone: Otto lights up the desk with warm golden beam & floating bokeh
                        if night || eng.reached100 {
                            var beam = Path()
                            beam.move(to: CGPoint(x: size.width - 42, y: 18))
                            beam.addLine(to: CGPoint(x: size.width - 180, y: groundY))
                            beam.addLine(to: CGPoint(x: size.width + 16, y: groundY))
                            beam.closeSubpath()
                            ctx.fill(beam, with: .linearGradient(
                                Gradient(colors: [Color(uiColor: MossOttoStyle.hex(0xFFC45A, night ? 0.25 : 0.14)), Color(uiColor: MossOttoStyle.hex(0xFFC45A, 0.02))]),
                                startPoint: CGPoint(x: size.width - 42, y: 18),
                                endPoint: CGPoint(x: size.width - 80, y: groundY)
                            ))
                            let bokehPulse = 0.09 + 0.05 * sin(eng.distance * 0.03)
                            ctx.fill(Path(ellipseIn: CGRect(x: size.width - 115, y: 48, width: 22, height: 22)),
                                     with: .color(Color(uiColor: MossOttoStyle.hex(0xFFC45A, bokehPulse))))
                            ctx.draw(controller.ottoLitImage, in: CGRect(x: size.width - 62, y: 10, width: 42, height: 42))
                        }

                        // 300-pt milestone: Moss cheers on from top-left desk corner
                        if eng.reached300 {
                            ctx.fill(Path(ellipseIn: CGRect(x: 10, y: 8, width: 38, height: 38)),
                                     with: .color(Color(uiColor: MossOttoStyle.hex(0x7EA86E, 0.18))))
                            ctx.draw(controller.mossHappyImage, in: CGRect(x: 13, y: 11, width: 32, height: 32))
                        }

                        // Layer 4: Foreground desk surface + scrolling grain ticks
                        let deskColor = night ? Color.white.opacity(0.22) : Color(uiColor: MossOttoStyle.hex(0x2B1961, 0.16))
                        ctx.fill(Path(CGRect(x: 0, y: groundY, width: size.width, height: 1.5)), with: .color(deskColor))
                        let tickStride: CGFloat = 44
                        let tickOffset = eng.distance.truncatingRemainder(dividingBy: tickStride)
                        let tickColor = night ? Color.white.opacity(0.11) : Color(uiColor: MossOttoStyle.hex(0x2B1961, 0.09))
                        var tx = -tickOffset
                        while tx < size.width {
                            ctx.fill(Path(CGRect(x: tx, y: groundY + 8, width: 14, height: 2)), with: .color(tickColor))
                            tx += tickStride
                        }

                        // Vector Obstacles
                        for o in eng.obstacles {
                            let rect = CGRect(x: o.x, y: groundY - o.y - o.height, width: o.width, height: o.height)
                            switch o.kind {
                            case 0:
                                // Two-tone sharpened wooden pencil: eraser, metal ferrule, yellow/green barrel, wood tip, graphite
                                let eraserH: CGFloat = 5
                                let ferruleH: CGFloat = 3
                                let tipH: CGFloat = 8
                                let bodyH = max(8, rect.height - eraserH - ferruleH - tipH)
                                let bodyColor = Color(uiColor: MossOttoStyle.hex(night ? 0xE0A844 : 0x55704A))
                                var tip = Path()
                                tip.move(to: CGPoint(x: rect.midX, y: rect.minY))
                                tip.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + tipH))
                                tip.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tipH))
                                tip.closeSubpath()
                                ctx.fill(tip, with: .color(Color(uiColor: MossOttoStyle.hex(0xE8C89B))))
                                var lead = Path()
                                lead.move(to: CGPoint(x: rect.midX, y: rect.minY))
                                lead.addLine(to: CGPoint(x: rect.midX + 3, y: rect.minY + 3.5))
                                lead.addLine(to: CGPoint(x: rect.midX - 3, y: rect.minY + 3.5))
                                lead.closeSubpath()
                                ctx.fill(lead, with: .color(Color(uiColor: MossOttoStyle.hex(0x2B253A))))
                                ctx.fill(Path(CGRect(x: rect.minX, y: rect.minY + tipH, width: rect.width, height: bodyH)),
                                         with: .color(bodyColor))
                                ctx.fill(Path(CGRect(x: rect.minX + 3, y: rect.minY + tipH, width: 3, height: bodyH)),
                                         with: .color(Color.white.opacity(0.22)))
                                ctx.fill(Path(CGRect(x: rect.minX, y: rect.maxY - eraserH - ferruleH, width: rect.width, height: ferruleH)),
                                         with: .color(Color(uiColor: MossOttoStyle.hex(0xC8CCD6))))
                                ctx.fill(Path(roundedRect: CGRect(x: rect.minX, y: rect.maxY - eraserH, width: rect.width, height: eraserH), cornerRadius: 2),
                                         with: .color(Color(uiColor: MossOttoStyle.hex(0xE78E9B))))
                            case 1:
                                // Chamfered wooden toy block
                                let blockColor = Color(uiColor: MossOttoStyle.hex(night ? 0x8F7AD8 : 0x2D4A8C))
                                ctx.fill(Path(roundedRect: rect, cornerRadius: 4.5), with: .color(blockColor))
                                ctx.stroke(Path(roundedRect: rect.insetBy(dx: 4, dy: 4), cornerRadius: 2),
                                           with: .color(Color.white.opacity(0.26)), lineWidth: 1.0)
                            case 2:
                                // Closed hardcover picture book
                                let spineColor = Color(uiColor: MossOttoStyle.hex(night ? 0xD69A34 : 0x633EBF))
                                ctx.fill(Path(roundedRect: rect, cornerRadius: 3.5), with: .color(spineColor))
                                ctx.fill(Path(roundedRect: CGRect(x: rect.minX + 4, y: rect.minY + 4, width: rect.width - 7, height: rect.height - 8), cornerRadius: 2),
                                         with: .color(Color(uiColor: MossOttoStyle.hex(0xFBF8F2))))
                                ctx.fill(Path(CGRect(x: rect.maxX - 8, y: rect.maxY - 5, width: 3, height: 7)),
                                         with: .color(Color(uiColor: MossOttoStyle.hex(0xE06D75))))
                            default:
                                // 200+ pts folded origami paper airplane gliding left
                                var trail = Path()
                                trail.move(to: CGPoint(x: rect.maxX + 2, y: rect.midY))
                                trail.addLine(to: CGPoint(x: rect.maxX + 18, y: rect.midY - 2))
                                ctx.stroke(trail, with: .color(Color.white.opacity(night ? 0.35 : 0.45)),
                                           style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                                var wingTop = Path()
                                wingTop.move(to: CGPoint(x: rect.minX, y: rect.midY))
                                wingTop.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                                wingTop.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.midY + 2))
                                wingTop.closeSubpath()
                                ctx.fill(wingTop, with: .color(Color(uiColor: MossOttoStyle.hex(night ? 0xF4F1FA : 0xFFFFFF))))
                                var wingBot = Path()
                                wingBot.move(to: CGPoint(x: rect.minX, y: rect.midY))
                                wingBot.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.midY + 2))
                                wingBot.addLine(to: CGPoint(x: rect.maxX - 6, y: rect.maxY))
                                wingBot.closeSubpath()
                                ctx.fill(wingBot, with: .color(Color(uiColor: MossOttoStyle.hex(night ? 0xA78BFA : 0xD6CEEE))))
                            }
                        }

                        // Otto's warm gold lamp beads with gentle hover bob
                        let beadColor = Color(uiColor: MossOttoStyle.hex(0xFFC45A))
                        for b in eng.beads where !b.collected {
                            let bob = sin(eng.distance * 0.05 + CGFloat(b.id)) * 2.5
                            let cy = groundY - b.y + bob
                            ctx.fill(Path(ellipseIn: CGRect(x: b.x - 9, y: cy - 9, width: 18, height: 18)),
                                     with: .color(beadColor.opacity(0.24)))
                            ctx.fill(Path(ellipseIn: CGRect(x: b.x - 5.5, y: cy - 5.5, width: 11, height: 11)),
                                     with: .color(beadColor))
                            ctx.fill(Path(ellipseIn: CGRect(x: b.x - 2.2, y: cy - 2.6, width: 3.5, height: 3.5)),
                                     with: .color(Color.white.opacity(0.75)))
                        }

                        // Moss mint shield pickups
                        let mintColor = Color(uiColor: MossOttoStyle.hex(night ? 0x7EA86E : 0x55704A))
                        for sh in eng.shieldPickups where !sh.collected {
                            let bob = cos(eng.distance * 0.04 + CGFloat(sh.id)) * 2.5
                            let cy = groundY - sh.y + bob
                            ctx.fill(Path(ellipseIn: CGRect(x: sh.x - 11, y: cy - 11, width: 22, height: 22)),
                                     with: .color(mintColor.opacity(0.20)))
                            ctx.stroke(Path(ellipseIn: CGRect(x: sh.x - 9, y: cy - 9, width: 18, height: 18)),
                                       with: .color(mintColor), lineWidth: 1.8)
                            ctx.fill(Path(ellipseIn: CGRect(x: sh.x - 4, y: cy - 4, width: 8, height: 8)),
                                     with: .color(mintColor))
                        }

                        // Particles (double jump violet stars, gold sparkles, mint shatter)
                        for p in eng.particles {
                            let alpha = max(0, min(1, p.life / p.maxLife))
                            let col: Color = p.kind == 0
                                ? Color(uiColor: MossOttoStyle.hex(0xA78BFA)).opacity(alpha)
                                : (p.kind == 1
                                   ? Color(uiColor: MossOttoStyle.hex(0xFFC45A)).opacity(alpha)
                                   : mintColor.opacity(alpha))
                            let r = CGRect(x: p.x - p.size * 0.5, y: groundY - p.y - p.size * 0.5, width: p.size, height: p.size)
                            ctx.fill(Path(ellipseIn: r), with: .color(col))
                        }

                        // Ground contact shadow + squash-and-stretch Mosto sprite + active mint shield bubble
                        let shadowScale = max(0.35, 1.0 - eng.playerY / 130.0)
                        let sw = 26 * shadowScale
                        ctx.fill(Path(ellipseIn: CGRect(x: 67 - sw * 0.5, y: groundY - 2, width: sw, height: 4)),
                                 with: .color(night ? Color.black.opacity(0.32) : Color.black.opacity(0.12)))

                        let stretchY = min(0.10, max(0, eng.velocityY) / 5000.0)
                        let sxScale = 1.0 + eng.landingSquash * 0.16 - stretchY * 0.65
                        let syScale = 1.0 - eng.landingSquash * 0.14 + stretchY
                        let pw = 38 * sxScale
                        let ph = 38 * syScale
                        let pRect = CGRect(x: 67 - pw * 0.5, y: groundY - eng.playerY - ph, width: pw, height: ph)

                        if eng.hasShield {
                            let bubbleRect = pRect.insetBy(dx: -5, dy: -5)
                            ctx.fill(Path(ellipseIn: bubbleRect), with: .color(mintColor.opacity(0.16)))
                            ctx.stroke(Path(ellipseIn: bubbleRect), with: .color(mintColor.opacity(0.85)), lineWidth: 1.6)
                        } else if eng.shieldFlash > 0 {
                            let expand = (1.0 - eng.shieldFlash) * 16
                            let flashRect = pRect.insetBy(dx: -6 - expand, dy: -6 - expand)
                            ctx.stroke(Path(ellipseIn: flashRect), with: .color(mintColor.opacity(eng.shieldFlash)), lineWidth: 2.0)
                        }

                        ctx.draw(night ? controller.mostoNightImage : controller.mostoDayImage, in: pRect)

                        // Floating score / shield popups
                        for pop in eng.popups {
                            let alpha = max(0, 1.0 - pop.age / 0.85)
                            let col: Color = pop.kind == 1
                                ? mintColor.opacity(alpha)
                                : (pop.kind == 2
                                   ? Color(uiColor: MossOttoStyle.hex(night ? 0xA78BFA : 0x633EBF)).opacity(alpha)
                                   : Color(uiColor: MossOttoStyle.hex(night ? 0xFFC45A : 0xB87B14)).opacity(alpha))
                            ctx.draw(
                                Text(pop.text).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(col),
                                at: CGPoint(x: pop.x, y: groundY - pop.y)
                            )
                        }
                    }
                    .frame(height: 196)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(MossOttoStyle.hairline, lineWidth: 0.6)
                    )
                    .overlay {
                        if !controller.isRunning {
                            VStack(spacing: 8) {
                                Text(controller.isGameOver
                                     ? (controller.displayedScore >= 200 ? "纸飞机也没能拦住你" : (controller.displayedScore >= 100 ? "Otto 为你点亮了夜灯" : "书桌上的铅笔有点高"))
                                     : "轻点跳跃 · 空中再点可二段跳")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(controller.isNight ? Color.white : MossOttoStyle.inkPrimary)
                                if controller.isGameOver {
                                    Text("本局 \(controller.displayedScore) 分 · 最高 \(controller.bestScore) · 最高连击 x\(max(1, min(controller.maxCombo, 3)))")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(controller.isNight ? Color.white.opacity(0.76) : MossOttoStyle.inkSecondary)
                                    Text("轻点再来一局")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(MossOttoStyle.violet)
                                } else {
                                    Text("接住光珠叠加连击 · 拾取 Moss 薄荷护盾可抵挡一次碰撞")
                                        .font(.caption)
                                        .foregroundStyle(controller.isNight ? Color.white.opacity(0.72) : MossOttoStyle.inkSecondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                guard !isPressing else { return }
                                isPressing = true
                                controller.handleTouchDown()
                            }
                            .onEnded { _ in
                                isPressing = false
                                controller.handleTouchUp()
                            }
                    )
                }

                // Gentle, non-pushy character handoff to 摸索台灯 using official adaptive App Icon
                Button(action: onOpenMossling) {
                    HStack(spacing: 12) {
                        Image("MosslingAppIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .shadow(color: Color.black.opacity(0.08), radius: 3, y: 1.5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Moss 和 Otto 住在《摸索台灯》里")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MossOttoStyle.inkPrimary)
                            Text("0–3 岁亲子共玩与床头夜灯 · 点这里去官网看看它们的故事")
                                .font(.caption)
                                .foregroundStyle(MossOttoStyle.inkSecondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MossOttoStyle.inkSecondary)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MossOttoStyle.surface))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(MossOttoStyle.hairline, lineWidth: 0.6))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(MossOttoStyle.canvas.ignoresSafeArea())
            .navigationTitle("离线小彩蛋")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .onAppear { controller.prepareHaptics() }
    }
}
