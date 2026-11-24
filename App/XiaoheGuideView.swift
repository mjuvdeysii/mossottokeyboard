import SwiftUI
import AudioToolbox

/// 小鹤双拼 reference chart & interactive tactile drill aligned with R50 monolith keycaps and OTTOSSOM styling.
struct XiaoheGuideView: View {
    var volume: VolumeMonitor? = nil

    var body: some View {
        ScrollView {
            XiaoheGuideContent(volume: volume)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .background(MossOttoStyle.canvas.ignoresSafeArea())
        .navigationTitle("小鹤双拼")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The page's content (shared with the CI snapshot).
struct XiaoheGuideContent: View {
    var volume: VolumeMonitor? = nil
    @State private var showCostNotice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "声感指法与键位图谱") {
                XiaoheDrill(volume: volume)
                Divider()
                HStack(spacing: 12) {
                    Legend(color: MossOttoStyle.violet, text: "zh / ch / sh")
                    Legend(color: MossOttoStyle.inkSecondary, text: "韵母")
                    Spacer(minLength: 0)
                    Text("其余声母即键帽本字")
                        .font(.caption)
                        .foregroundStyle(MossOttoStyle.inkSecondary)
                }
                .font(.caption)
            }

            Card(title: "两键成音 · 对比全拼") {
                VStack(alignment: .leading, spacing: 12) {
                    WrapLayout(spacing: 8, lineSpacing: 8) {
                        SyllableEquation(k1: "N", k2: "I", result: "你")
                        SyllableEquation(k1: "V", sub1: "zh", k2: "S", sub2: "ong", result: "中")
                        SyllableEquation(k1: "H", k2: "C", sub2: "ao", result: "好")
                        SyllableEquation(k1: "U", sub1: "sh", k2: "L", sub2: "uang", result: "双")
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        KeystrokeMeterRow(label: "全拼", ratio: 1.0, metric: "~3.0 键/字", highlight: false)
                        KeystrokeMeterRow(label: "小鹤", ratio: 2.0 / 3.0, metric: "固定 2 键 · 省 33%", highlight: true)
                    }

                    WrapLayout(spacing: 6, lineSpacing: 6) {
                        MiniBadgeChip(icon: "brain.head.profile", text: "需记 26 键韵母")
                        MiniBadgeChip(icon: "lightbulb.min.fill", text: "控制台可开键位提示")
                        MiniBadgeChip(icon: "arrow.triangle.branch", text: "与全拼共用纠错联想")
                    }
                }
            }

            Card(title: "零声母速查") {
                ZeroFormulaRow(tag: "1 字母 ×2", pairs: [("A+A", "啊"), ("O+O", "哦"), ("E+E", "饿")])
                Divider()
                ZeroFormulaRow(tag: "2 字母照打", pairs: [("A+I", "爱"), ("A+N", "安"), ("O+U", "欧"), ("E+R", "二")])
                Divider()
                ZeroFormulaRow(tag: "3 字母首+韵", pairs: [("A+H", "昂"), ("E+G", "鞥")])
                Text("y / w 开头按普通声母：yi · wo")
                    .font(.caption)
                    .foregroundStyle(MossOttoStyle.inkSecondary)
            }

            DisclosureGroup(isExpanded: SnapshotRenderer.requested ? .constant(true) : $showCostNotice) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(costs, id: \.self) { c in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("·").foregroundStyle(MossOttoStyle.inkSecondary)
                                Text(c)
                                    .font(.caption)
                                    .foregroundStyle(MossOttoStyle.inkPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Divider()
                    Text("“小鹤双拼”“小鹤音形”是小鹤（flypy.cc）发布的输入方案名称，相关名称、标识及商标等权利归其权利人所有。Mosto键盘与小鹤及其权利人没有隶属、合作、授权或背书关系。")
                        .font(.caption2)
                        .foregroundStyle(MossOttoStyle.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("本应用里的“小鹤双拼”只指与该方案兼容的键位规则，由开发者依据公开的汉语拼音规则独立实现；不包含、不分发小鹤音形码表、小鹤官方软件或其词库，也不使用小鹤的标识。词库来自开源项目雾凇拼音。")
                        .font(.caption2)
                        .foregroundStyle(MossOttoStyle.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 10)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MossOttoStyle.violet)
                    Text("学习成本与名称权利声明（flypy.cc · 雾凇拼音）")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MossOttoStyle.inkPrimary)
                    Spacer()
                }
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

    private let costs = [
        "需记忆 26 键韵母及 zh=V、ch=I、sh=U 借位。",
        "切换初期会暂时变慢，连续使用几天可形成指法肌肉记忆。",
        "与全拼频繁混切会互相干扰；全拼够用时无需强换。",
    ]
}

private struct SyllableEquation: View {
    let k1: String
    var sub1: String? = nil
    let k2: String
    var sub2: String? = nil
    let result: String

    var body: some View {
        HStack(spacing: 4) {
            cap(k1, sub: sub1, accent: sub1 != nil)
            Text("+").font(.caption2.weight(.bold)).foregroundStyle(MossOttoStyle.inkSecondary)
            cap(k2, sub: sub2, accent: false)
            Text("=").font(.caption2.weight(.bold)).foregroundStyle(MossOttoStyle.inkSecondary)
            Text(result)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MossOttoStyle.inkPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(MossOttoStyle.surfaceMuted))
    }

    private func cap(_ key: String, sub: String?, accent: Bool) -> some View {
        VStack(spacing: 0) {
            Text(key)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(MossOttoStyle.inkPrimary)
            if let sub {
                Text(sub)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent ? MossOttoStyle.violet : MossOttoStyle.inkSecondary)
            }
        }
        .frame(minWidth: 24, minHeight: 28)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(MossOttoStyle.surface))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(MossOttoStyle.hairline, lineWidth: 0.7))
    }
}

