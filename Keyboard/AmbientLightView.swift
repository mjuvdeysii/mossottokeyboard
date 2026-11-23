import UIKit

/// Zero-overhead system-glass backdrop host under the keys.
/// Night and day craft now live directly in the sculpted matte vinyl keycaps (zero full-screen CALayer masks or 120Hz breathing animations over iOS Liquid Glass).
final class AmbientLightView: UIView {
    var lampLit = true
    var night = false
    var forcedNight = false
    var forcedDay = false
    var lampPoint = CGPoint(x: 28, y: 26)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }
}
