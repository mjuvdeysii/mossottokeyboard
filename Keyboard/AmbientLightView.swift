import UIKit

/// The light under the keys, in Moss & Otto's two lights. It sits on the system glass, below everything else:
/// 日光 — nothing: the system glass;
/// 夜灯 — only a small pool of gold from Mosto's tail tip in the top-left corner (the glass itself is the system's).
/// Static (no motion), faint, and always under the keys, so it never competes with the legends.
final class AmbientLightView: UIView {
    private let glow = CAGradientLayer()
    /// Holds the glow: it fades with Mosto (the light is his; while candidates fill the strip he is away, so is it).
    private let lamp = CALayer()
    var lampLit = true {
        didSet {
            guard lampLit != oldValue else { return }
            let to: Float = lampLit ? 1 : 0
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = lamp.presentation()?.opacity ?? lamp.opacity
            a.toValue = to
            a.duration = lampLit ? 0.5 : 0.15
            lamp.opacity = to
            lamp.add(a, forKey: "lit")
        }
    }
    /// The tint fades out at the top and bottom edges, so it melts into the system glass around the keyboard
    /// (the glass above the strip and the globe row below) instead of sitting on it as a box.
    private let edgeFade = CAGradientLayer()
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
        lamp.addSublayer(glow)
        layer.addSublayer(lamp)
        edgeFade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        layer.mask = edgeFade
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
        lamp.frame = bounds
        glow.frame = bounds
        edgeFade.frame = bounds
        edgeFade.locations = [0, NSNumber(value: Double(min(0.2, 22 / bounds.height))), NSNumber(value: Double(max(0.8, 1 - 16 / bounds.height))), 1]
        let w = bounds.width, h = bounds.height
        if night {
            let c = Theme.hex(0xFFC45A)   // the gold glow of Mosto's spade
            glow.colors = [c.withAlphaComponent(0.22).cgColor, c.withAlphaComponent(0.07).cgColor, c.withAlphaComponent(0).cgColor]
            glow.locations = [0, 0.4, 1]
            glow.startPoint = CGPoint(x: lampPoint.x / w, y: lampPoint.y / h)
            glow.endPoint = CGPoint(x: (lampPoint.x + 90) / w, y: (lampPoint.y + 60) / h)
        } else {
            glow.colors = nil   // 日光: the system glass, untouched
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