private struct KeystrokeMeterRow: View {
    let label: String
    let ratio: CGFloat
    let metric: String
    let highlight: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(highlight ? MossOttoStyle.violet : MossOttoStyle.inkSecondary)
                .frame(width: 34, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(MossOttoStyle.surfaceMuted)
                    Capsule()
                        .fill(highlight ? MossOttoStyle.violet : MossOttoStyle.inkSecondary.opacity(0.35))
                        .frame(width: max(16, geo.size.width * ratio))
                }
            }
            .frame(height: 8)
            Text(metric)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(highlight ? MossOttoStyle.violet : MossOttoStyle.inkSecondary)
                .frame(width: 108, alignment: .trailing)
        }
    }
}

private struct MiniBadgeChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MossOttoStyle.violet)
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(MossOttoStyle.inkSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(MossOttoStyle.surfaceMuted))
    }
}

private struct ZeroFormulaRow: View {
    let tag: String
    let pairs: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tag)
                .font(.caption2.weight(.bold))
                .foregroundStyle(MossOttoStyle.violet)
            HStack(spacing: 6) {
                ForEach(pairs, id: \.0) { code, ch in
                    HStack(spacing: 3.5) {
                        Text(code)
                            .font(.caption2.weight(.bold).monospaced())
                            .foregroundStyle(MossOttoStyle.inkPrimary)
                        Text(ch)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(MossOttoStyle.inkSecondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(MossOttoStyle.surfaceMuted))
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// The 26 letter keys in keyboard rows rendered as matte monolith caps.
struct XiaoheKeyChart: View {
    private let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 4
            let w = (geo.size.width - gap * 9) / 10
            VStack(spacing: 6) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(Array(row), id: \.self) { c in
                            ChartKey(letter: c).frame(width: w)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: 3 * 68 + 2 * 6)
    }
}

struct ChartKey: View {
    let letter: Character
    var mark: Color? = nil
    var pressed: Bool = false

    var body: some View {
        let g = XiaoheScheme.keyGuide[letter]
        MonolithKeycapView(
            label: String(letter).uppercased(),
            initialMark: g?.initial,
            finals: g?.finals ?? [],
            pressed: pressed,
            cornerRadius: 8
        )
        .frame(maxWidth: .infinity)
        .frame(height: 68)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(mark ?? .clear, lineWidth: 2)
        )
    }
}

private struct Legend: View {
    let color: Color, text: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundStyle(MossOttoStyle.inkSecondary)
        }
    }
}

