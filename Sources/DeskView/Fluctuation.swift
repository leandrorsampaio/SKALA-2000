import ConsoleKit
import QuartzCore

/// A moving-coil needle is never quite still. About a fifth of the time it drifts one to
/// three points off its reading and settles back. Only a needle with something to measure
/// drifts: one on its stop, or where a fresh session starts it (all context left, no API
/// or tool time yet), stays put.
///
/// Every roll is its own, per meter and per second, so no two needles move together.
enum Fluctuation {

    /// The share of seconds in which a needle drifts.
    static let chance = 0.2
    /// How far, as a fraction of the scale: one to three points.
    static let size = 0.01...0.03
    /// Out, a little past, and back: one second, the time between rolls.
    static let duration: CFTimeInterval = 1

    /// The drift for `meter` reading `value` this time, or `nil` for none.
    static func roll<R: RandomNumberGenerator>(
        _ meter: InstrumentID, value: Double, using random: inout R
    ) -> Double? {
        guard moves(meter, at: value), Double.random(in: 0..<1, using: &random) < chance else {
            return nil
        }
        let points = Double.random(in: size, using: &random)
        var offset = Bool.random(using: &random) ? points : -points
        // Never past the end of the scale: at 99% it drifts down.
        if !(0...1).contains(value + offset) { offset = -offset }
        return offset
    }

    /// Whether a needle reading `value` drifts at all.
    static func moves(_ meter: InstrumentID, at value: Double) -> Bool {
        // Below zero is the stop: nothing to measure, or MAINS off.
        guard value >= 0 else { return false }
        switch meter {
        case PK4.contextMeter: return value < 1
        case PK4.apiShareMeter, PK4.toolShareMeter: return value > 0
        default: return false
        }
    }
}

extension DeskLayers {

    /// Drifts a needle `offset` off its reading and back, on top of what it shows: the
    /// reading is untouched, and a new one still swings in as ever.
    func fluctuate(_ id: InstrumentID, by offset: Double, after delay: CFTimeInterval = 0) {
        guard let needle = needles[id], let value = shownMeter(id) else { return }
        let delta = DeskLayers.needleAngle(value + offset) - DeskLayers.needleAngle(value)
        let drift = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        drift.isAdditive = true
        drift.values = [0, delta * 1.15, delta * 0.95, delta, 0]
        drift.keyTimes = [0, 0.18, 0.3, 0.72, 1]
        drift.timingFunctions = [Motion.easeOut, Motion.easeInOut, Motion.linear, Motion.easeInOut]
        drift.duration = Fluctuation.duration
        drift.beginTime = CACurrentMediaTime() + delay
        drift.fillMode = .backwards
        // A needle's drift is slow: 30 frames a second, like the flash, halves what every
        // frame costs WindowServer.
        drift.preferredFrameRateRange = Motion.flashRate
        needle.add(drift, forKey: "drift")
    }
}

extension DeskView {

    /// Once a second while the desk can be seen, each meter rolls for a drift of its own,
    /// starting somewhere in the second so that none keeps time with another.
    func startDrift() {
        guard driftTimer == nil else { return }
        let timer = Timer(timeInterval: Fluctuation.duration, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.drift() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        driftTimer = timer
    }

    func stopDrift() {
        driftTimer?.invalidate()
        driftTimer = nil
    }

    func drift() {
        guard snapshot.mains, !layers.reduceMotion, layers.art != nil,
            window?.occlusionState.contains(.visible) == true
        else { return }
        for id in PK4.meters where layers.needles[id]?.animation(forKey: "drift") == nil {
            guard let offset = Fluctuation.roll(id, value: snapshot.meter(id), using: &random)
            else { continue }
            layers.fluctuate(id, by: offset, after: Double.random(in: 0..<0.5, using: &random))
        }
    }
}
