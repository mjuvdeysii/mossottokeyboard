import UIKit

/// The ticks felt while the space bar drags the cursor (rounds/R4.md, 方案第 2 项). The cursor's steps stay as they
/// were (9 / 5.5 / 3.5 pt a character by the finger's speed); the ticks follow the finger's distance instead of the
/// characters, so a fast drag no longer turns into a buzz:
/// - one tick for every 27 pt the finger travels while the cursor moves (the remainder carries over);
/// - never two ticks within 100 ms (at most 10 a second);
/// - after the cursor has stood still for 250 ms, or when it turns back, the first character it passes ticks at once
///   (still at least 100 ms after the last tick) and the distance starts again from zero — a one-character nudge
///   is felt;
/// - at the start or end of the text, where the cursor passes nothing, no tick and no distance.
/// A plain value driven by touch samples: no timers, time comes from the samples, so the test bench measures the
/// same rhythm a finger gets.
struct CursorRhythm {
    static let distance: CGFloat = 27
    static let minInterval: CFTimeInterval = 0.100
    static let pause: CFTimeInterval = 0.250
    /// Sample times 100 ms apart on paper can differ from it in the last bits of a Double.
    static let slack: CFTimeInterval = 0.0005

    /// Distance the finger travelled since the last tick (or since the cursor stopped or turned).
    private var travelled: CGFloat = 0
    private var lastTick: CFTimeInterval?
    /// When the cursor last passed a character (or cursor mode began).
    private var lastPass: CFTimeInterval = 0
    /// The way the cursor was last asked to go: +1 right, −1 left, 0 not yet.
    private var direction = 0
    /// The cursor has turned back and not yet passed a character the new way.
    private var turned = false
    /// The cursor was asked to go on and passed nothing: it is at the start or end of the text.
    private(set) var atEnd = false

    /// Cursor mode begins (the `.cursorMode` tap is felt then): the distance counts from zero.
    mutating func begin(at time: CFTimeInterval) {
        travelled = 0
        lastTick = nil
        lastPass = time
        direction = 0
        turned = false
        atEnd = false
    }

    /// One touch sample while dragging: the finger moved `dx`; the cursor was asked to go `steps` characters (signed,
    /// + to the right) and passed `passed` visible ones. Returns whether this sample ticks.
    mutating func feed(dx: CGFloat, steps: Int, passed: Int, at time: CFTimeInterval) -> Bool {
        let dir = steps > 0 ? 1 : (steps < 0 ? -1 : 0)
        if dir != 0 {
            if direction != 0 && dir != direction { turned = true }
            direction = dir
            atEnd = passed == 0
        }
        // at an end: nothing passed, nothing felt, no distance counted
        if atEnd { return false }
        travelled += abs(dx)
        guard passed > 0 else { return false }
        let fresh = turned || time - lastPass >= Self.pause - Self.slack
        lastPass = time
        turned = false
        let spaced: Bool
        if let last = lastTick { spaced = time - last >= Self.minInterval - Self.slack } else { spaced = true }
        if fresh {
            travelled = 0
            if !spaced { return false }
            lastTick = time
            return true
        }
        if travelled < Self.distance || !spaced { return false }
        // the remainder carries over; a fast drag held back by the 100 ms owes at most one tick
        travelled = min(travelled - Self.distance, Self.distance)
        lastTick = time
        return true
    }
}
