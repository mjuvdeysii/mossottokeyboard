import Foundation

/// Keeps the keyboard from falling back to the system keyboard again and again. iOS replaces a third-party keyboard
/// with its own whenever the keyboard's process ends — a crash, or iOS ending it for memory while it starts. A launch
/// is marked as started here and as good once the keyboard has been up for a few seconds or is put away normally;
/// after two launches in a row that never got there, the next one starts in a light mode (lexicon and learned words
/// only), and the launch after a good one is normal again.
enum LaunchGuard {
    private static let key = "launchesUnfinished"

    /// Call at launch. True: start light.
    static func begin() -> Bool {
        let d = UserDefaults.standard
        let unfinished = d.integer(forKey: key)
        d.set(unfinished + 1, forKey: key)
        return unfinished >= 2
    }

    /// The keyboard came up and stayed up (or was put away normally).
    static func succeeded() {
        UserDefaults.standard.set(0, forKey: key)
    }
}
