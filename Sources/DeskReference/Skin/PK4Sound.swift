import AVFoundation
import AppKit
import ConsoleKit
import Foundation

/// Four sounds, all short, all dry, mono, at the position of nothing in particular.
///
/// | Sound  | When                                                   | Character            |
/// | ------ | ------------------------------------------------------ | -------------------- |
/// | click  | button contact, down and up                            | 18 ms, 2.6 kHz       |
/// | clunk  | a relay: window change, confirm, detent, key, guard    | 70 ms, 320 Hz        |
/// | tick   | each drum wheel that moves                             | 10 ms, 1.4 kHz       |
/// | buzzer | any unacknowledged alarm                               | 420 Hz square, looped|
///
/// Pre-rendered once into buffers and played through `AVAudioEngine`. The system mute is
/// respected by the output itself; nothing about the console's alarms depends on sound.
@MainActor
public final class PK4Sound {

    public enum Effect: CaseIterable, Sendable {
        case click, clunk, tick
    }

    public var volume: Float = 0.8 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    public var isEnabled = true {
        didSet { if !isEnabled { buzzer(false) } }
    }

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var voices: [AVAudioPlayerNode] = []
    private var next = 0
    private let buzz = AVAudioPlayerNode()
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private var buzzerLoop: AVAudioPCMBuffer?
    private var buzzing = false
    private var lastClunk = Date.distantPast

    public init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        for _ in 0..<6 {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
            voices.append(voice)
        }
        engine.attach(buzz)
        engine.connect(buzz, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = volume

        buffers[.click] = Self.burst(milliseconds: 18, frequency: 2600, gain: 0.5, format: format)
        buffers[.clunk] = Self.burst(milliseconds: 70, frequency: 320, gain: 0.9, format: format)
        buffers[.tick] = Self.burst(milliseconds: 10, frequency: 1400, gain: 0.25, format: format)
        buzzerLoop = Self.square(frequency: 420, gain: 0.04, format: format)
    }

    public func stop() {
        buzzer(false)
        engine.stop()
    }

    public func play(_ effect: Effect, after delay: TimeInterval = 0) {
        guard isEnabled, let buffer = buffers[effect] else { return }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.play(effect)
            }
            return
        }
        if effect == .clunk {
            // A selector turn relights many lamps at once; more than one clunk inside
            // 100 ms is heard as one.
            guard Date().timeIntervalSince(lastClunk) > 0.1 else { return }
            lastClunk = Date()
        }
        guard start() else { return }
        let voice = voices[next]
        next = (next + 1) % voices.count
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !voice.isPlaying { voice.play() }
    }

    public func buzzer(_ on: Bool) {
        guard on != buzzing else { return }
        buzzing = on && isEnabled
        if buzzing, start(), let loop = buzzerLoop {
            buzz.scheduleBuffer(loop, at: nil, options: [.loops, .interrupts])
            buzz.play()
        } else {
            buzz.stop()
            scheduleIdleStop()
        }
    }

    /// The power-up lamp test's 80 ms of buzzer.
    public func chirp() {
        guard isEnabled, !buzzing, start(), let loop = buzzerLoop else { return }
        buzz.scheduleBuffer(loop, at: nil, options: .interrupts)
        buzz.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, !self.buzzing else { return }
            self.buzz.stop()
        }
    }

    private func start() -> Bool {
        scheduleIdleStop()
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    /// A running output unit renders silence every few milliseconds. Three seconds after
    /// the last sound, with the buzzer quiet, the engine stops; the next sound restarts it.
    private var idleStop: DispatchWorkItem?

    private func scheduleIdleStop() {
        idleStop?.cancel()
        let stop = DispatchWorkItem { [weak self] in
            guard let self, !self.buzzing else { return }
            self.engine.stop()
        }
        idleStop = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: stop)
    }

    // MARK: - Synthesis

    /// A noise burst with a fast decay, band-passed around one frequency: the sound of
    /// metal contacts and relay armatures.
    nonisolated static func burst(
        milliseconds: Double, frequency: Double, gain: Float, format: AVAudioFormat
    ) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let count = AVAudioFrameCount(rate * milliseconds / 1000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        let samples = buffer.floatChannelData![0]

        // RBJ band-pass, constant 0 dB peak gain, Q 1.2.
        let w = 2 * Double.pi * frequency / rate
        let alpha = sin(w) / (2 * 1.2)
        let a0 = 1 + alpha
        let b0 = alpha / a0
        let b2 = -alpha / a0
        let a1 = -2 * cos(w) / a0
        let a2 = (1 - alpha) / a0
        var x1 = 0.0
        var x2 = 0.0
        var y1 = 0.0
        var y2 = 0.0
        var random = SplitMix64(seed: UInt64(frequency))
        for index in 0..<Int(count) {
            let envelope = pow(1 - Double(index) / Double(count), 3)
            let x = (random.unit() * 2 - 1) * envelope
            let y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
            samples[index] = Float(y) * gain * 3
        }
        return buffer
    }

    /// A whole number of periods, so the loop has no seam: at 44.1 kHz, 420 Hz is exactly
    /// 105 samples.
    nonisolated static func square(
        frequency: Double, gain: Float, format: AVAudioFormat
    ) -> AVAudioPCMBuffer {
        let period = Int((format.sampleRate / frequency).rounded())
        let count = AVAudioFrameCount(period * 40)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(count) {
            samples[index] = (index % period) < period / 2 ? gain : -gain
        }
        return buffer
    }
}

