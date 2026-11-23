import SwiftUI

/// System keyboard activation status & live verification screen styled with OTTOSSOM ceramic surfaces.
struct EnableScreen: View {
    @Environment(\.scenePhase) private var phase
    @State private var added = KeyboardStatus.isAdded()
    @State private var text = ""
    @FocusState private var typing: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                EnableStatusHero(added: added)

                VStack(spacing: 10) {
                    EnableStepRow(step: 1, title: "打开系统设置", detail: "设置 › 通用 › 键盘 › 键盘", art: .settings)
                    EnableStepRow(step: 2, title: "添加 Mosto键盘", detail: "点「添加新键盘」选中 Mosto键盘", art: .add)
                    EnableStepRow(step: 3, title: "切到地球键开打", detail: "无需开启「允许完全访问」，全功能本机离线运行", art: .globe)
                }

                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Text(added ? "前往系统设置管理键盘" : "打开系统设置去添加")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(.white)
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
                        if typing {
                            Button("收起键盘") { typing = false }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MossOttoStyle.violet)
                        } else {
                            Text(added ? "点下方切换地球键验证" : "添加后可在此唤出系统键盘")
                                .font(.caption2)
                                .foregroundStyle(MossOttoStyle.inkSecondary)
                        }
                    }
                    TextField("全拼 nihao 或小鹤 nihc → 你好", text: $text, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($typing)
                        .font(.subheadline)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(MossOttoStyle.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(MossOttoStyle.hairline, lineWidth: 0.7)
                )
            }
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

    var body: some View {
        HStack(spacing: 12) {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let violet = Color(uiColor: MossOttoStyle.hex(0x633EBF))
                let green = Color(uiColor: MossOttoStyle.hex(0x55704A))
                let accent = added ? green : violet
                let bg = CGRect(x: w * 0.08, y: h * 0.08, width: w * 0.84, height: h * 0.84)
                ctx.fill(Path(roundedRect: bg, cornerRadius: w * 0.26), with: .color(accent.opacity(0.14)))
                ctx.stroke(Path(roundedRect: bg, cornerRadius: w * 0.26), with: .color(accent), lineWidth: 1.5)
                if added {
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
                        ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(violet.opacity(0.32)))
                    }
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(added ? "Mosto键盘已在系统启用" : "三步把 Mosto 装进系统键盘")
                    .font(.headline)
                    .foregroundStyle(MossOttoStyle.inkPrimary)
                Text(added ? "在任意应用长按地球键切换；系统键盘的偏好直接在键盘内「按住表情键」调整。" : "全程约半分钟，零联网权限也能使用全部纠错、双拼与心算能力。")
                    .font(.caption)
                    .foregroundStyle(MossOttoStyle.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
}

private enum StepArtKind { case settings, add, globe }

private struct EnableStepRow: View {
    let step: Int
    let title: String
    let detail: String
    let art: StepArtKind

    var body: some View {
        HStack(spacing: 12) {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let violet = Color(uiColor: MossOttoStyle.hex(0x633EBF))
                let gold = Color(uiColor: MossOttoStyle.hex(0xD69A34))
                let box = CGRect(x: w * 0.08, y: h * 0.08, width: w * 0.84, height: h * 0.84)
                ctx.fill(Path(roundedRect: box, cornerRadius: w * 0.24), with: .color(violet.opacity(0.10)))
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
