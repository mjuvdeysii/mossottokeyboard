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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Card(title: "是什么") {
                Text("双拼把每个音节固定成两个键：第一个键打声母，第二个键打韵母。小鹤双拼是其中一种键位安排。")
                    .foregroundStyle(MossOttoStyle.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("例：你好 → ni hc　中国 → vs go　双拼 → ul pb")
                    .font(.subheadline)
                    .foregroundStyle(MossOttoStyle.inkSecondary)
                Text("Mosto键盘的全拼与小鹤双拼功能完全相同（纠错、联想、九宫格、学习），用哪一种都可以，在工作台或键盘面板随时切换。")
                    .font(.subheadline)
                    .foregroundStyle(MossOttoStyle.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Card(title: "和全拼比") {
                CompareRow(label: "每个字按几下", quanpin: "平均约 3 下（本应用测试语料 5,287 个音节，平均 2.98）", xiaohe: "固定 2 下")
                Divider()
                CompareRow(label: "要记什么", quanpin: "不用额外记", xiaohe: "30 多个韵母和 zh / ch / sh 在 26 个键上的位置，以及零声母的打法")
                Divider()
                CompareRow(label: "换个输入法", quanpin: "任何输入法都能打", xiaohe: "要那个输入法也提供小鹤方案，并手动选上")
            }

            Card(title: "学习成本（建议先读完再决定）") {
                ForEach(costs, id: \.self) { c in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("·").foregroundStyle(MossOttoStyle.inkSecondary)
                        Text(c)
                            .font(.subheadline)
                            .foregroundStyle(MossOttoStyle.inkPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Card(title: "键位表") {
                XiaoheKeyChart()
                HStack(spacing: 14) {
                    Legend(color: MossOttoStyle.violet, text: "声母 zh ch sh")
                    Legend(color: MossOttoStyle.inkSecondary, text: "韵母")
                }
                .font(.caption)
                Text("其余声母（b p m f d t n l g k h j q x r z c s y w）就是它本身的字母。")
                    .font(.footnote)
                    .foregroundStyle(MossOttoStyle.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Card(title: "声感指法练一练") {
                XiaoheDrill(volume: volume)
            }

            Card(title: "没有声母的字（零声母）") {
                ZeroRow(rule: "单字母韵母：按两次", examples: "啊 a → aa　哦 o → oo　饿 e → ee")
                Divider()
                ZeroRow(rule: "两个字母的韵母：照原样打", examples: "爱 ai → ai　安 an → an　欧 ou → ou　二 er → er")
                Divider()
                ZeroRow(rule: "三个字母的韵母：首字母 + 韵母所在的键", examples: "昂 ang → ah　鞥 eng → eg")
                Text("y、w 开头的音节（一 yi、我 wo）按普通声母打：yi、wo。")
                    .font(.footnote)
                    .foregroundStyle(MossOttoStyle.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Card(title: "学习模式") {
                Text("按住表情键打开键盘设置 › 小鹤双拼 › 键位提示：开启后，每个字母键上会显示声母与韵母，不必对照外图。记熟后随时关闭。")
                    .font(.subheadline)
                    .foregroundStyle(MossOttoStyle.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Card(title: "名称与权利说明") {
                Text("“小鹤双拼”“小鹤音形”是小鹤（flypy.cc）发布的输入方案名称，相关名称、标识及商标等权利归其权利人所有。Mosto键盘与小鹤及其权利人没有隶属、合作、授权或背书关系。")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                Text("本应用里的“小鹤双拼”只指与该方案兼容的键位规则，由开发者依据公开的汉语拼音规则独立实现；不包含、不分发小鹤音形码表、小鹤官方软件或其词库，也不使用小鹤的标识。词库来自开源项目雾凇拼音。")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(MossOttoStyle.inkSecondary)
        }
    }

    private let costs = [
        "要背键位。韵母分散在 26 个键上，有的键放两个韵母（如 S 是 ong 和 iong），zh、ch、sh 借用 V、I、U。",
        "刚换过来的一段时间，打字会明显比全拼慢、也更容易打错；要每天坚持用，才能从“想键位”变成手指记住。",
        "全拼和双拼来回换着用，两套记忆会互相干扰。换别的设备或输入法时，也要记得把方案选成小鹤。",
        "省下的是按键次数，不是思考时间。全拼的速度已经够用，就继续用全拼。",
    ]
}

/// The 26 letter keys in keyboard rows rendered as R50 matte monolith caps.
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

private struct CompareRow: View {
    let label: String, quanpin: String, xiaohe: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MossOttoStyle.inkPrimary)
            HStack(alignment: .top, spacing: 10) {
                Column(title: "全拼", text: quanpin)
                Column(title: "小鹤双拼", text: xiaohe)
            }
        }
    }

    private struct Column: View {
        let title: String, text: String
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(MossOttoStyle.inkSecondary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(MossOttoStyle.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ZeroRow: View {
    let rule: String, examples: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rule)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MossOttoStyle.inkPrimary)
            Text(examples)
                .font(.subheadline)
                .foregroundStyle(MossOttoStyle.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

/// Interactive tactile + acoustic Xiaohe rhythm drill, volume-gated on first audible tap.
struct XiaoheDrill: View {
    var volume: VolumeMonitor? = nil

    private static let words: [(String, String)] = [
        ("你", "ni"), ("好", "hao"), ("我", "wo"), ("是", "shi"), ("中", "zhong"), ("国", "guo"), ("的", "de"),
        ("了", "le"), ("在", "zai"), ("人", "ren"), ("有", "you"), ("这", "zhe"), ("说", "shuo"), ("要", "yao"),
        ("就", "jiu"), ("出", "chu"), ("会", "hui"), ("学", "xue"), ("双", "shuang"), ("拼", "pin"), ("想", "xiang"),
        ("光", "guang"), ("熊", "xiong"), ("鹤", "he"), ("安", "an"), ("爱", "ai"), ("二", "er"), ("饿", "e"),
        ("昂", "ang"), ("欧", "ou"), ("用", "yong"), ("天", "tian"), ("气", "qi"), ("小", "xiao"), ("月", "yue"),
        ("去", "qu"), ("快", "kuai"), ("床", "chuang"), ("水", "shui"), ("追", "zhui"), ("女", "nv"), ("绿", "lv"),
    ]
    @State private var index = Int.random(in: 0..<XiaoheDrill.words.count)
    @State private var typed: [Character] = []
    @State private var verdict: Bool?
    @State private var streak = 0
    @State private var flashKey: Character?
    private let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    private var word: (String, String) { Self.words[index] }
    private var code: [Character] { Array(XiaoheScheme.code(for: word.1) ?? "") }

    var body: some View {
        VStack(spacing: 12) {
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

            VStack(spacing: 6) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(Array(row), id: \.self) { c in
                            Button { tap(c) } label: {
                                ChartKey(letter: c, mark: keyMark(c), pressed: flashKey == c)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(c))
                        }
                    }
                    .padding(.horizontal, row.count == 10 ? 0 : (row.count == 9 ? 14 : 44))
                }
            }

            if verdict == false {
                Button("下一个") { next() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MossOttoStyle.violet)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: typed.count)
        .animation(.easeOut(duration: 0.2), value: verdict)
    }

    private func slotColor(_ i: Int) -> Color {
        guard let v = verdict else { return i == typed.count ? MossOttoStyle.violet : MossOttoStyle.hairline }
        return v ? MossOttoStyle.moss : MossOttoStyle.lampAmber
    }

    private func keyMark(_ c: Character) -> Color? {
        guard verdict == false else { return nil }
        return code.contains(c) ? MossOttoStyle.lampAmber : nil
    }

    private func tap(_ c: Character) {
        guard verdict == nil, typed.count < 2 else { return }
        let soundOn = KeyboardSettings.shared.keySound
        let proceed = {
            flashKey = c
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if flashKey == c { flashKey = nil }
            }
            typed.append(c)
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.66)
            if soundOn { AudioServicesPlaySystemSound(1104) }
            guard typed.count == 2 else { return }
            let ok = typed == code
            verdict = ok
            streak = ok ? streak + 1 : 0
            UINotificationFeedbackGenerator().notificationOccurred(ok ? .success : .warning)
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
