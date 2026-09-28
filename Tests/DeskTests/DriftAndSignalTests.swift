import AVFoundation
import ConsoleKit
import DeskArt
import QuartzCore
import Testing

@testable import DeskSound
@testable import DeskView

/// SplitMix64, so the random tests give the same numbers every run.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The needles' drift: a fifth of the time, one to three points, each meter on its own.
struct FluctuationTests {

    @Test func aFifthOfTheTimeANeedleDriftsOneToThreePoints() {
        var random = SeededRandom(state: 1972)
        var drifts: [Double] = []
        for _ in 0..<10_000 {
            if let offset = Fluctuation.roll(PK4.apiShareMeter, value: 0.5, using: &random) {
                drifts.append(offset)
            }
        }
        #expect(abs(Double(drifts.count) / 10_000 - 0.2) < 0.02)
        #expect(drifts.allSatisfy { (0.01...0.03).contains(abs($0)) })
        #expect(drifts.contains { $0 > 0 } && drifts.contains { $0 < 0 })
    }

    /// Where a fresh session starts a needle, or on its stop, it stays put.
    @Test func aNeedleAtItsStartOrOnItsStopStaysPut() {
        var random = SeededRandom(state: 7)
        for _ in 0..<1000 {
            #expect(Fluctuation.roll(PK4.contextMeter, value: 1, using: &random) == nil)
            #expect(Fluctuation.roll(PK4.apiShareMeter, value: 0, using: &random) == nil)
            #expect(Fluctuation.roll(PK4.toolShareMeter, value: 0, using: &random) == nil)
            #expect(
                Fluctuation.roll(PK4.contextMeter, value: Needle.leftStop, using: &random) == nil)
            #expect(Fluctuation.roll(PK4.batteryMeter, value: 0.5, using: &random) == nil)
        }
    }

    @Test func aDriftNeverLeavesTheScale() {
        var random = SeededRandom(state: 3)
        for _ in 0..<2000 {
            if let offset = Fluctuation.roll(PK4.contextMeter, value: 0.995, using: &random) {
                #expect(offset < 0)
            }
            if let offset = Fluctuation.roll(PK4.toolShareMeter, value: 0.005, using: &random) {
                #expect(offset > 0)
            }
        }
    }

    /// Each meter rolls for itself: two drift together about 4% of the time, not 20%.
    @Test func theMetersDriftIndependently() {
        var random = SeededRandom(state: 11)
        var both = 0
        for _ in 0..<20_000 {
            let api = Fluctuation.roll(PK4.apiShareMeter, value: 0.4, using: &random) != nil
            let tool = Fluctuation.roll(PK4.toolShareMeter, value: 0.4, using: &random) != nil
            if api && tool { both += 1 }
        }
        #expect(abs(Double(both) / 20_000 - 0.04) < 0.01)
    }

    /// The drift rides on the reading: the needle's own angle is untouched.
    @MainActor
    @Test func aDriftRidesOnTheReadingAndLeavesItAlone() throws {
        let layers = DeskLayers()
        layers.install(DeskLayersTests.art)
        var s = ConsoleSnapshot()
        s.meters[PK4.apiShareMeter] = 0.5
        layers.apply(s, animated: false)
        let needle = try #require(layers.needles[PK4.apiShareMeter])
        let angle = needle.affineTransform()

        layers.fluctuate(PK4.apiShareMeter, by: 0.02)
        let drift = try #require(needle.animation(forKey: "drift") as? CAKeyframeAnimation)
        #expect(drift.isAdditive)
        #expect(drift.duration == Fluctuation.duration)
        #expect(needle.affineTransform() == angle)
        let held = try #require(drift.values?[3] as? CGFloat)
        let expected = DeskLayers.needleAngle(0.52) - DeskLayers.needleAngle(0.5)
        #expect(abs(held - expected) < 1e-9)
    }
}

/// The signals' sounds: the buzzer in patterns, and a beep that is nothing like it.
struct SignalSoundTests {

    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    func seconds(_ buffer: AVAudioPCMBuffer) -> Double {
        Double(buffer.frameLength) / format.sampleRate
    }

    /// Sign changes per second, halved: the pitch.
    func pitch(_ buffer: AVAudioPCMBuffer, from start: Double, to end: Double) -> Double {
        let samples = buffer.floatChannelData![0]
        let first = Int(start * format.sampleRate)
        let last = Int(end * format.sampleRate)
        var crossings = 0
        for index in first + 1..<last where (samples[index] >= 0) != (samples[index - 1] >= 0) {
            crossings += 1
        }
        return Double(crossings) / 2 / (end - start)
    }

    @Test func eachSignalHasItsShape() {
        let quick = (0.11, 0.09)
        #expect(abs(seconds(DeskSound.pattern([(0.3, 0)], format: format)) - 0.3) < 0.001)
        let twice = DeskSound.pattern([quick, quick], format: format)
        #expect(abs(seconds(twice) - 0.4) < 0.001)
        #expect(
            abs(seconds(DeskSound.pattern([quick, quick, quick], format: format)) - 0.6) < 0.001)
        #expect(abs(seconds(DeskSound.pattern([(1.2, 0)], format: format)) - 1.2) < 0.001)

        // Two buzzes with silence between.
        let samples = twice.floatChannelData![0]
        let gap = Int(0.15 * format.sampleRate)
        #expect(samples[gap] == 0)
        #expect(abs(pitch(twice, from: 0.01, to: 0.1) - 420) < 15)
    }

    @Test func theBeepIsShortAndHigh() {
        let beep = DeskSound.beep(format: format)
        #expect(abs(seconds(beep) - 0.15) < 0.001)
        #expect(abs(pitch(beep, from: 0.02, to: 0.13) - 1600) < 20)
    }

    @Test func eachSignalHasItsSound() {
        #expect(DeskDirector.effect(.done) == .buzzOnce)
        #expect(DeskDirector.effect(.wait) == .buzzTwice)
        #expect(DeskDirector.effect(.compact) == .buzzThrice)
        #expect(DeskDirector.effect(.block) == .buzzLong)
        #expect(DeskDirector.effect(.lowContext) == .beep)
    }
}
