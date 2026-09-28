import QuartzCore

/// Every timing on the desk, from `10-interaction.md`, as Core Animation.
///
/// The render server interpolates these off the main thread at the display's refresh rate;
/// the app's own thread only starts them.
enum Motion {

    // MARK: Lamps

    static let lampOn: CFTimeInterval = 0.09
    static let lampOff: CFTimeInterval = 0.22

    /// Rise 80 ms, hold to 250, decay 200, dark 50: one 500 ms period, 1 s with Reduce
    /// Motion. Every flashing lamp starts on the same phase origin, so all are in phase.
    static func flash(reduceMotion: Bool) -> CAKeyframeAnimation {
        let period: CFTimeInterval = reduceMotion ? 1.0 : 0.5
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [0, 1, 1, 0, 0]
        animation.keyTimes = [0, 0.16, 0.5, 0.9, 1]
        animation.calculationMode = .linear
        animation.duration = period
        animation.repeatCount = .infinity
        // A whole number of periods since the media clock's origin: whenever a lamp starts
        // flashing, it joins the others in step.
        animation.beginTime = (CACurrentMediaTime() / period).rounded(.down) * period
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        // 30 frames a second, as the reference drew it: a filament looks no different, and
        // every frame costs WindowServer a recomposite (see PERFORMANCE.md).
        animation.preferredFrameRateRange = flashRate
        return animation
    }

    static let flashRate = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 30)

    static let easeIn = CAMediaTimingFunction(name: .easeIn)
    static let easeOut = CAMediaTimingFunction(name: .easeOut)
    static let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)
    static let linear = CAMediaTimingFunction(name: .linear)

    // MARK: Buttons

    /// A cap sinks into its hole, and comes back, in 45 ms.
    static let cap: CFTimeInterval = 0.045

    /// No answer: six blinks of 160 ms, the cap at ×1.5 brightness for the first half.
    static func noAnswerBlink() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        var values: [Float] = []
        var times: [NSNumber] = []
        for step in 0..<12 {
            values.append(step % 2 == 0 ? 1 : 0)
            times.append(NSNumber(value: Double(step) / 12))
        }
        values.append(0)
        times.append(1)
        animation.values = values
        animation.keyTimes = times
        animation.calculationMode = .discrete
        animation.duration = 0.96
        return animation
    }

    // MARK: Springs

    /// SwiftUI's `spring(response:dampingFraction:)`, as a Core Animation spring.
    static func spring(_ keyPath: String, response: Double, damping: Double) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 1
        animation.stiffness = pow(2 * .pi / response, 2)
        animation.damping = 4 * .pi * damping / response
        animation.initialVelocity = 0
        animation.duration = animation.settlingDuration
        return animation
    }

    /// Moving-coil needle: ≈ 700 ms, one overshoot.
    static func needle() -> CASpringAnimation {
        spring("transform.rotation.z", response: 0.55, damping: 0.55)
    }
    /// Needles on power loss fall to the stop in 900 ms.
    static let needleFall: CFTimeInterval = 0.9
    /// The battery's edgewise pointer.
    static func pointer() -> CASpringAnimation {
        spring("position.y", response: 0.45, damping: 0.65)
    }
    /// A plan usage meter's pointer, the same spring along the other axis.
    static func horizontalPointer() -> CASpringAnimation {
        spring("position.x", response: 0.45, damping: 0.65)
    }
    /// A drum wheel: 320 ms with a slight overshoot, each higher wheel 45 ms later.
    static func wheel() -> CASpringAnimation { spring("position.y", response: 0.32, damping: 0.7) }
    static let wheelStagger: CFTimeInterval = 0.045
    /// The selector's detent.
    static func detent() -> CASpringAnimation {
        spring("transform.rotation.z", response: 0.17, damping: 0.45)
    }

    // MARK: Mechanisms

    static let keyTurn: CFTimeInterval = 0.14
    static let backOut = CAMediaTimingFunction(controlPoints: 0.4, 1.6, 0.6, 1)
    static let toggle: CFTimeInterval = 0.1
    static let toggleCurve = CAMediaTimingFunction(controlPoints: 0.7, 0, 0.3, 1)
    static let nixieGhost: CFTimeInterval = 0.06
}
