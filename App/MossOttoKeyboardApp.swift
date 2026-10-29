import SwiftUI

@main
struct MossOttoKeyboardApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// Mosto sprites from the app's asset catalog (full resolution; the keyboard carries small copies of its own).
func mostoImage(_ name: String) -> UIImage { UIImage(named: name) ?? UIImage() }

/// Mosto's violet (the app tint), lighter in dark mode so it keeps its contrast.
let mostoTint = Color(UIColor { $0.userInterfaceStyle == .dark
    ? UIColor(red: 0xB7 / 255, green: 0xA2 / 255, blue: 0xF5 / 255, alpha: 1)
    : UIColor(red: 0x55 / 255, green: 0x36 / 255, blue: 0xB0 / 255, alpha: 1) })

/// The companion app: Mosto, how to turn the keyboard on, a field to try it, how it works, and the fine print.
/// Built from plain stacks (not Form), laid out like iOS Settings, so the same view also renders to an image in CI.
struct ContentView: View {
    @State private var text = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                HomeContent(text: $text)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Mosto键盘")
            .navigationBarTitleDisplayMode(.inline)
            .tint(mostoTint)
            .task {
                // CI only: render the keyboard's real views to PNGs, then exit (SnapshotRenderer.swift)
                if SnapshotRenderer.requested,
                   let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                    SnapshotRenderer.run(in: scene)
                }
            }
        }
    }
}

/// Everything on the home screen (shared by the app and the CI snapshot of it).
struct HomeContent: View {
    @Binding var text: String
    var snapshot = false

