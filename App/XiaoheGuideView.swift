import SwiftUI

/// 小鹤双拼, explained for someone who types 全拼 today: what it is, what it costs to learn (plainly — the app does
/// not push anyone to switch), the full key chart, how syllables without an initial are typed, the keyboard's
/// learning mode, and who owns the name. The chart is drawn from XiaoheScheme.keyGuide, the table the keyboard uses.
struct XiaoheGuideView: View {
    var body: some View {
        ScrollView { XiaoheGuideContent().padding(.horizontal, 16).padding(.vertical, 12) }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("小鹤双拼")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// The page's content (shared with the CI snapshot).
struct XiaoheGuideContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Card(title: "是什么") {
                Text("双拼把每个音节固定成两个键：第一个键打声母，第二个键打韵母。小鹤双拼是其中一种键位安排。")
                    .fixedSize(horizontal: false, vertical: true)
                Text("例：你好 → ni hc　中国 → vs go　双拼 → ul pb")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Mosto键盘的全拼与小鹤双拼功能完全相同（纠错、联想、九宫格、学习），用哪一种都可以，随时在键盘设置里切换。")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
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
                        Text("·").foregroundStyle(.secondary)
                        Text(c).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Card(title: "键位表") {
                XiaoheKeyChart()
                HStack(spacing: 14) {
                    Legend(color: mostoTint, text: "声母 zh ch sh")
                    Legend(color: .secondary, text: "韵母")
                }
                .font(.caption)
                Text("其余声母（b p m f d t n l g k h j q x r z c s y w）就是它本身的字母。")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            Card(title: "没有声母的字（零声母）") {
                ZeroRow(rule: "单字母韵母：按两次", examples: "啊 a → aa　哦 o → oo　饿 e → ee")
                Divider()
                ZeroRow(rule: "两个字母的韵母：照原样打", examples: "爱 ai → ai　安 an → an　欧 ou → ou　二 er → er")
                Divider()
                ZeroRow(rule: "三个字母的韵母：首字母 + 韵母所在的键", examples: "昂 ang → ah　鞥 eng → eg")
                Text("y、w 开头的音节（一 yi、我 wo）按普通声母打：yi、wo。")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            Card(title: "学习模式") {
                Text("键盘设置（按住 😊 键）› 小鹤双拼 › 键位提示：打开后，小鹤方案下每个字母键上会显示它代表的声母和韵母，不用另外看图。记熟后可以关掉。横屏时键帽太矮，只显示字母。")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }

            Card(title: "名称与权利说明") {
                Text("“小鹤双拼”“小鹤音形”是小鹤（flypy.cc）发布的输入方案名称，相关名称、标识及商标等权利归其权利人所有。Mosto键盘与小鹤及其权利人没有隶属、合作、授权或背书关系。")
                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
                Text("本应用里的“小鹤双拼”只指与该方案兼容的键位规则，由开发者依据公开的汉语拼音规则独立实现；不包含、不分发小鹤音形码表、小鹤官方软件或其词库，也不使用小鹤的标识。词库来自开源项目雾凇拼音。")
                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.secondary)
        }
    }

    private let costs = [
        "要背键位。韵母分散在 26 个键上，有的键放两个韵母（如 S 是 ong 和 iong），zh、ch、sh 借用 V、I、U。",
        "刚换过来的一段时间，打字会明显比全拼慢、也更容易打错；要每天坚持用，才能从“想键位”变成手指记住。多久能追上全拼因人而异。",
        "全拼和双拼来回换着用，两套记忆会互相干扰。换别的设备或输入法时，也要记得把方案选成小鹤。",
        "省下的是按键次数，不是思考时间。如果全拼的速度已经够用，没有必要为此切换。",
    ]
}

/// The 26 letter keys in keyboard rows, each with the initial (accent) and finals it stands for.
struct XiaoheKeyChart: View {
    private let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 4
            let w = (geo.size.width - gap * 9) / 10
            VStack(spacing: 6) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(Array(row), id: \.self) { c in ChartKey(letter: c).frame(width: w) }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: 3 * 70 + 2 * 6)
    }
}

private struct ChartKey: View {
    let letter: Character
    var body: some View {
        let g = XiaoheScheme.keyGuide[letter]
        VStack(spacing: 1) {
            Text(String(letter).uppercased()).font(.system(size: 15, weight: .semibold, design: .rounded))
            if let i = g?.initial {
                Text(i).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(mostoTint)
            }
            ForEach(g?.finals ?? [], id: \.self) { f in
                Text(f).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.top, 5)
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(UIColor.tertiarySystemGroupedBackground)))
    }
}

private struct CompareRow: View {
    let label: String, quanpin: String, xiaohe: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.semibold))
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
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ZeroRow: View {
    let rule: String, examples: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rule).font(.subheadline.weight(.semibold))
            Text(examples).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Legend: View {
    let color: Color, text: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundStyle(.secondary)
        }
    }
}
