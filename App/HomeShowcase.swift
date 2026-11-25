import SwiftUI
import UIKit

/// Full-resolution 3D studio vinyl sprites from the app asset catalog (Moss, Otto, Mosto).
func mostoImage(_ name: String) -> UIImage { UIImage(named: name) ?? UIImage() }

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
    /// WCAG AA+ ink on `MossOttoStyle.violet` (Day: #FFFFFF on #633EBF = 7.56:1; Night: #1A1429 on #A78BFA = 6.59:1).
    static let onViolet = dynamic(hex(0xFFFFFF), hex(0x1A1429))
    static let lampAmber = dynamic(hex(0xD69A34), hex(0xFFC45A))
    static let correctionAccent = dynamic(hex(0x633EBF), hex(0xFFC45A))
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
        if plain { return Color.white.opacity(night ? 0.08 : 0.45) }
        return night ? Color.white.opacity(0.08) : Color(uiColor: hex(0xDDD5C8))
    }

    static func keyShadow(night: Bool) -> Color {
        night ? Color.black.opacity(0.55) : Color(uiColor: hex(0xCFC7B8)).opacity(0.52)
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
    let isNight: Bool
    var dimFactor: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    private var darkLook: Bool { isNight || scheme == .dark }

    private var dimmerOpacity: Double {
        Double(max(0.45, 1.0 - dimFactor * 0.30))
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
                .blur(radius: 14)
                .opacity(dimmerOpacity)
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
                .opacity(dimmerOpacity)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: plinthColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 24)
            }
        }
    }

    private var plinthColors: [Color] {
        if isNight {
            return [.clear, Color(uiColor: MossOttoStyle.hex(0x0E0B1A)).opacity(0.65)]
        }
        if darkLook {
            return [.clear, Color(uiColor: MossOttoStyle.hex(0x181427)).opacity(0.45)]
        }
        return [.clear, Color(uiColor: MossOttoStyle.hex(0xEFE8DA)).opacity(0.65)]
    }

    private var stageBg: Color {
        if isNight {
            return Color(uiColor: MossOttoStyle.hex(0x181427))
        }
        return scheme == .dark ? Color(uiColor: MossOttoStyle.hex(0x231E33)) : Color(uiColor: MossOttoStyle.hex(0xFFFDF8))
    }

    private var coneColors: [Color] {
        if isNight {
            let c = Color(uiColor: MossOttoStyle.hex(0xFFC45A))
            return [c.opacity(0.26), c.opacity(0.07), .clear]
        }
        let c = Color(uiColor: MossOttoStyle.hex(0xF7CD7A))
        return [c.opacity(darkLook ? 0.20 : 0.22), c.opacity(0.03), .clear]
    }

    private var haloColors: [Color] {
        if isNight {
            return [Color(uiColor: MossOttoStyle.hex(0xFFC45A)).opacity(0.62), .clear]
        }
        return [Color(uiColor: MossOttoStyle.hex(0xFFD678)).opacity(0.50), .clear]
    }
}

/// Physical spring-loaded OTTOSSOM desk-lamp pull-cord switch mounted at the top-right stage edge.
struct LampPullCordSwitch: View {
    static let pullThreshold: CGFloat = 22

    let isNight: Bool
    let darkStage: Bool
    @Binding var pullFraction: CGFloat
    var onTrigger: () -> Void

    @State private var pullOffset: CGFloat = 0
    @State private var armed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cordColor: Color {
        if isNight { return Color(uiColor: MossOttoStyle.hex(0xFFC45A)).opacity(0.55) }
        return darkStage ? Color.white.opacity(0.36) : MossOttoStyle.inkSecondary.opacity(0.42)
    }

    private var beadColor: Color {
        if isNight { return MossOttoStyle.lampAmber }
        return MossOttoStyle.violet
    }

    private var collarColor: Color {
        isNight ? Color(uiColor: MossOttoStyle.hex(0xFFE4A8)) : MossOttoStyle.inkSecondary.opacity(0.65)
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(cordColor.opacity(0.65))
                .frame(width: 10, height: 3.5)

            Rectangle()
                .fill(cordColor)
                .frame(width: 1.5, height: 42 + pullOffset)

            Capsule()
                .fill(collarColor)
                .frame(width: 7, height: 3)

            ZStack {
                Capsule(style: .continuous)
                    .fill(beadColor)
                    .frame(width: 13, height: 19)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.black.opacity(darkStage ? 0.28 : 0.12), lineWidth: 0.6)
                    )
                    .shadow(color: (isNight ? MossOttoStyle.lampAmber : Color.black).opacity(isNight ? 0.38 : 0.16), radius: armed ? 5 : 2, y: 1.5)

                Circle()
                    .fill(Color.white.opacity(0.42))
                    .frame(width: 3.5, height: 3.5)
                    .offset(x: -2.2, y: -4.2)
            }
            .scaleEffect(armed ? 1.08 : 1.0)
        }
        .frame(width: 44, height: 96, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.08)) {
                    pullOffset = 10
                    pullFraction = 0.45
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.56)) {
                        pullOffset = 0
                        pullFraction = 0
                    }
                }
            }
            onTrigger()
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    guard value.translation.height > 0,
                          abs(value.translation.height) >= abs(value.translation.width) * 0.8 else { return }
                    let travel = min(32, value.translation.height * 0.68)
                    pullOffset = travel
                    pullFraction = min(1, travel / Self.pullThreshold)
                    if !armed && travel >= Self.pullThreshold {
                        armed = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
                    } else if armed && travel < Self.pullThreshold - 4 {
                        armed = false
                    }
                }
                .onEnded { _ in
                    let shouldFire = armed
                    armed = false
                    withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.56)) {
                        pullOffset = 0
                        pullFraction = 0
                    }
                    if shouldFire { onTrigger() }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("台灯拉绳开关")
        .accessibilityHint("下拉或轻点切换日光与夜灯")
        .accessibilityAddTraits(.isButton)
    }
}

/// R50 Single-Layer Matte Monolith Keycap for Companion App specimens, Switch Tester & Xiaohe charts.
struct MonolithKeycapView: View {
    let label: String
    var symbol: String? = nil
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
                        .strokeBorder(MossOttoStyle.keyBorder(plain: plain, night: isNight), lineWidth: 0.5)
                )
                .shadow(color: pressed ? .clear : MossOttoStyle.keyShadow(night: isNight), radius: 0, x: 0, y: 1.2)

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
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isNight ? Color.white : MossOttoStyle.inkPrimary)
                    } else {
                        Text(label)
                            .font(.system(size: 17, weight: .medium, design: plain ? .default : .rounded))
                            .foregroundStyle(isNight ? Color.white : MossOttoStyle.inkPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                    }
                    if let secondary {
                        Text(secondary)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(MossOttoStyle.inkSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
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
                        .strokeBorder(MossOttoStyle.hairline, lineWidth: 0.5)
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
