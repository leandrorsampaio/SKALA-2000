import ConsoleKit
import DeskArt
import QuartzCore
import Testing

@testable import DeskView

/// Each instrument's layers after a snapshot: what shows, and how it moves there. The
/// timings are the design system's (`10-interaction.md`).
@MainActor
struct DeskLayersTests {

    static let art = ArtSet.render(style: ArtStyle(), scale: 0.5)

    func layers(reduceMotion: Bool = false) -> DeskLayers {
        let layers = DeskLayers()
        layers.reduceMotion = reduceMotion
        layers.install(Self.art)
        layers.apply(ConsoleSnapshot(), animated: false)
        return layers
    }

    func angle(_ layer: CALayer) -> Double {
        Double(atan2(layer.affineTransform().b, layer.affineTransform().a)) * 180 / .pi
    }

    @Test func aLampComesOnIn90MillisecondsAndGoesOffIn220() throws {
        let layers = layers()
        var s = ConsoleSnapshot()
        let id = PK4.annunciator(.busy, slot: 2)
        s.lamps[id] = .on
        layers.apply(s, animated: true)
        let lamp = try #require(layers.lamps[id])
        #expect(lamp.opacity == 1)
        #expect((lamp.animation(forKey: "fade") as? CABasicAnimation)?.duration == 0.09)
        s.lamps[id] = nil
        layers.apply(s, animated: true)
        #expect(lamp.opacity == 0)
        #expect((lamp.animation(forKey: "fade") as? CABasicAnimation)?.duration == 0.22)
    }

