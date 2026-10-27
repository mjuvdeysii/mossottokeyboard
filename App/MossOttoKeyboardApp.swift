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
                            Usage(icon: "textformat.abc", text: "中英混输：打 ok、ios、iphone 直接出 OK、iOS、iPhone。")
                            Usage(icon: "character.cursor.ibeam", text: "英文模式（中/英 切到“英”）也按触点纠错并给出候选：teh → the、dont → don't、im → I'm；空格时替换，删除可撤回；首字母自动大写，双击空格出句号。")
                            Usage(icon: "chevron.down", text: "候选栏右侧 ⌄ 展开全部候选；长按自己学过的词可以删掉它。")
                            Usage(icon: "arrow.left.and.right", text: "按住空格左右拖动移动光标。数字和符号在 123（九宫格数字键盘）与 #+= 页；长按 ， 可选 。？！、…：")
                            Usage(icon: "face.smiling", text: "😊 表情：常用与八个分类，上下滑动，底栏一点跳到分类。按住 😊 打开键盘设置：输入方案、九宫格、中英混输、自动纠错、震动与按键音、外观。")
                            Usage(icon: "circle.lefthalf.filled", text: "外观：自动跟随系统浅色 / 深色；也可固定日光或夜灯。")
                        }
                        Card(title: "Mosto 的两种光") {
                            HStack(alignment: .top, spacing: 12) {
                                LightTile(image: "Mosto", title: "日光", text: "瞪大眼睛看你打字。住在键盘设置的顶部。")
                                LightTile(image: "MostoNight", title: "夜灯", text: "眯眼坏笑，尾巴尖亮起金光，待在候选栏左边。")
                            }
                        }
                        Card(title: "关于") {
                            if snapshot {
                                Label("隐私与开源许可", systemImage: "hand.raised")
                            } else {
                                NavigationLink { AboutView() } label: {
                                    Label("隐私与开源许可", systemImage: "hand.raised").frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            Divider()
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

    var body: some View {
        HStack(spacing: 14) {
            Image(uiImage: mostoImage(scheme == .dark ? "MostoNight" : (blink ? "MostoBlink" : "Mosto")))
                .resizable().scaledToFit()
                .frame(width: 104, height: 104)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Mosto键盘").font(.title2.weight(.bold))
                Text("小鹤双拼 · 全拼 · 九宫格\n按触点位置自动纠错")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Mosto，念快了像“魔头”：住在键盘里的小魔王，歪戴小金冠。")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(scheme == .dark
                      ? LinearGradient(colors: [Color(red: 0.16, green: 0.13, blue: 0.27), Color(red: 0.10, green: 0.11, blue: 0.22)], startPoint: .top, endPoint: .bottom)
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

/// Privacy and the licences of what the keyboard is built from (required for a release).
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Card(title: "隐私") {
                    Text("Mosto键盘不联网，也没有任何统计或广告代码。你打的字、学过的词和触点习惯只保存在这台设备上的键盘里，不会被收集或上传。")
                    Text("“允许完全访问”只用于震动和按键音；不开也能正常打字。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Card(title: "开源许可") {
                    License(name: "雾凇拼音 rime-ice（中文词库）", license: "GPL-3.0", url: "https://github.com/iDvel/rime-ice")
                    Divider()
                    License(name: "wordfreq（英文词频，中英混输）", license: "数据 CC BY-SA 4.0", url: "https://github.com/rspeer/wordfreq")
                    Divider()
                    License(name: "Emojibase（表情列表与分类）", license: "MIT", url: "https://github.com/milesj/emojibase")
                    Divider()
                    License(name: "Mosto键盘", license: "GPL-3.0", url: "https://github.com/mjuvdeysii/mossottokeyboard")
                }
            }
            .padding(16)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("隐私与开源许可")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct License: View {
    let name: String
    let license: String
    let url: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.subheadline.weight(.semibold))
            Text(license).font(.footnote).foregroundStyle(.secondary)
            if let u = URL(string: url) { Link(url, destination: u).font(.footnote) }
        }
    }
}