/// Interactive tactile + acoustic Xiaohe rhythm drill and live 26-key inspector, volume-gated on first audible tap.
struct XiaoheDrill: View {
    var volume: VolumeMonitor? = nil

    private static let words: [(String, String)] = [
        ("你", "ni"), ("好", "hao"), ("我", "wo"), ("是", "shi"), ("中", "zhong"), ("国", "guo"), ("的", "de"),
        ("了", "le"), ("在", "zai"), ("人", "ren"), ("有", "you"), ("这", "zhe"), ("说", "shuo"), ("要", "yao"),
        ("就", "jiu"), ("出", "chu"), ("会", "hui"), ("学", "xue"), ("双", "shuang"), ("拼", "pin"), ("想", "xiang"),
        ("光", "guang"), ("熊", "xiong"), ("鹤", "he"), ("安", "an"), ("爱", "ai"), ("二", "er"), ("饿", "e"),
        ("昂", "ang"), ("欧", "ou"), ("用", "yong"), ("天", "tian"), ("气", "qi"), ("小", "xiao"), ("月", "yue"),
        ("去", "qu"), ("快", "kuai"), ("床", "chuang"), ("水", "shui"), ("追", "zhui"), ("女", "nv"), ("绿", "lv"),
        ("春", "chun"), ("松", "song"), ("飞", "fei"), ("秋", "qiu"), ("林", "lin"), ("星", "xing"), ("村", "cun"),
        ("百", "bai"), ("南", "nan"), ("北", "bei"), ("门", "men"), ("风", "feng"), ("花", "hua"), ("鸟", "niao"),
        ("高", "gao"), ("草", "cao"), ("热", "re"), ("甜", "tian"), ("军", "jun"), ("选", "xuan"), ("略", "lve"),
    ]
    @State private var inspectMode = false
    @State private var inspectedKey: Character = "v"
    @State private var index = Int.random(in: 0..<XiaoheDrill.words.count)
    @State private var typed: [Character] = []
    @State private var verdict: Bool?
    @State private var streak = 0
    @State private var flashKey: Character?
    private let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    private var word: (String, String) { Self.words[index] }
    private var code: [Character] { Array(XiaoheScheme.code(for: word.1) ?? "") }

