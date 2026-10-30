import UIKit

// The judgements made on touches (rounds/R3.md), as plain values driven by samples: the keys and the candidate strip
// read their fingers through them, and the test bench drives the same code with recorded sequences. No timers in
// here; time comes from the samples.

/// One finger at one moment: as a UITouch reads, or as the test bench feeds it.
struct TouchSample {
    enum Phase { case began, moved, ended, cancelled }
    var id: Int
    var phase: Phase
    var point: CGPoint
    var time: CFTimeInterval
}

/// Swipe left off the delete key to clear what is being composed (rounds/R3.md, 方案第 2 项).
///
/// The finger lands on delete (which deletes one key, as always). Arming: within 0.42 s of landing (before held
/// delete starts repeating), at least 44 pt to the left, more than 12 pt past the key's left edge, no more than 30 pt
/// up or down and at least twice as far across as up or down. Back over the key (within 8 pt of its edge) or more
/// than 34 pt up or down disarms. Lifting the finger while armed clears; a cancelled touch never does.
struct ClearSwipe {
    static let reach: CGFloat = 44
    static let beyond: CGFloat = 12
    static let back: CGFloat = 8
    static let rise: CGFloat = 30
    static let window: CFTimeInterval = 0.42

    enum Outcome: Equatable { case none, armed, clear }

    let start: CGPoint
    /// The delete key's left edge (its cap), in the same space as the points.
    let keyLeft: CGFloat
    let began: CFTimeInterval
    private(set) var armed = false

    init(start: CGPoint, keyLeft: CGFloat, time: CFTimeInterval) {
        self.start = start
        self.keyLeft = keyLeft
        self.began = time
    }

    /// The finger is at `p` at time `t`. Returns true when this arms or disarms.
    @discardableResult
    mutating func move(to p: CGPoint, at t: CFTimeInterval) -> Bool {
        let dx = p.x - start.x, dy = p.y - start.y
        let was = armed
        if armed {
            if p.x > keyLeft - Self.back || abs(dy) > Self.rise + 4 { armed = false }
        } else if t - began <= Self.window, dx <= -Self.reach, p.x <= keyLeft - Self.beyond,
                  abs(dy) <= Self.rise, abs(dx) >= 2 * abs(dy) - 1e-6 {
            armed = true
        }
        return armed != was
    }

    /// What the swipe amounts to now (`lifted`: the finger has just come up).
    func outcome(lifted: Bool) -> Outcome { armed ? (lifted ? .clear : .armed) : .none }
}

/// Tap, slide or hold on the candidate strip (rounds/R3.md, 方案第 1 项). A tap selects the candidate under the
/// finger; a finger that moved more than 10 pt, or that the strip's scrolling took over, or that landed to stop a
/// fling, never selects and never holds; a hold of 0.5 s on a candidate (not a suggestion) offers removing it.
struct StripGesture {
    static let slop: CGFloat = 10
    static let holdTime: CFTimeInterval = 0.5

    /// The candidate under the finger as it landed (an index into the full list) and its text then.
    private(set) var index: Int?
    private(set) var text: String?
    private(set) var start: CGPoint = .zero
    private(set) var began: CFTimeInterval = 0
    private(set) var down = false
    /// Slid, scrolled, or stopped a fling: this touch selects nothing.
    private(set) var slid = false
    private(set) var held = false
    private var canHold = false

    mutating func begin(index: Int?, text: String?, at p: CGPoint, time: CFTimeInterval, stoppingScroll: Bool, canHold: Bool) {
        self.index = index
        self.text = text
        start = p
        began = time
        down = true
        slid = stoppingScroll
        held = false
        self.canHold = canHold
    }

    /// Returns true when this move turns the touch into a slide.
    mutating func move(to p: CGPoint) -> Bool {
        guard down, !slid, !held else { return false }
        if hypot(p.x - start.x, p.y - start.y) > Self.slop { slid = true; return true }
        return false
    }

    /// The strip began to scroll under this finger. Returns true when that ended a tap or hold still pending.
    mutating func scrollBegan() -> Bool {
        guard down, !slid, !held else { return false }
        slid = true
        return true
    }

    /// At time `t`: the candidate to offer removing, once, when the finger has rested on it long enough.
    mutating func hold(at t: CFTimeInterval) -> Int? {
        guard down, canHold, !slid, !held, let i = index, t - began >= Self.holdTime else { return nil }
        held = true
        return i
    }

    /// The finger came up over candidate `idx`, whose text is now `currentText`: the candidate to select, if this
    /// was a tap. The word under the finger must still be the one it pressed (a decode arriving mid-tap never gets
    /// a word committed unseen).
    mutating func end(index idx: Int?, currentText: String?) -> Int? {
        defer { down = false }
        guard down, !slid, !held, let i = index, idx == i, let t = text, currentText == t else { return nil }
        return i
    }

    mutating func cancel() { down = false }

    /// The candidate drawn pressed.
    var highlighted: Int? { down && !slid && !held ? index : nil }
}

/// A key's timer (long press, held delete). On the keys it is a run-loop timer; on the test bench it fires when the
/// clock of the fed samples passes it, so a recorded sequence plays out the same on every run. Used on the main
/// thread only (the keys and the test bench); not marked @MainActor so that a run-loop timer's block may fire it.
final class KeyTimer {
    fileprivate(set) var fireAt: CFTimeInterval
    let interval: CFTimeInterval?
    private var action: ((KeyTimer) -> Void)?
    fileprivate var timer: Timer?

    init(fireAt: CFTimeInterval, interval: CFTimeInterval?, action: @escaping (KeyTimer) -> Void) {
        self.fireAt = fireAt
        self.interval = interval
        self.action = action
    }

    var isValid: Bool { action != nil }

    func invalidate() {
        action = nil
        timer?.invalidate()
        timer = nil
    }

    func fire() {
        guard let a = action else { return }
        if let i = interval { fireAt += i } else { action = nil }
        a(self)
    }

    /// On the keys: a run-loop timer in the default mode, or the common modes (it keeps firing while a finger moves).
    static func scheduled(after delay: CFTimeInterval, repeating: CFTimeInterval?, commonModes: Bool,
                          _ action: @escaping (KeyTimer) -> Void) -> KeyTimer {
        let kt = KeyTimer(fireAt: CACurrentMediaTime() + delay, interval: repeating, action: action)
        let t: Timer
        if let r = repeating {
            t = Timer(timeInterval: r, repeats: true) { [weak kt] timer in
                guard let kt, kt.isValid else { timer.invalidate(); return }
                kt.fire()
            }
        } else {
            t = Timer(timeInterval: delay, repeats: false) { [weak kt] _ in kt?.fire() }
        }
        RunLoop.main.add(t, forMode: commonModes ? .common : .default)
        kt.timer = t
        return kt
    }
}
