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
                    TextField("在这里试打，例如 nihc → 你好", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("用法") {
                    Text("小鹤双拼：每个字两个键，直接用小写字母输入。")
                    Text("空格：上屏首选　回车：上屏字母　删除：逐键回退")
                    Text("首选下方带蓝色下划线 = 已按触点位置自动纠错；第二个候选是未纠错的原文。")
                    Text("候选栏右侧 ⌄ 展开全部候选；空闲时 ⚙︎ 打开设置。")
                    Text("空格键左右拖动可移动光标；长按字母输入数字和符号。")
                }
            }
            .navigationTitle("小鹤双拼键盘")
        }
    }
}