/// Hears the desk change and does what the machine does beyond drawing: a relay for every
/// window that changes, a clunk per selector detent, a tick per drum wheel, the buzzer
/// while an alarm is unacknowledged, an announcement when an alarm is raised, and the text
/// log's window when PRINT TEXT asks for it. Buttons click by themselves; this is
/// everything else.
@MainActor
public final class PK4Director {

    private let sound: PK4Sound
    private var previous: ConsoleSnapshot?
    public var announce: (String) -> Void = { _ in }
    public var openLog: () -> Void = {}

    public init(sound: PK4Sound) {
        self.sound = sound
    }

    public func hear(_ snapshot: ConsoleSnapshot) {
        defer { previous = snapshot }
        guard let old = previous else {
            sound.buzzer(snapshot.buzzer)
            return
        }

        let ids = Set(old.lamps.keys).union(snapshot.lamps.keys)
        let changed = ids.filter { old.lamp($0) != snapshot.lamp($0) }
        if !changed.isEmpty { sound.play(.clunk) }

        for id in changed where snapshot.lamp(id) == .flash && old.lamp(id) != .flash {
            if let words = PK4Words.alarm(id, selector: snapshot.selector) { announce(words) }
        }

        for (id, face) in snapshot.buttons where face.phase != old.button(id).phase {
            if face.phase == .confirmed {
                sound.play(.clunk)
                Haptic.level()
            }
            if face.phase == .noAnswer { sound.play(.clunk) }
        }

        let detents = abs(snapshot.selector - old.selector)
        if detents > 0 {
            sound.play(.clunk)
            Haptic.detent()
        }

        if snapshot.guardsOpen != old.guardsOpen {
            let lifted = !snapshot.guardsOpen.subtracting(old.guardsOpen).isEmpty
            if lifted {
                sound.play(.clunk)
            } else {
                // A falling guard lands at 270 ms, bounces, and lands again with a click.
                sound.play(.clunk, after: 0.27)
                sound.play(.click, after: 0.44)
            }
        }
        if snapshot.keysArmed != old.keysArmed { sound.play(.clunk) }
        if snapshot.mains != old.mains { sound.play(.clunk, after: 0.06) }
        if snapshot.cues.relay != old.cues.relay { sound.play(.clunk) }
        if snapshot.cues.chirp != old.cues.chirp { sound.chirp() }
        if snapshot.cues.openLog != old.cues.openLog { openLog() }

        for (id, value) in snapshot.drums {
            let before = String(old.drum(id))
            let after = String(value)
            let wheels = zip(
                before.leftPadded(to: 6).reversed(), after.leftPadded(to: 6).reversed()
            ).filter { $0 != $1 }.count
            for wheel in 0..<wheels { sound.play(.tick, after: Double(wheel) * 0.045) }
        }

        sound.buzzer(snapshot.buzzer)
    }
}

extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}