    var body: some View {
                VStack(alignment: .leading, spacing: 22) {
                    MostoHero()
                    Group {
                        Card(title: "启用键盘") {
                            Step(n: 1, text: "打开 设置 › 通用 › 键盘 › 键盘 › 添加新键盘，选择 Mosto键盘。")
                            Divider()
                            Step(n: 2, text: "打字时长按或轻点 🌐，切换到 Mosto键盘。")
                            Divider()
                            Step(n: 3, text: "（可选）在键盘列表中点 Mosto键盘，开启“允许完全访问”，就有按键震动和按键音。键盘本身不联网。")
                            Divider()
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            } label: {
                                Label("打开系统设置", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 2)
                        }
                        if !snapshot {
                            Card(title: "试打") {
                                TextField("小鹤 nihc 或全拼 nihao → 你好", text: $text, axis: .vertical)
                                    .lineLimit(3...8)
                            }
                        }
                        Card(title: "用法") {
                            Usage(icon: "keyboard", text: "两种输入方案，在键盘设置里切换：小鹤双拼（每个字两个键，纯双拼，无形码）与全拼（完整拼写，也可只打声母，如 nh → 你好）。")
                            Usage(icon: "square.grid.3x3", text: "中文键盘可选全键盘或九宫格；九宫格两种方案都能用：打字时左列列出可能的拼音，点一下就定下这几个键，“分词”切开音节。")
                            Usage(icon: "space", text: "空格：上屏首选　回车：上屏字母　删除：逐键回退，按住会加速，再久一点按词删除。")
                            Usage(icon: "wand.and.stars", text: "首选带下划线 = 已按触点位置自动纠错；第二个候选是未纠错的原文。上屏后立刻按删除可撤回纠错。")
                            Usage(icon: "text.append", text: "联想：中文上屏后，候选栏给出接下来常用的字词，点一下直接上屏并继续联想；按任意键即收起。")
                            Usage(icon: "textformat.abc", text: "中英混输：打 ok、ios、iphone 直接出 OK、iOS、iPhone。")
                            Usage(icon: "character.cursor.ibeam", text: "英文模式（中/英 切到“英”）也按触点纠错并给出候选：teh → the、dont → don't、im → I'm；空格时替换，删除可撤回；首字母自动大写，双击空格出句号。")
                            Usage(icon: "chevron.down", text: "候选栏右侧 ⌄ 展开全部候选；长按自己学过的词可以删掉它。")
                            Usage(icon: "arrow.left.and.right", text: "按住空格左右拖动移动光标。123 打开数字符号页或九宫格数字键盘（键盘设置里选；用九宫格打字时默认九宫格数字，数字输入框也自动换成它）；长按 ， 可选 。？！、…：")
                            Usage(icon: "face.smiling", text: "😊 表情：常用与八个分类，上下滑动，底栏一点跳到分类。按住 😊 打开键盘设置：输入方案、九宫格、数字键盘、中英混输、自动纠错、震动与按键音、外观。")
                            Usage(icon: "hand.tap", text: "候选栏左边的 Mosto：轻点一下打开他的颜文字（右下角“返回”回到键盘），轻点两下切换日光 / 夜灯。")
                            Usage(icon: "circle.lefthalf.filled", text: "外观：自动跟随系统浅色 / 深色；也可固定日光或夜灯（按键与 Mosto 换光，候选栏跟随系统，始终看得清）。")
                        }
                        Card(title: "小鹤双拼") {
                            Text("每个字固定两键的双拼方案。全拼用户请先看清学习成本再决定；不切换也完全没关系，两种方案在这个键盘上功能相同。")
                                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                            if snapshot {
                                Label("说明、学习成本与键位表", systemImage: "keyboard.badge.ellipsis")
                            } else {
                                NavigationLink { XiaoheGuideView() } label: {
                                    Label("说明、学习成本与键位表", systemImage: "keyboard.badge.ellipsis").frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        Card(title: "Mosto 的两种光") {
                            HStack(alignment: .top, spacing: 12) {
                                LightTile(image: "Mosto", title: "日光", text: "瞪大眼睛看你打字，不打字时待在候选栏左边，偶尔眨眼。")
                                LightTile(image: "MostoNight", title: "夜灯", text: "眯眼坏笑，尾巴尖亮起灯珠的金光，待在候选栏左边；键盘闲下来，他会慢慢打个哈欠。")
                            }
                        }
                        Card(title: "关于") {
                            // privacy policy, terms and disclaimer, licences: each its own page (the same text as the
                            // hosted pages, from Tools/build_legal.py), plus beta notes and where to give feedback
                            ForEach(Array(LegalText.docs.enumerated()), id: \.offset) { i, doc in
                                if i > 0 { Divider() }
                                if snapshot {
                                    Label(doc.title, systemImage: aboutIcon(doc.id))
                                } else {
                                    NavigationLink { LegalView(doc: doc) } label: {
                                        Label(doc.title, systemImage: aboutIcon(doc.id)).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            Divider()
                            Label("测试版：功能可能变动，发送重要内容前请核对上屏文字。在 TestFlight 中截图即可提交反馈。", systemImage: "testtube.2")
                                .font(.footnote)
                            if let u = URL(string: "https://github.com/mjuvdeysii/mossottokeyboard/issues") {
                                Link(destination: u) { Label("问题与建议", systemImage: "bubble.left.and.text.bubble.right") }
                            }
                            Divider()
                            Text("纯粹的输入法：不含 AI，不接入任何大模型或云端服务。候选来自装在 App 里的开源词库与统计数据（按词语在公开语料里出现的次数排序），全部在手机上计算。")
                                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Text("键盘不联网。词库、你学过的词和触点习惯只存在这台设备上，不会上传。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
    }
}

/// Mosto at the top of the app: the day sprite blinking now and then, the night sprite in dark mode, the name and
/// what the keyboard is — on a warm cream card (the icon's colours), so the violet stands out.
struct MostoHero: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blink = false
    @State private var hop = false

    var body: some View {
        HStack(spacing: 14) {
            // a designer toy on its base: Mosto standing on one of the keyboard's vinyl keys (face over lip)
            VStack(spacing: -20) {
                Image(uiImage: mostoImage(scheme == .dark ? "MostoNight" : (blink ? "MostoBlink" : "Mosto")))
                    .resizable().scaledToFit()
                    .frame(width: 104, height: 104)
                    .scaleEffect(x: hop ? 1.08 : 1, y: hop ? 0.9 : 1, anchor: .bottom)
                    .offset(y: hop ? -6 : 0)
                    .zIndex(1)
                ToyKey(night: scheme == .dark).frame(width: 84, height: 32)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) { hop = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { hop = false }
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Mosto键盘").font(.title2.weight(.bold))
                Text("小鹤双拼 · 全拼 · 九宫格\n按触点位置自动纠错")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Mosto，念快了像“魔头”：Moss 与 Otto 共同的另一面，住在键盘里的小魔王，歪戴小金冠。")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(scheme == .dark
                      ? LinearGradient(colors: [Color(red: 0.19, green: 0.14, blue: 0.38), Color(red: 0.10, green: 0.08, blue: 0.24)], startPoint: .top, endPoint: .bottom)
                      : LinearGradient(colors: [Color(red: 1.0, green: 0.96, blue: 0.86), Color(red: 0.98, green: 0.88, blue: 0.66)], startPoint: .top, endPoint: .bottom))
        )
        .padding(.top, 8)
        .task {
            // by day an occasional quick blink (5–9 s), as in the keyboard; never with Reduce Motion
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 5...9) * 1_000_000_000))
                blink = true
                try? await Task.sleep(nanoseconds: 110_000_000)
                blink = false
            }
        }
    }
}

/// One of the keyboard's vinyl keys, as Mosto's base: a cream face resting on a lavender lip (violet at night).
struct ToyKey: View {
    let night: Bool
    var body: some View {
        let lip = night ? Color(red: 0.11, green: 0.07, blue: 0.28) : Color(red: 0.80, green: 0.75, blue: 0.92)
        let top = night ? Color(red: 0.32, green: 0.26, blue: 0.62) : Color.white
        let bottom = night ? Color(red: 0.27, green: 0.22, blue: 0.55) : Color(red: 1.0, green: 0.99, blue: 0.97)
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(lip)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
                .padding(.bottom, 5)
        }
        .shadow(color: Color(red: 0.17, green: 0.10, blue: 0.38).opacity(0.18), radius: 6, y: 4)
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote).foregroundStyle(.secondary).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
        }
    }
}

struct Step: View {
    let n: Int
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(mostoTint))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Usage: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).foregroundStyle(mostoTint).frame(width: 22)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct LightTile: View {
    let image: String
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 6) {
            Image(uiImage: mostoImage(image)).resizable().scaledToFit().frame(height: 84)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(image.hasSuffix("Night") ? Color(red: 0.11, green: 0.13, blue: 0.27) : Color(red: 0.99, green: 0.93, blue: 0.80)))
                .accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

func aboutIcon(_ id: String) -> String {
    switch id { case "privacy": return "hand.raised"; case "terms": return "doc.text"; default: return "shippingbox" }
}

/// One legal page (隐私政策 / 用户协议与免责声明 / 开源许可): the same text as the hosted page, readable offline.
struct LegalView: View {
    let doc: LegalText.Doc
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("生效日期：\(LegalText.effective)").font(.footnote).foregroundStyle(.secondary)
                ForEach(Array(doc.sections.enumerated()), id: \.offset) { _, section in
                    Card(title: section.0) {
                        ForEach(Array(section.1.enumerated()), id: \.offset) { _, item in
                            switch item {
                            case .text(let t):
                                Text(linked(t)).fixedSize(horizontal: false, vertical: true)
                            case .bullets(let list):
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(list.enumerated()), id: \.offset) { _, b in
                                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                                            Text("•").foregroundStyle(.secondary)
                                            Text(linked(b)).fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if let u = URL(string: LegalText.site + "/" + doc.id + ".html") {
                    Link("网页版：" + u.absoluteString, destination: u).font(.footnote)
                }
            }
            .padding(16)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle(doc.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Plain text with its web addresses made tappable.
    private func linked(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return a }
        for m in det.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let url = m.url, let r = Range(m.range, in: s), let ar = Range(r, in: a) else { continue }
            a[ar].link = url
        }
        return a
    }
}

