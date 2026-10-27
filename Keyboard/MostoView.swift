import UIKit

/// Mosto, the keyboard's little demon king (小魔王, after 魔头), in the toolbar's idle corner (where Gboard shows its G):
/// mostly still, no words, never in the way of typing — hidden while composing or suggesting. By day an occasional
/// quick blink; at night a scheming squint, gold eyes and the spade on its tail glowing — and, left alone for half a
/// minute, his one slow yawn (as in the stories: the half of him that only wants to rest; the fang shows, the wings
/// droop), once per quiet stretch. With Reduce Motion, no blinking and no yawn.
final class MostoView: UIView {
    private let image = UIImageView()
    private var timer: Timer?
    private var night = false

    private static func load(_ name: String) -> UIImage? {
        UIImage(named: name, in: Bundle(for: MostoView.self), with: nil)
    }
    private let day = MostoView.load("mosto_day")
    private let blink = MostoView.load("mosto_blink")
    private let sleep = MostoView.load("mosto_night")
    private let yawn = MostoView.load("mosto_yawn")
    /// One yawn per quiet stretch: reset when he is hidden (typing) and shown again.
    private var yawned = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityLabel = "Mosto，键盘设置"
        accessibilityTraits = .button
        image.contentMode = .scaleAspectFit
        addSubview(image)
        image.image = day
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        image.frame = bounds
    }

    func setNight(_ on: Bool) {
        if on != night { yawned = false }
        night = on
        image.image = on ? sleep : day
        schedule()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { timer?.invalidate(); timer = nil } else { schedule() }
    }

    override var isHidden: Bool {
        didSet {
            if isHidden { timer?.invalidate(); timer = nil; yawned = false; if night { image.image = sleep } } else { schedule() }
        }
    }

    private func schedule() {
        timer?.invalidate(); timer = nil
        guard !isHidden, window != nil, !UIAccessibility.isReduceMotionEnabled else { return }
        if night {
            guard !yawned else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in self?.slowYawn() }
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 5...9), repeats: false) { [weak self] _ in
            guard let self, !self.night else { return }
            self.image.image = self.blink
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) { [weak self] in
                guard let self else { return }
                if !self.night { self.image.image = self.day }
                self.schedule()
            }
        }
    }

    /// Snapshot support: the yawn, at once.
    func demoYawn() { image.image = yawn }

    /// Slowly into the yawn (1.2 s), held about seven seconds, slowly out again.
    private func slowYawn() {
        guard night, !isHidden, let yawn else { return }
        yawned = true
        UIView.transition(with: image, duration: 1.2, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.image.image = yawn
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.2 + 7, repeats: false) { [weak self] _ in
            guard let self, self.night else { return }
            UIView.transition(with: self.image, duration: 1.2, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.image.image = self.sleep
            }
        }
    }
}