    /// Verified 2-key syllable examples whose Xiaohe sequence uses `key`.
    static func inspectExamplesForTests(key: Character) -> [(hanzi: String, pinyin: String, code: String)] {
        let lower = Character(String(key).lowercased())
        var out: [(hanzi: String, pinyin: String, code: String)] = []
        for (hanzi, py) in words {
            if let code = XiaoheScheme.code(for: py), code.contains(lower) {
                out.append((hanzi, py.replacingOccurrences(of: "v", with: "ü"), code))
                if out.count >= 3 { break }
            }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                modePill(title: "指法跟练", active: !inspectMode) { inspectMode = false }
                modePill(title: "点键查码", active: inspectMode) { inspectMode = true }
                Spacer(minLength: 0)
            }

            if inspectMode {
                inspectorHeader
            } else {
                drillHeader
            }

            VStack(spacing: 6) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(Array(row), id: \.self) { c in
                            Button { tap(c) } label: {
                                ChartKey(letter: c, mark: keyMark(c), pressed: flashKey == c || (inspectMode && inspectedKey == c))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(c))
                        }
                    }
                    .padding(.horizontal, row.count == 10 ? 0 : (row.count == 9 ? 14 : 44))
                }
            }

            if !inspectMode && verdict == false {
                Button("下一个") { next() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MossOttoStyle.violet)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: typed.count)
        .animation(.easeOut(duration: 0.2), value: verdict)
        .animation(.easeOut(duration: 0.16), value: inspectMode)
    }

    private func modePill(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(active ? Color.white : MossOttoStyle.inkSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(active ? MossOttoStyle.violet : MossOttoStyle.surfaceMuted))
        }
        .buttonStyle(.plain)
    }

    private var drillHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 2) {
                Text(word.0)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(MossOttoStyle.inkPrimary)
                Text(word.1.replacingOccurrences(of: "v", with: "ü"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(MossOttoStyle.inkSecondary)
            }
            .frame(width: 72)

            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { i in
                    let shown: Character? = i < typed.count ? typed[i] : (verdict == false ? code[i] : nil)
                    Text(shown.map { String($0).uppercased() } ?? "")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(MossOttoStyle.inkPrimary)
                        .frame(width: 48, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(MossOttoStyle.surfaceMuted)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(slotColor(i), lineWidth: 1.8)
                        )
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                if let v = verdict {
                    Label(v ? "对了" : "是 \(String(code).uppercased())", systemImage: v ? "checkmark.circle.fill" : "arrow.uturn.right.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(v ? MossOttoStyle.moss : MossOttoStyle.lampAmber)
                }
                if streak > 1 {
                    Text("连对 \(streak)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MossOttoStyle.violet)
                }
            }
        }
    }

    private var inspectorHeader: some View {
        let g = XiaoheScheme.keyGuide[inspectedKey]
        let initialText = g?.initial.map { "借声母 \($0)" } ?? (XiaoheScheme.plainInitials.contains(inspectedKey) ? "声母 \(inspectedKey)" : "零声母占位")
        let finalsText = (g?.finals.isEmpty == false) ? "韵母 " + (g?.finals.joined(separator: " / ") ?? "") : "无对应韵母"
        let exs = Self.inspectExamplesForTests(key: inspectedKey)
        return HStack(alignment: .center, spacing: 12) {
            Text(String(inspectedKey).uppercased())
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(MossOttoStyle.inkPrimary)
                .frame(width: 48, height: 52)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(MossOttoStyle.surfaceMuted))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(MossOttoStyle.violet, lineWidth: 1.6))

            VStack(alignment: .leading, spacing: 5) {
                Text("\(initialText)  ·  \(finalsText)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MossOttoStyle.inkPrimary)
                HStack(spacing: 6) {
                    ForEach(exs, id: \.hanzi) { ex in
                        Text("\(ex.hanzi) \(ex.code.uppercased())")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(MossOttoStyle.inkSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(MossOttoStyle.surfaceMuted))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func slotColor(_ i: Int) -> Color {
        guard let v = verdict else { return i == typed.count ? MossOttoStyle.violet : MossOttoStyle.hairline }
        return v ? MossOttoStyle.moss : MossOttoStyle.lampAmber
    }

    private func keyMark(_ c: Character) -> Color? {
        if inspectMode { return inspectedKey == c ? MossOttoStyle.violet : nil }
        guard verdict == false else { return nil }
        return code.contains(c) ? MossOttoStyle.lampAmber : nil
    }

    private func tap(_ c: Character) {
        if !inspectMode, (verdict != nil || typed.count >= 2) { return }
        let s = KeyboardSettings.shared
        let soundOn = s.keySound
        let feedbackOn = s.feedback
        let profile = HapticProfile(rawValue: s.hapticProfile) ?? .crisp
        let proceed = {
            flashKey = c
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if flashKey == c { flashKey = nil }
            }
            if feedbackOn {
                let t = SystemFeedbackPlayer.tunedImpact(for: profile, firm: false)
                UIImpactFeedbackGenerator(style: t.style).impactOccurred(intensity: t.intensity)
            }
            if soundOn { AudioServicesPlaySystemSound(1104) }
            if inspectMode {
                inspectedKey = c
                return
            }
            typed.append(c)
            guard typed.count == 2 else { return }
            let ok = typed == code
            verdict = ok
            streak = ok ? streak + 1 : 0
            if feedbackOn {
                UINotificationFeedbackGenerator().notificationOccurred(ok ? .success : .warning)
            }
            if ok { DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { next() } }
        }
        if let volume {
            volume.gateSoundInteraction(soundEnabled: soundOn, action: proceed)
        } else {
            proceed()
        }
    }

    private func next() {
        typed = []
        verdict = nil
        var n = Int.random(in: 0..<Self.words.count)
        if n == index { n = (n + 1) % Self.words.count }
        index = n
    }
}
