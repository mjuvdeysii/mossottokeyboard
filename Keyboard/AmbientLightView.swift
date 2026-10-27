import UIKit

/// The light under the keys, in Moss & Otto's two lights. It sits on the system glass, below everything else:
/// 日光 — a breath of warm paper and a soft sunbeam from the top right (the app's daylight comes from there);
/// 夜灯 — the deep night tint and the red glow of Mosto's tail tip in the top-left corner.
/// Static (no motion), faint, and always under the keys, so it never competes with the legends.
final class AmbientLightView: UIView {
    private let glow = CAGradientLayer()
    var night = false { didSet { refresh() } }
    /// Night chosen while the system is light: the glass below is pale, so the tint must be denser.
    var forcedNight = false { didSet { refresh() } }
    /// Where the lamp bead is (container coordinates), so the night glow centres on it.
    var lampPoint = CGPoint(x: 50, y: 22) { didSet { refresh() } }

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
        backgroundColor = night && forcedNight ? Theme.forcedNightTint : Theme.glassTint
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glow.frame = bounds
        let w = bounds.width, h = bounds.height
        if night {
            let c = Theme.hex(0xFFB02E)   // the glow of Mosto's gold spade
            glow.colors = [c.withAlphaComponent(0.22).cgColor, c.withAlphaComponent(0.07).cgColor, c.withAlphaComponent(0).cgColor]
            glow.locations = [0, 0.4, 1]
            glow.startPoint = CGPoint(x: lampPoint.x / w, y: lampPoint.y / h)
            glow.endPoint = CGPoint(x: (lampPoint.x + 150) / w, y: (lampPoint.y + 120) / h)
        } else {
            let c = Theme.hex(0xFFE3B0)
            glow.colors = [c.withAlphaComponent(0.38).cgColor, c.withAlphaComponent(0.10).cgColor, c.withAlphaComponent(0).cgColor]
            glow.locations = [0, 0.45, 1]
            let sun = CGPoint(x: w - 10, y: -20)
            glow.startPoint = CGPoint(x: sun.x / w, y: sun.y / h)
            glow.endPoint = CGPoint(x: (sun.x + 230) / w, y: (sun.y + 190) / h)
        }
        CATransaction.commit()
    }
}
