import SwiftUI

/// 启用: whether the keyboard is already added (iOS lists added keyboards in the global AppleKeyboards setting), the
/// steps to add it, and a real text field to try it in — with a 收起 button so the system keyboard never stays over
/// the page.
struct EnableScreen: View {
    @Environment(\.scenePhase) private var phase
    @State private var added = KeyboardStatus.isAdded()
    @State private var text = ""
    @FocusState private var typing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                StatusCard(added: added)
                SetupCard()
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "在真实输入框里试", subtitle: added ? "点一下输入框，用 🌐 切到 Mosto键盘" : "添加键盘后，在这里切到 Mosto键盘试试")
                    HStack(alignment: .top, spacing: 8) {
                        TextField("全拼 nihao 或小鹤 nihc → 你好", text: $text, axis: .vertical)
                            .lineLimit(3...8)
                            .focused($typing)
                        if typing {
                            Button { typing = false } label: {
                                Image(systemName: "keyboard.chevron.compact.down").font(.system(size: 17, weight: .semibold))
                            }
                            .accessibilityLabel("收起键盘")
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(UIColor.systemGroupedBackground).onTapGesture { typing = false })
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
    /// The keyboards the user has added, as iOS keeps them in the global defaults (read-only here).
    static func isAdded() -> Bool {
        guard let list = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String] else { return false }
        let ext = Bundle.main.builtInPlugInsURL.flatMap { u in
            (try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil))?.compactMap { Bundle(url: $0)?.bundleIdentifier }
        } ?? []
        return list.contains { ext.contains($0) }
    }
}

private struct StatusCard: View {
    let added: Bool
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: added ? "checkmark.circle.fill" : "keyboard.badge.ellipsis")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(added ? Color.green : mostoTint)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(added ? "Mosto键盘已添加" : "还没有添加 Mosto键盘").font(.headline)
                Text(added ? "打字时按 🌐 切换过来；在“上手”里可以先练一练。" : "照下面三步添加，大约半分钟。")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
    }
}
