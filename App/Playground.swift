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


// MARK: - R96: Offline Easter Egg Game — 桌边夜行 (Mosto Run)

/// Pure-Swift offline endless runner state machine (zero network, zero SpriteKit bloat, 100% unit-testable).
struct MostoRunEngine {
    struct Obstacle: Identifiable {
        let id: Int
        var x: CGFloat
        let width: CGFloat
        let height: CGFloat
        let kind: Int // 0 = pencil, 1 = wooden block
    }
    struct Bead: Identifiable {
        let id: Int
        var x: CGFloat
        var y: CGFloat
        var collected: Bool = false
    }

    static let highScoreKey = "mosto.run.highscore.v1"

    var playerY: CGFloat = 0          // height above desk ground (0 = grounded)
    var velocityY: CGFloat = 0
    var speed: CGFloat = 230          // pt / sec
    var distance: CGFloat = 0
    var bonusScore: Int = 0
    var running: Bool = false
    var gameOver: Bool = false
    var obstacles: [Obstacle] = []
    var beads: [Bead] = []
    private var nextID: Int = 1
    private var spawnCooldown: CGFloat = 0.9

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
        obstacles = []
        beads = []
        spawnCooldown = 0.85
    }

    @discardableResult
    mutating func jump(strong: Bool = false) -> Bool {
        if gameOver {
            start()
            return true
        }
        if !running {
            start()
        }
        guard playerY <= 1.5 else { return false }
        velocityY = strong ? 560 : 490
        return true
    }

    /// Advances physics by `dt` seconds. Returns `(collectedBead, died)`.
    @discardableResult
    mutating func step(dt rawDt: CGFloat, trackWidth: CGFloat = 360) -> (collected: Bool, died: Bool) {
        guard running, !gameOver else { return (false, false) }
        let dt = min(max(rawDt, 0.001), 0.05)
        speed = min(430, 230 + CGFloat(score) * 0.45)
        distance += speed * dt

        // Gravity & ground clamp
        let gravity: CGFloat = 1480
        velocityY -= gravity * dt
        playerY += velocityY * dt
        if playerY <= 0 {
            playerY = 0
            velocityY = 0
        }

        // Spawn obstacles & lamp beads
        spawnCooldown -= dt
        if spawnCooldown <= 0 {
            let kind = nextID % 2
            let w: CGFloat = kind == 0 ? 16 : 26
            let h: CGFloat = kind == 0 ? 34 : 26
            obstacles.append(Obstacle(id: nextID, x: trackWidth + 24, width: w, height: h, kind: kind))
            if nextID % 2 == 1 {
                beads.append(Bead(id: nextID + 10000, x: trackWidth + 24 + w * 0.5, y: h + 38))
            }
            nextID += 1
            let pace = max(0.72, 1.38 - (speed - 230) / 420)
            spawnCooldown = pace + CGFloat((nextID * 37) % 10) * 0.045
        }

        // Move & prune
        let dx = speed * dt
        for i in obstacles.indices { obstacles[i].x -= dx }
        obstacles.removeAll { $0.x + $0.width < -20 }
        for i in beads.indices { beads[i].x -= dx }
        beads.removeAll { $0.x < -20 || $0.collected }

        // Player hitbox centered at x = 66, size 30x30 (forgiving inset)
        let pRect = CGRect(x: 52, y: playerY + 2, width: 26, height: 28)
        var gotBead = false
        for i in beads.indices where !beads[i].collected {
            let bRect = CGRect(x: beads[i].x - 10, y: beads[i].y - 10, width: 20, height: 20)
            if pRect.intersects(bRect) {
                beads[i].collected = true
                bonusScore += 10
                gotBead = true
            }
        }
        for o in obstacles {
            let oRect = CGRect(x: o.x + 3, y: 0, width: max(8, o.width - 6), height: max(12, o.height - 5))
            if pRect.intersects(oRect) {
                gameOver = true
                running = false
                return (gotBead, true)
            }
        }
        return (gotBead, false)
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

/// Interactive Chrome-Dino-inspired offline desk runner starring Mosto, with natural handoff to 摸索台灯.
struct MostoRunEasterEggView: View {
    var onOpenMossling: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var engine = MostoRunEngine()
    @State private var bestScore = MostoRunEngine.loadHighScore()
    @State private var lastTick: Date? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("桌边夜行 · Mosto Run")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(MossOttoStyle.inkPrimary)
                        Text(engine.isNight ? "夜灯模式 · 跳过铅笔与积木，接住暖金光珠" : "日光书桌 · 轻点屏幕跳跃，满 100 分切换夜灯")
                            .font(.caption)
                            .foregroundStyle(MossOttoStyle.inkSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(engine.score)")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(MossOttoStyle.violet)
                        Text("最高 \(bestScore)")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(MossOttoStyle.inkSecondary)
                    }
                }

                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !engine.running)) { timeline in
                    Canvas { ctx, size in
                        let groundY = size.height - 34
                        let bgTop = engine.isNight ? Color(uiColor: MossOttoStyle.hex(0x161229)) : Color(uiColor: MossOttoStyle.hex(0xF6F2EA))
                        let bgBot = engine.isNight ? Color(uiColor: MossOttoStyle.hex(0x231C3E)) : Color(uiColor: MossOttoStyle.hex(0xEBE5D8))
                        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                                 with: .linearGradient(Gradient(colors: [bgTop, bgBot]),
                                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

                        // Desk surface line
                        let deskColor = engine.isNight ? Color.white.opacity(0.18) : Color(uiColor: MossOttoStyle.hex(0x2B1961, 0.16))
                        ctx.fill(Path(CGRect(x: 0, y: groundY, width: size.width, height: 1.5)), with: .color(deskColor))

                        // 100-pt milestone: Otto lights up the desk with a warm golden beam in Night mode
                        if engine.isNight {
                            var beam = Path()
                            beam.move(to: CGPoint(x: size.width - 42, y: 18))
                            beam.addLine(to: CGPoint(x: size.width - 170, y: groundY))
                            beam.addLine(to: CGPoint(x: size.width + 16, y: groundY))
                            beam.closeSubpath()
                            ctx.fill(beam, with: .linearGradient(
                                Gradient(colors: [Color(uiColor: MossOttoStyle.hex(0xFFC45A, 0.24)), Color(uiColor: MossOttoStyle.hex(0xFFC45A, 0.03))]),
                                startPoint: CGPoint(x: size.width - 42, y: 18),
                                endPoint: CGPoint(x: size.width - 80, y: groundY)
                            ))
                            let ottoSprite = mostoImage("OttoLit")
                            ctx.draw(Image(uiImage: ottoSprite), in: CGRect(x: size.width - 62, y: 10, width: 42, height: 42))
                        }

                        // Obstacles (pencils & blocks)
                        for o in engine.obstacles {
                            let rect = CGRect(x: o.x, y: groundY - o.height, width: o.width, height: o.height)
                            let fill = o.kind == 0
                                ? Color(uiColor: MossOttoStyle.hex(engine.isNight ? 0xD69A34 : 0x55704A))
                                : Color(uiColor: MossOttoStyle.hex(engine.isNight ? 0x8F7AD8 : 0x2D4A8C))
                            ctx.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(fill))
                        }

                        // Otto's warm gold lamp beads
                        for b in engine.beads where !b.collected {
                            let r = CGRect(x: b.x - 6, y: groundY - b.y - 6, width: 12, height: 12)
                            ctx.fill(Path(ellipseIn: r), with: .color(Color(uiColor: MossOttoStyle.hex(0xFFC45A))))
                        }

                        // Mosto player sprite
                        let sprite = mostoImage(engine.isNight ? "MostoNight" : "Mosto")
                        let pRect = CGRect(x: 48, y: groundY - engine.playerY - 38, width: 38, height: 38)
                        ctx.draw(Image(uiImage: sprite), in: pRect)
                    }
                    .frame(height: 196)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(MossOttoStyle.hairline, lineWidth: 0.6)
                    )
                    .overlay {
                        if !engine.running {
                            VStack(spacing: 8) {
                                Text(engine.gameOver ? (engine.score >= 100 ? "Otto 为你点亮了夜灯" : (engine.score >= 50 ? "快追上 Otto 的台灯光了" : "书桌上的铅笔有点高")) : "轻点屏幕，开始夜行")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(engine.isNight ? Color.white : MossOttoStyle.inkPrimary)
                                Text(engine.gameOver ? "本次得分 \(engine.score) · 轻点再来一局" : "纯离线彩蛋 · 满 100 分召唤 Otto 点灯")
                                    .font(.caption)
                                    .foregroundStyle(engine.isNight ? Color.white.opacity(0.72) : MossOttoStyle.inkSecondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if engine.jump() {
                            if KeyboardSettings.shared.feedback {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.72)
                            }
                            if KeyboardSettings.shared.keySound {
                                AudioServicesPlaySystemSound(1104)
                            }
                        }
                    }
                    .onChange(of: timeline.date) { now in
                        if let prev = lastTick {
                            let res = engine.step(dt: CGFloat(now.timeIntervalSince(prev)))
                            if res.collected {
                                if KeyboardSettings.shared.feedback {
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
                                }
                                if KeyboardSettings.shared.keySound {
                                    AudioServicesPlaySystemSound(1156)
                                }
                            }
                            if res.died {
                                bestScore = MostoRunEngine.recordHighScore(engine.score)
                                if KeyboardSettings.shared.feedback {
                                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                }
                            }
                        }
                        lastTick = now
                    }
                }

                // Gentle, non-pushy character handoff to 摸索台灯
                Button(action: onOpenMossling) {
                    HStack(spacing: 12) {
                        Image(uiImage: mostoImage("OttoLit"))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Moss 和 Otto 住在《摸索台灯》里")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MossOttoStyle.inkPrimary)
                            Text("0–3 岁亲子共玩与床头夜灯 · 点这里在 App Store 看一眼")
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
        .onAppear { lastTick = Date() }
    }
}
