import SwiftUI

/// System keyboard activation status & live verification screen styled with OTTOSSOM ceramic surfaces.
struct EnableScreen: View {
    @Environment(\.scenePhase) private var phase
    @State private var added = KeyboardStatus.isAdded()
    @State private var text = ""
    @FocusState private var typing: Bool

    var body: some View {
        ScrollView {
            EnableContent(added: added, text: $text, typing: $typing)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
        .background(MossOttoStyle.canvas.ignoresSafeArea().onTapGesture { typing = false })
        .navigationTitle("启用系统键盘")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("收起") { typing = false }.fontWeight(.semibold)
            }
        }
        .onChange(of: phase) { p in if p == .active { added = KeyboardStatus.isAdded() } }
    }
}

enum EnablePalette {
    static func violet(dark: Bool) -> UIColor {
        dark ? MossOttoStyle.hex(0xA78BFA) : MossOttoStyle.hex(0x633EBF)
    }

    static func moss(dark: Bool) -> UIColor {
        dark ? MossOttoStyle.hex(0x7EA86E) : MossOttoStyle.hex(0x55704A)
    }

    static func amber(dark: Bool) -> UIColor {
        dark ? MossOttoStyle.hex(0xFFC45A) : MossOttoStyle.hex(0xD69A34)
    }
}

/// Shared non-scrolling content tree so live screen and CI snapshot renderer share one layout.
struct EnableContent: View {
    let added: Bool
    @Binding var text: String
    var typing: FocusState<Bool>.Binding

    static func isVerificationPassed(_ text: String) -> Bool {
        text.contains("你好")
    }

    private var verified: Bool {
        Self.isVerificationPassed(text)
    }

    var body: some View {
        VStack(spacing: 14) {
            EnableStatusHero(added: added, verified: verified)

            VStack(spacing: 10) {
                EnableStepRow(step: 1, title: "打开设置", detail: "设置 › 通用 › 键盘 › 键盘", art: .settings)
                EnableStepRow(step: 2, title: "添加 Mosto", detail: "添加新键盘 › 选中 Mosto键盘", art: .add)
                EnableStepRow(step: 3, title: "地球键切换", detail: "长按地球键切换 · 无需完全访问", art: .globe)
            }

            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) {
                    HStack(spacing: 8) {
                        Text(added ? "前往系统设置管理键盘" : "打开系统设置去添加")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(MossOttoStyle.onViolet)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(MossOttoStyle.violet))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("真机键盘验证区")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MossOttoStyle.inkSecondary)
                    Spacer()
                    if verified {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("验通成功")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(MossOttoStyle.moss)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(MossOttoStyle.moss.opacity(0.14)))
                    } else if typing.wrappedValue {
                        Button("收起键盘") { typing.wrappedValue = false }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MossOttoStyle.violet)
                    } else {
                        Text(added ? "目标：你好" : "添加后可验证")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(added ? MossOttoStyle.violet : MossOttoStyle.inkSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(added ? MossOttoStyle.violet.opacity(0.12) : MossOttoStyle.surfaceMuted))
                    }
                }
                if SnapshotRenderer.requested {
                    Text("全拼 nihao 或小鹤 nihc → 你好")
                        .font(.subheadline)
                        .foregroundStyle(MossOttoStyle.inkSecondary.opacity(0.65))
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                } else {
                    TextField("全拼 nihao 或小鹤 nihc → 你好", text: $text, axis: .vertical)
                        .lineLimit(2...4)
                        .focused(typing)
                        .font(.subheadline)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(MossOttoStyle.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(verified ? MossOttoStyle.moss.opacity(0.65) : MossOttoStyle.hairline, lineWidth: verified ? 1.1 : 0.7)
            )
            .onChange(of: verified) { ok in
                if ok { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            }
        }
    }
}

enum KeyboardStatus {
    /// Reads global defaults read-only to see if the keyboard extension has been added in iOS Settings.
    static func isAdded() -> Bool {
        guard let list = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String] else { return false }
        let ext = Bundle.main.builtInPlugInsURL.flatMap { u in
            (try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil))?.compactMap { Bundle(url: $0)?.bundleIdentifier }
        } ?? []
        return list.contains { ext.contains($0) }
    }
}

private struct EnableStatusHero: View {
    let added: Bool
    let verified: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let violet = Color(uiColor: EnablePalette.violet(dark: dark))
        let green = Color(uiColor: EnablePalette.moss(dark: dark))
        let stage = verified ? 3 : (added ? 2 : 0)

