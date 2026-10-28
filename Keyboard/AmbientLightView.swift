import UIKit

/// The light under the keys, in Moss & Otto's two lights. It sits on the system glass, below everything else:
/// 日光 — lavender milk with a soft studio light from the top left;
/// 夜灯 — the deep night tint and the gold glow of Mosto's tail tip in the top-left corner.
/// Static (no motion), faint, and always under the keys, so it never competes with the legends.
final class AmbientLightView: UIView {
    private let glow = CAGradientLayer()
    var night = false { didSet { refresh() } }
    /// Night chosen while the system is light: the glass below is pale, so the tint must be denser.
    var forcedNight = false { didSet { refresh() } }
    /// Day chosen while the system (or the app) is dark: the glass below is dark, so without a light surface the
    /// white keys would glare on it. A pale frosted sheet makes it read as the light keyboard.
    var forcedDay = false { didSet { refresh() } }
    /// Where the lamp bead is (container coordinates), so the night glow centres on it.
    var lampPoint = CGPoint(x: 28, y: 26) { didSet { refresh() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        glow.type = .radial
        layer.addSublayer(glow)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        refresh()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        refresh()
    }

    private func refresh() {
        backgroundColor = night && forcedNight ? Theme.forcedNightTint
            : !night && forcedDay ? Theme.forcedDayTint : Theme.glassTint
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glow.frame = bounds
        let w = bounds.width, h = bounds.height
        if night {
            let c = Theme.hex(0xFFC45A)   // the gold glow of Mosto's spade
            glow.colors = [c.withAlphaComponent(0.22).cgColor, c.withAlphaComponent(0.07).cgColor, c.withAlphaComponent(0).cgColor]
            glow.locations = [0, 0.4, 1]
            glow.startPoint = CGPoint(x: lampPoint.x / w, y: lampPoint.y / h)
            glow.endPoint = CGPoint(x: (lampPoint.x + 150) / w, y: (lampPoint.y + 120) / h)
        } else {
            // 日光: the soft studio light of Mosto's product shot, from the top left
            let c = UIColor.white
            glow.colors = [c.withAlphaComponent(0.45).cgColor, c.withAlphaComponent(0.12).cgColor, c.withAlphaComponent(0).cgColor]
            glow.locations = [0, 0.45, 1]
            glow.startPoint = CGPoint(x: 0.15, y: 0)
            glow.endPoint = CGPoint(x: 0.85, y: 1.1)
        }
        CATransaction.commit()
        // at night the spade's glow breathes, very slowly (5 s), like a lamp; never with Reduce Motion
        if night && !UIAccessibility.isReduceMotionEnabled {
            if glow.animation(forKey: "breathe") == nil {
                let a = CABasicAnimation(keyPath: "opacity")
                a.fromValue = 1.0
                a.toValue = 0.72
                a.duration = 2.5
                a.autoreverses = true
                a.repeatCount = .infinity
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                glow.add(a, forKey: "breathe")
            }
        } else {
            glow.removeAnimation(forKey: "breathe")
        }
    }
}
