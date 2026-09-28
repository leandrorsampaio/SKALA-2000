import Darwin
import Foundation

/// What the Mac is doing, every two seconds: how hard its processors and GPU work, what it
/// draws, how hot it runs and how fast its fans turn, how its memory stands, what its
/// disks and network move, and what each seated session's processes cost.
///
/// Everything is read on the Mac, without privileges, and goes nowhere but the desk. The
/// sampling runs on a utility queue; the readings reach the main actor as one batch.
public final class LoadSource: @unchecked Sendable {

    public static let interval: TimeInterval = 2
    public static let ttl = TTL.polled(every: interval)

    private let processes: @MainActor () -> [SessionKey: Int32]
    private let deliver: @MainActor ([Reading]) -> Void
    private let queue = DispatchQueue(label: "com.skala2000.load", qos: .utility)

    /// Everything, for panel F; or, while F is hidden, only the thermal state and memory
    /// pressure panel D's lamps show, which cost next to nothing to read.
    @MainActor public var detailed = false

    // Main actor only.
    private var timer: Timer?
    private var generation = 0
    // `queue` only.
    private var sampler: LoadSampler?

    /// - Parameters:
    ///   - processes: each seated session's process, asked on every pass.
    ///   - deliver: the readings of a pass.
    public init(
        processes: @escaping @MainActor () -> [SessionKey: Int32],
        deliver: @escaping @MainActor ([Reading]) -> Void
    ) {
        self.processes = processes
        self.deliver = deliver
    }

    @MainActor public func start() {
        guard timer == nil else { return }
        generation += 1
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pass() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        pass()
    }

    @MainActor public func stop() {
        timer?.invalidate()
        timer = nil
        generation += 1
        queue.async { [self] in sampler = nil }
    }

    @MainActor private func pass() {
        let detailed = self.detailed
        let sessions = detailed ? processes() : [:]
        let ticket = generation
        queue.async { [self] in
            let sampler = self.sampler ?? LoadSampler()
            self.sampler = sampler
            let readings =
                detailed
                ? sampler.sample(sessions, at: Date()) : LoadSampler.essentials(at: Date())
            DispatchQueue.main.async { [self] in
                MainActor.assumeIsolated {
                    // Stopped, or stopped and started again, since this pass began.
                    guard ticket == generation, timer != nil else { return }
                    deliver(readings)
                }
            }
        }
    }
}

/// One pass after another, remembering each counter's last value so the next can say how
/// fast it moved. Confined to `LoadSource`'s queue.
final class LoadSampler {

    private var cpu: MacProbes.CPUTicks?
    private var disk: (read: UInt64, written: UInt64, at: Date)?
    private var network: (counters: [UInt16: MacProbes.Counters], at: Date)?
    private var free: (bytes: Double?, at: Date)?
    private var heat: (soc: Double?, ssd: Double?, at: Date)?
    private var processes = ProcessMeter()
    private let thermometer = Thermometer()
    private let fans = FanReader()

    /// Room on the disk changes slowly and costs more to ask: once a minute.
    static let freeEvery: TimeInterval = 60
    /// Temperatures change slowly too, and each sensor is a round trip: every ten seconds.
    static let heatEvery: TimeInterval = 10

    /// Whether a figure read at `last` is due again at `moment`: never read, old enough,
    /// or read at a time the clock has since gone back past.
    static func due(_ last: Date?, at moment: Date, every interval: TimeInterval) -> Bool {
        guard let last else { return true }
        return moment.timeIntervalSince(last) >= interval || moment < last
    }

    /// What panel D shows while panel F is hidden.
    static func essentials(at moment: Date) -> [Reading] {
        var out = [
            Reading(
                .machine, .thermalState, .text(MacProbes.thermal(ProcessInfo.processInfo.thermalState)),
                at: moment, ttl: LoadSource.ttl)
        ]
        if let pressure = MacProbes.memoryPressure() {
            out.append(Reading(.machine, .memoryPressure, .text(pressure), at: moment, ttl: LoadSource.ttl))
        }
        return out
    }

    func sample(_ sessions: [SessionKey: Int32], at moment: Date) -> [Reading] {
        var out: [Reading] = []
        func add(_ field: Field, _ value: Value?) {
            if let value { out.append(Reading(.machine, field, value, at: moment, ttl: LoadSource.ttl)) }
        }

        if let ticks = MacProbes.cpuTicks() {
            if let cpu { add(.cpuLoad, MacProbes.load(from: cpu, to: ticks).map(Value.amount)) }
            cpu = ticks
        }
        add(.gpuLoad, MacProbes.gpuLoad().map(Value.amount))
        add(.systemPower, MacProbes.systemPower().map(Value.amount))
        add(.thermalState, .text(MacProbes.thermal(ProcessInfo.processInfo.thermalState)))
        add(.memoryPressure, MacProbes.memoryPressure().map(Value.text))

        add(.memoryTotal, .amount(Double(ProcessInfo.processInfo.physicalMemory)))
        if let memory = MacProbes.memory() {
            add(.memoryUsed, .amount(memory.used))
            add(.memoryWired, .amount(memory.wired))
            add(.memoryCompressed, .amount(memory.compressed))
        }
        add(.swapUsed, MacProbes.swapUsed().map(Value.amount))

        if Self.due(free?.at, at: moment, every: Self.freeEvery) {
            free = (MacProbes.diskFree(), moment)
        }
        add(.diskFree, free?.bytes.map(Value.amount))
        if let bytes = MacProbes.diskBytes() {
            let seconds = disk.map { moment.timeIntervalSince($0.at) } ?? 0
            add(.diskRead, MacProbes.rate(from: disk?.read, to: bytes.read, over: seconds).map(Value.amount))
            add(
                .diskWrite,
                MacProbes.rate(from: disk?.written, to: bytes.written, over: seconds).map(Value.amount))
            disk = (bytes.read, bytes.written, moment)
        }
        if let counters = MacProbes.networkCounters() {
            if let network,
                let traffic = MacProbes.traffic(
                    from: network.counters, to: counters, over: moment.timeIntervalSince(network.at))
            {
                add(.networkIn, .amount(traffic.received))
                add(.networkOut, .amount(traffic.sent))
            }
            network = (counters, moment)
        }

        if Self.due(heat?.at, at: moment, every: Self.heatEvery) {
            let read = thermometer.read()
            heat = (read.soc, read.ssd, moment)
        }
        add(.socTemperature, heat?.soc.map(Value.amount))
        add(.ssdTemperature, heat?.ssd.map(Value.amount))
        add(.batteryTemperature, MacProbes.batteryTemperature().map(Value.amount))
        let speeds = fans.speeds()
        add(.fan1Speed, speeds.first.map(Value.amount))
        add(.fan2Speed, speeds.dropFirst().first.map(Value.amount))

        for (key, sample) in processes.measure(sessions) {
            func session(_ field: Field, _ value: Double) {
                out.append(Reading(.session(key), field, .amount(value), at: moment, ttl: LoadSource.ttl))
            }
            if let share = sample.share { session(.processCPU, share) }
            session(.processMemory, sample.memory)
        }
        return out
    }
}
