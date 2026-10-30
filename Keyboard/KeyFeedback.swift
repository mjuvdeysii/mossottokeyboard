import UIKit
import AudioToolbox

/// Everything the keyboard can be felt or heard for.
enum FeedbackEvent: Equatable {
    /// A key the finger lands on.
    case key(KeyAction)
    /// A candidate, or a 九宫格 syllable in the picker column.
    case candidate
    /// The ↩ chip that puts back what a correction replaced.
    case undoChip
    /// A long press opens the key's other characters; the finger slides from one to the next.
    case altShown, altMoved
    /// The space bar becomes a trackpad; the cursor moves one character.
    case cursorMode, cursorStep
    /// Held delete, once it takes a word at a time: every word.
    case deleteWord
    /// Mosto in the strip, tapped or double-tapped.
    case mosto
}

enum FeedbackKind: Equatable {
    /// A short tap: keys and candidates (`intensity` sets how firm).
    case impact
    /// The ticks of something moving in steps: other characters, cursor, word deletes.
    case selection
    /// Mosto: rounder than any key.
    case soft
}

struct FeedbackResponse: Equatable {
    var kind: FeedbackKind?
    var intensity: CGFloat = 1
    /// One of the system keyboard's click sounds.
    var sound: SystemSoundID?
}

/// The one table of what is felt and heard (rounds/R2.md). Character keys are light, the keys that act on the text
/// or the keyboard are firm, things that move in steps tick, and Mosto is soft. Nothing is felt for what the keyboard
/// does on its own (corrections, suggestions, Mosto idling) — only for what a finger does.
enum FeedbackModel {
    static let letter: CGFloat = 0.6
    static let function: CGFloat = 1.0
    static let mostoIntensity: CGFloat = 0.7

    static func response(for event: FeedbackEvent) -> FeedbackResponse {
        switch event {
        case .key(let action):
            switch action {
            case .char, .t9:
                return FeedbackResponse(kind: .impact, intensity: letter, sound: 1104)
            case .space:
                return FeedbackResponse(kind: .impact, intensity: function, sound: 1104)
            case .delete, .deleteWord:
                return FeedbackResponse(kind: .impact, intensity: function, sound: 1155)
            case .shift, .ret, .globe, .settings, .page, .toggleLanguage, .clearInput, .emoji:
                return FeedbackResponse(kind: .impact, intensity: function, sound: 1156)
            }
        case .candidate:
            return FeedbackResponse(kind: .impact, intensity: letter, sound: 1104)
        case .undoChip:
            return FeedbackResponse(kind: .impact, intensity: function, sound: 1155)
        case .altShown, .altMoved, .cursorStep, .deleteWord:
            return FeedbackResponse(kind: .selection, intensity: 1, sound: nil)
        case .cursorMode:
            return FeedbackResponse(kind: .impact, intensity: function, sound: nil)
        case .mosto:
            return FeedbackResponse(kind: .soft, intensity: mostoIntensity, sound: 1156)
        }
    }
}

/// Plays a response. The keyboard uses the system's generators; the test bench records what would have been played.
protocol FeedbackPlayer: AnyObject {
    func prepare()
    func play(_ kind: FeedbackKind, intensity: CGFloat, at point: CGPoint?)
    func play(sound: SystemSoundID)
    /// How many haptics went out this session (the settings' 诊断 line).
    var played: Int { get }
}

/// The system's feedback generators, attached to the keyboard view where the system allows it (iOS 17.5: a generator
/// is an interaction of a view, and plays where the finger is); before that, or while the view is off screen, the
/// plain generators — a tap is never dropped silently.
final class SystemFeedbackPlayer: FeedbackPlayer {
    private weak var view: UIView?
    private var light: UIImpactFeedbackGenerator
    private var soft: UIImpactFeedbackGenerator
    private var tick: UISelectionFeedbackGenerator
    private let plainLight = UIImpactFeedbackGenerator(style: .light)
    private let plainSoft = UIImpactFeedbackGenerator(style: .soft)
    private let plainTick = UISelectionFeedbackGenerator()
    private(set) var played = 0
    /// Click sounds are started off the main thread: AudioServicesPlaySystemSound can block for a few milliseconds
    /// (most of all on the first sound after the keyboard appears), and the key press must not wait for it.
    private static let soundQueue = DispatchQueue(label: "mosto.keysound", qos: .userInteractive)

    init(view: UIView) {
        self.view = view
        if #available(iOS 17.5, *) {
            light = UIImpactFeedbackGenerator(style: .light, view: view)
            soft = UIImpactFeedbackGenerator(style: .soft, view: view)
            tick = UISelectionFeedbackGenerator(view: view)
        } else {
            light = UIImpactFeedbackGenerator(style: .light)
            soft = UIImpactFeedbackGenerator(style: .soft)
            tick = UISelectionFeedbackGenerator()
        }
    }

    private var attached: Bool { view?.window != nil }

    func prepare() {
        if attached { light.prepare(); tick.prepare() } else { plainLight.prepare(); plainTick.prepare() }
    }

    func play(_ kind: FeedbackKind, intensity: CGFloat, at point: CGPoint?) {
        played += 1
        let onView = attached
        switch kind {
        case .impact:
            let g = onView ? light : plainLight
            if #available(iOS 17.5, *), onView, let point { g.impactOccurred(intensity: intensity, at: point) }
            else { g.impactOccurred(intensity: intensity) }
            g.prepare()
        case .soft:
            let g = onView ? soft : plainSoft
            if #available(iOS 17.5, *), onView, let point { g.impactOccurred(intensity: intensity, at: point) }
            else { g.impactOccurred(intensity: intensity) }
        case .selection:
            let g = onView ? tick : plainTick
            if #available(iOS 17.5, *), onView, let point { g.selectionChanged(at: point) }
            else { g.selectionChanged() }
            g.prepare()
        }
    }

    func play(sound: SystemSoundID) {
        Self.soundQueue.async { AudioServicesPlaySystemSound(sound) }
    }
}

/// The test bench's player: what would have been felt and heard, in order.
final class RecordingFeedbackPlayer: FeedbackPlayer {
    struct Entry: Equatable { var kind: FeedbackKind; var intensity: CGFloat }
    private(set) var haptics: [Entry] = []
    private(set) var sounds: [SystemSoundID] = []
    var played: Int { haptics.count }
    func prepare() {}
    func play(_ kind: FeedbackKind, intensity: CGFloat, at point: CGPoint?) { haptics.append(Entry(kind: kind, intensity: intensity)) }
    func play(sound: SystemSoundID) { sounds.append(sound) }
    func clear() { haptics = []; sounds = [] }
}
