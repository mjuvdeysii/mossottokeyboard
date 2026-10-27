import UIKit

/// Mosto in the toolbar's idle corner (where Gboard shows its G). By the rules Moss and Otto follow: mostly still,
/// no words, never in the way of typing — hidden while composing or suggesting. By day an occasional quick blink;
/// at night eyes settled and the bead glowing; with Reduce Motion, no blinking at all.
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
        night = on
        image.image = on ? sleep : day
        schedule()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { timer?.invalidate(); timer = nil } else { schedule() }
    }

    override var isHidden: Bool {
        didSet { if isHidden { timer?.invalidate(); timer = nil } else { schedule() } }
    }

    private func schedule() {
        timer?.invalidate(); timer = nil
        guard !night, !isHidden, window != nil, !UIAccessibility.isReduceMotionEnabled else { return }
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
}