        HStack(spacing: 12) {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let accent = (added || verified) ? green : violet
                let bg = CGRect(x: w * 0.08, y: h * 0.08, width: w * 0.84, height: h * 0.84)
                ctx.fill(Path(roundedRect: bg, cornerRadius: w * 0.26), with: .color(accent.opacity(dark ? 0.20 : 0.14)))
                ctx.stroke(Path(roundedRect: bg, cornerRadius: w * 0.26), with: .color(accent), lineWidth: 1.5)
                if added || verified {
                    var check = Path()
                    check.move(to: CGPoint(x: w * 0.30, y: h * 0.52))
                    check.addLine(to: CGPoint(x: w * 0.45, y: h * 0.67))
                    check.addLine(to: CGPoint(x: w * 0.72, y: h * 0.36))
                    ctx.stroke(check, with: .color(green), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                } else {
                    let k1 = CGRect(x: w * 0.24, y: h * 0.34, width: w * 0.22, height: h * 0.18)
                    let k2 = CGRect(x: w * 0.54, y: h * 0.34, width: w * 0.22, height: h * 0.18)
                    let sp = CGRect(x: w * 0.28, y: h * 0.60, width: w * 0.44, height: h * 0.14)
                    for r in [k1, k2, sp] {
                        ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(violet.opacity(dark ? 0.45 : 0.32)))
                    }
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(verified ? "Mosto键盘已验通" : (added ? "Mosto键盘已就绪" : "三步启用 Mosto键盘"))
                        .font(.headline)
                        .foregroundStyle(MossOttoStyle.inkPrimary)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { idx in
                            let lit = idx < stage
                            Capsule()
                                .fill(lit ? (verified ? MossOttoStyle.moss : MossOttoStyle.violet) : MossOttoStyle.inkSecondary.opacity(0.24))
                                .frame(width: 14, height: 4.5)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("启用进度")
                    .accessibilityValue(verified ? "已验通" : (added ? "已添加待验证" : "待添加"))
                }
                HStack(spacing: 6) {
                    statusChip(icon: "lock.fill", text: "纯离线")
                    statusChip(icon: added ? "globe" : "gearshape", text: added ? "长按地球键切换" : "按住表情键调控制台")
                }
            }
            Spacer(minLength: 0)
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
    }

    private func statusChip(icon: String, text: String) -> some View {
        HStack(spacing: 3.5) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(MossOttoStyle.violet)
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(MossOttoStyle.inkSecondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(MossOttoStyle.surfaceMuted))
    }
}

private enum StepArtKind { case settings, add, globe }

private struct EnableStepRow: View {
    let step: Int
    let title: String
    let detail: String
    let art: StepArtKind
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let violet = Color(uiColor: EnablePalette.violet(dark: dark))
        let gold = Color(uiColor: EnablePalette.amber(dark: dark))
        HStack(spacing: 12) {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let box = CGRect(x: w * 0.08, y: h * 0.08, width: w * 0.84, height: h * 0.84)
                ctx.fill(Path(roundedRect: box, cornerRadius: w * 0.24), with: .color(violet.opacity(dark ? 0.18 : 0.10)))
                switch art {
                case .settings:
                    let track = CGRect(x: w * 0.22, y: h * 0.34, width: w * 0.56, height: h * 0.32)
                    ctx.fill(Path(roundedRect: track, cornerRadius: h * 0.16), with: .color(violet.opacity(0.28)))
                    let knob = CGRect(x: w * 0.50, y: h * 0.38, width: h * 0.24, height: h * 0.24)
                    ctx.fill(Path(ellipseIn: knob), with: .color(violet))
                case .add:
                    var plus = Path()
                    plus.move(to: CGPoint(x: w * 0.50, y: h * 0.28)); plus.addLine(to: CGPoint(x: w * 0.50, y: h * 0.72))
                    plus.move(to: CGPoint(x: w * 0.28, y: h * 0.50)); plus.addLine(to: CGPoint(x: w * 0.72, y: h * 0.50))
                    ctx.stroke(plus, with: .color(violet), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                case .globe:
                    let circle = CGRect(x: w * 0.24, y: h * 0.24, width: w * 0.52, height: w * 0.52)
                    ctx.stroke(Path(ellipseIn: circle), with: .color(gold), lineWidth: 1.6)
                    let meridian = CGRect(x: w * 0.38, y: h * 0.24, width: w * 0.24, height: h * 0.52)
                    ctx.stroke(Path(ellipseIn: meridian), with: .color(gold), lineWidth: 1.2)
                    var eq = Path()
                    eq.move(to: CGPoint(x: w * 0.25, y: h * 0.50)); eq.addLine(to: CGPoint(x: w * 0.75, y: h * 0.50))
                    ctx.stroke(eq, with: .color(gold), lineWidth: 1.2)
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(step). \(title)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MossOttoStyle.inkPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(MossOttoStyle.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(MossOttoStyle.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(MossOttoStyle.hairline, lineWidth: 0.7)
        )
    }
}