    @Test func flashingLampsShareOnePhase() throws {
        let layers = layers()
        var s = ConsoleSnapshot()
        s.lamps[PK4.annunciator(.wait, slot: 1)] = .flash
        layers.apply(s, animated: true)
        s.lamps[PK4.annunciator(.block, slot: 3)] = .flash
        layers.apply(s, animated: true)
        let a = try #require(
            layers.lamps[PK4.annunciator(.wait, slot: 1)]?.animation(forKey: "flash"))
        let b = try #require(
            layers.lamps[PK4.annunciator(.block, slot: 3)]?.animation(forKey: "flash"))
        #expect(a.duration == 0.5 && b.duration == 0.5)
        // Both begin on a whole number of periods, so they are in step.
        for begin in [a.beginTime, b.beginTime] {
            #expect(abs(begin / 0.5 - (begin / 0.5).rounded()) < 1e-9)
        }
        let keyframes = try #require(a as? CAKeyframeAnimation)
        #expect(keyframes.keyTimes == [0, 0.16, 0.5, 0.9, 1])
    }

    @Test func reduceMotionSlowsTheFlashToOneHertz() throws {
        let layers = layers(reduceMotion: true)
        var s = ConsoleSnapshot()
        s.lamps[PK4.warning(.stale)] = .flash
        layers.apply(s, animated: true)
        #expect(layers.lamps[PK4.warning(.stale)]?.animation(forKey: "flash")?.duration == 1.0)
    }

    @Test func aPressedCapSinksAndDarkensIn45Milliseconds() throws {
        let layers = layers()
        var s = ConsoleSnapshot()
        s.buttons[PK4.acknowledge] = ButtonFace(capDown: true)
        layers.apply(s, animated: true)
        let cap = try #require(layers.caps[PK4.acknowledge])
        #expect(abs(cap.body.affineTransform().a - 0.89) < 1e-6)
        #expect(cap.faceDown.opacity == 1 && cap.face.opacity == 0)
        #expect(cap.hole.opacity == 1 && cap.shadow.opacity == 0)
        #expect((cap.body.animation(forKey: "press") as? CABasicAnimation)?.duration == 0.045)
    }

    @Test func aHeldCapIsDownBeforeTheModelSaysSo() throws {
        let layers = layers()
        layers.held.insert(PK4.function(3))
        layers.apply(ConsoleSnapshot(), animated: true)
        let cap = try #require(layers.caps[PK4.function(3)])
        #expect(abs(cap.body.affineTransform().a - 0.89) < 1e-6)
    }

    @Test func noAnswerBlinksSixTimes() throws {
        let layers = layers()
        var s = ConsoleSnapshot()
        s.buttons[PK4.function(1)] = ButtonFace(phase: .noAnswer)
        layers.apply(s, animated: true)
        let blink = try #require(
            layers.caps[PK4.function(1)]?.bright.animation(forKey: "blink") as? CAKeyframeAnimation)
        #expect(blink.duration == 0.96)
        #expect(blink.calculationMode == .discrete)
        #expect((blink.values as? [Float])?.filter { $0 == 1 }.count == 6)
    }

    @Test func aConfirmedCapLights() throws {
        let layers = layers()
        var s = ConsoleSnapshot()
        s.buttons[PK4.silence] = ButtonFace(lamp: .on, phase: .confirmed)
        layers.apply(s, animated: true)
        let cap = try #require(layers.caps[PK4.silence])
        #expect(cap.lit.opacity == 1 && cap.glow.opacity == 1)
    }

    @Test func theGuardLiftsTo112AndFallsWithTwoBounces() throws {
        let layers = layers()
        var s = ConsoleSnapshot()
        s.guardsOpen = [PK4.f9]
        layers.apply(s, animated: true)
        let g = try #require(layers.guards[PK4.f9])
        let lift = try #require(g.flap.animation(forKey: "swing") as? CAKeyframeAnimation)
        #expect(lift.duration == 0.26)
        #expect(lift.values?.count == 3)
        s.guardsOpen = []
        layers.apply(s, animated: true)
        let fall = try #require(g.flap.animation(forKey: "swing") as? CAKeyframeAnimation)
        #expect(abs(fall.duration - 0.52) < 1e-9)
        #expect(fall.values?.count == 6)
    }

    @Test func theKeyTurnsNinetyDegrees() throws {
        let layers = layers()
        var s = ConsoleSnapshot()
        s.keysArmed = [PK4.f10]
        layers.apply(s, animated: true)
        let key = try #require(layers.keys[PK4.f10])
        #expect(abs(angle(key) - 90) < 0.01)
        #expect((key.animation(forKey: "turn") as? CABasicAnimation)?.duration == 0.14)
    }

    @Test func theSelectorTurnsSixtyDegreesADetent() {
        let layers = layers()
        #expect(abs(angle(layers.knob) - -90) < 0.01)
        var s = ConsoleSnapshot()
        s.selector = 3
        layers.apply(s, animated: true)
        #expect(abs(angle(layers.knob) - 30) < 0.01)
        #expect(layers.knob.animation(forKey: "detent") != nil)
    }

    @Test func mainsOffThrowsTheLeverAndDropsTheNeedles() throws {
        let layers = layers()
        var s = ConsoleSnapshot()
        s.meters[PK4.contextMeter] = 0.7
        layers.apply(s, animated: true)
        let needle = try #require(layers.needles[PK4.contextMeter])
        #expect(abs(angle(needle) - (-60 + 120 * 0.7)) < 0.01)
        #expect(needle.animation(forKey: "swing") is CASpringAnimation)
        s.mains = false
        s.meters = [:]
        layers.apply(s, animated: true)
        #expect(layers.lever.affineTransform().d == -1)
        #expect(abs(angle(needle) - -60) < 0.01)
        let fall = try #require(needle.animation(forKey: "swing") as? CABasicAnimation)
        #expect(fall.duration == 0.9)
    }

    @Test func aMeterWithNothingToMeasureRestsOnZero() throws {
        let layers = layers()
        var s = ConsoleSnapshot()
        s.meters[PK4.apiShareMeter] = Needle.leftStop
        layers.apply(s, animated: false)
        #expect(abs(angle(try #require(layers.needles[PK4.apiShareMeter])) - -60) < 0.01)
    }

    @Test func aNixieLeavesAGhostOfItsOldDigit() throws {
        let layers = layers()
        var s = ConsoleSnapshot()
        s.nixies[PK4.queueDepth] = "000004"
        layers.apply(s, animated: true)
        s.nixies[PK4.queueDepth] = "000005"
        layers.apply(s, animated: true)
        let last = try #require(layers.tubes[PK4.queueDepth]?.last)
        let ghost = try #require(last.ghost.animation(forKey: "ghost") as? CABasicAnimation)
        #expect(ghost.duration == 0.06)
        #expect(ghost.fromValue as? Double == 0.35)
        #expect(last.glyph.contents != nil)
    }

    @Test func drumWheelsRollForwardOnlyAndRippleLeftward() throws {
        let layers = layers()
        var s = ConsoleSnapshot()
        s.drums[PK4.totalCost] = 19
        layers.apply(s, animated: false)
        s.drums[PK4.totalCost] = 20
        layers.apply(s, animated: true)
        let wheels = try #require(layers.wheels[PK4.totalCost])
        let units = wheels[5]
        let tens = wheels[4]
        // 9 → 0 rolls on to the strip's second 0, not back to its first.
        let roll = try #require(units.strip.animation(forKey: "roll") as? CASpringAnimation)
        #expect((roll.toValue as? CGFloat).map { $0 < (roll.fromValue as? CGFloat ?? 0) } == true)
        #expect(units.strip.position.y == -10 * units.rect.height)
        let carry = try #require(tens.strip.animation(forKey: "roll"))
        #expect(carry.beginTime > roll.beginTime)
    }

    @Test func theBuzzerTremblesWhileItSounds() {
        let layers = layers()
        var s = ConsoleSnapshot()
        s.buzzer = true
        layers.apply(s, animated: true)
        #expect(layers.buzzer.animation(forKey: "shake")?.duration == 0.02)
        s.buzzer = false
        layers.apply(s, animated: true)
        #expect(layers.buzzer.animation(forKey: "shake") == nil)
    }

    @Test func reduceMotionJumpsWhatWouldSwing() throws {
        let layers = layers(reduceMotion: true)
        var s = ConsoleSnapshot()
        s.meters[PK4.toolShareMeter] = 0.5
        s.guardsOpen = [PK4.f8]
        s.selector = 2
        layers.apply(s, animated: true)
        #expect(layers.needles[PK4.toolShareMeter]?.animation(forKey: "swing") == nil)
        #expect(layers.guards[PK4.f8]?.flap.animation(forKey: "swing") == nil)
        #expect(layers.knob.animation(forKey: "detent") == nil)
    }
}
