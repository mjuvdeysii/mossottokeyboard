import UIKit

/// Zero-overhead system-glass backdrop host under the keys.
/// Night and day craft now live directly in the sculpted matte vinyl keycaps (zero full-screen CALayer masks or 120Hz breathing animations over iOS Liquid Glass).
final class AmbientLightView: UIView {
    var lampLit = true
    var night = false
    var forcedNight = false { didSet { if forcedNight != oldValue { syncBackdrop() } } }
    var forcedDay = false { didSet { if forcedDay != oldValue { syncBackdrop() } } }
    var lampPoint = CGPoint(x: 28, y: 26)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        syncBackdrop()
    }
    required init?(coder: NSCoder) { fatalError() }

    func syncBackdrop() {
        if forcedDay {
            backgroundColor = Theme.plain ? Theme.hex(0xEBEDF2, 0.92) : Theme.hex(0xEFEBF6, 0.92)
        } else if forcedNight {
            backgroundColor = Theme.plain ? Theme.hex(0x1B1C22, 0.94) : Theme.hex(0x181426, 0.94)
        } else {
            backgroundColor = .clear
        }
    }
}
