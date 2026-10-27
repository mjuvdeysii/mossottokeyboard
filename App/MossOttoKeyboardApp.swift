import SwiftUI

@main
struct MossOttoKeyboardApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image("Mosto").resizable().scaledToFit().frame(width: 96, height: 96)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Mosto").font(.title2.weight(.semibold))
                            Text("名字念快了像“魔头”：一只住在键盘里的小恶魔。白天一只眼圆睁、一只眼半垂地看你打字，夜里眯起眼，尾巴尖亮起红光。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("启用键盘") {
                    Text("1. 打开 设置 › 通用 › 键盘 › 键盘 › 添加新键盘，选择本键盘。")
                    Text("2. 打字时长按或轻点 🌐 切换到本键盘。")
                    Text("3.（可选）在键盘列表中点本键盘，开启“允许完全访问”以启用震动和按键音。键盘本身不联网，词库与学习数据只存放在本机。")
                    Button("打开系统设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Section("试打") {
                    TextField("在这里试打：小鹤 nihc 或全拼 nihao → 你好", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("用法") {
                    Text("两种输入方案，在键盘设置里切换：小鹤双拼（每个字两个键）与全拼（完整拼写，也可只打声母，如 nh → 你好）。")
                    Text("空格：上屏首选　回车：上屏字母　删除：逐键回退")
                    Text("首选带下划线 = 已按触点位置自动纠错；第二个候选是未纠错的原文。两种方案都支持。")
                    Text("候选栏右侧 ⌄ 展开全部候选。")
                    Text("空格键左右拖动可移动光标；长按字母输入数字和符号。")
                    Text("上屏后候选栏显示联想词；空闲时点 Mosto 或 ⚙︎ 打开设置。")
                    Text("外观：日光与夜灯，默认跟随系统；也可固定，或选“晚上”在 19:00–6:00 自动开夜灯。")
                }
            }
            .navigationTitle("小鹤双拼键盘")
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
