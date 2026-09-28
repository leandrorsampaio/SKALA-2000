import AVFoundation
import AppKit
import ConsoleKit
import DeskArt
import Foundation

/// Four sounds, all short, all dry, mono, at the position of nothing in particular.
///
/// | Sound  | When                                                   | Character            |
/// | ------ | ------------------------------------------------------ | -------------------- |
/// | click  | button contact, down and up                            | 30 ms, 1.8 kHz       |
/// | clunk  | a relay: window change, confirm, detent, key, guard    | 70 ms, 320 Hz        |
/// | tick   | each drum wheel that moves                             | 10 ms, 1.4 kHz       |
/// | buzzer | BUZZER TEST held; the signals below                    | 420 Hz square        |
/// | beep   | LOW CONTEXT comes on                                   | 150 ms, 1.6 kHz sine |
///
/// The signals are the buzzer in patterns: DONE one buzz, WAIT two quick, CMPCT three
/// quick, BLOCK and the desk's own alarms one long. Each plays once, in turn.
///
/// Pre-rendered once into buffers and played through `AVAudioEngine`. The system mute is
/// respected by the output itself; nothing about the console's alarms depends on sound.
@MainActor
public final class DeskSound {

    public enum Effect: CaseIterable, Sendable {
        case click, clunk, tick
        /// The signals.
        case buzzOnce, buzzTwice, buzzThrice, buzzLong, beep
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
    private var outputObserver: NSObjectProtocol?

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

        // 30 ms at 1.8 kHz: the 18 ms tick at 2.6 kHz was there, and too short to be heard.
        buffers[.click] = Self.burst(milliseconds: 30, frequency: 1800, gain: 0.9, format: format)
        buffers[.clunk] = Self.burst(milliseconds: 70, frequency: 320, gain: 0.9, format: format)
        buffers[.tick] = Self.burst(milliseconds: 10, frequency: 1400, gain: 0.25, format: format)
        // A quick buzz is 110 ms on and 90 off; a long one, 1.2 s.
        let buzz: (Double, Double) = (0.11, 0.09)
        buffers[.buzzOnce] = Self.pattern([(0.3, 0)], format: format)
        buffers[.buzzTwice] = Self.pattern([buzz, buzz], format: format)
        buffers[.buzzThrice] = Self.pattern([buzz, buzz, buzz], format: format)
        buffers[.buzzLong] = Self.pattern([(1.2, 0)], format: format)
        buffers[.beep] = Self.beep(format: format)
        buzzerLoop = Self.square(frequency: 420, gain: 0.04, format: format)

        // Headphones in or out, a display's speakers gone: the engine stops itself. An
        // alarm still sounding starts again on whatever the Mac plays through now.
        outputObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.outputChanged() }
        }
    }

    private func outputChanged() {
        guard buzzing else { return }
        buzzing = false
        buzzer(true)
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
        var random = Noise(seed: UInt64(frequency))
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

    /// How long an effect lasts, for playing signals one after another.
    public func duration(_ effect: Effect) -> TimeInterval {
        guard let buffer = buffers[effect] else { return 0 }
        return Double(buffer.frameLength) / format.sampleRate
    }

    /// The buzzer's 420 Hz square, switched on and off: `(on, off)` in seconds for each
    /// buzz. Each edge ramps over 3 ms, as a relay-driven buzzer does, and never clicks.
    nonisolated static func pattern(
        _ buzzes: [(on: Double, off: Double)], frequency: Double = 420, gain: Float = 0.05,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let period = Int((rate / frequency).rounded())
        let total = buzzes.reduce(0) { $0 + $1.on + $1.off }
        let count = AVAudioFrameCount((total * rate).rounded())
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(count) { samples[index] = 0 }
        let ramp = Int(0.003 * rate)
        var start = 0
        for buzz in buzzes {
            let length = Int((buzz.on * rate).rounded())
            for index in 0..<length where start + index < Int(count) {
                let edge = Float(min(index, length - 1 - index, ramp)) / Float(max(ramp, 1))
                let wave: Float = (index % period) < period / 2 ? gain : -gain
                samples[start + index] = wave * min(1, edge)
            }
            start += length + Int((buzz.off * rate).rounded())
        }
        return buffer
    }

    /// LOW CONTEXT's beep: a pure 1.6 kHz tone for 150 ms, soft at both ends. Higher than
    /// the buzzer and round where it is harsh, so the two are never taken for each other.
    nonisolated static func beep(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let count = AVAudioFrameCount(0.15 * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        let samples = buffer.floatChannelData![0]
        let fade = 0.012 * rate
        for index in 0..<Int(count) {
            let t = Double(index)
            let envelope = min(1, t / fade, (Double(count) - t) / fade)
            samples[index] = Float(0.22 * envelope * sin(2 * .pi * 1600 * t / rate))
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
public final class DeskDirector {

    private let sound: DeskSound
    private var previous: ConsoleSnapshot?
    /// When the last signal queued ends: a new one waits its turn.
    private var signalsEnd = Date.distantPast
    public var announce: (String) -> Void = { _ in }
    public var openLog: () -> Void = {}

    public init(sound: DeskSound) {
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
            if let words = DeskWords.alarm(id, selector: snapshot.selector) { announce(words) }
        }

        for (id, face) in snapshot.buttons where face.phase != old.button(id).phase {
            if face.phase == .confirmed {
                sound.play(.clunk)
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .levelChange, performanceTime: .now)
            }
            if face.phase == .noAnswer { sound.play(.clunk) }
        }

        let detents = abs(snapshot.selector - old.selector)
        if detents > 0 {
            sound.play(.clunk)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
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

        // Signals, each once, one after the other so none drowns another.
        var delay = max(0, signalsEnd.timeIntervalSinceNow)
        for signal in Signal.allCases {
            let effect = Self.effect(signal)
            for _ in 0..<max(0, snapshot.cues.count(signal) - old.cues.count(signal)) {
                sound.play(effect, after: delay)
                delay += sound.duration(effect) + 0.35
                signalsEnd = Date().addingTimeInterval(delay)
            }
        }

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

extension DeskDirector {
    nonisolated static func effect(_ signal: Signal) -> DeskSound.Effect {
        switch signal {
        case .done: .buzzOnce
        case .wait: .buzzTwice
        case .compact: .buzzThrice
        case .block: .buzzLong
        case .lowContext, .quota: .beep
        }
    }
}

extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}

/// The same numbers every time, so a relay sounds the same relay.
struct Noise {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func unit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
}
