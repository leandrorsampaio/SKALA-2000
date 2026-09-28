import Darwin
import Foundation
import Testing

@testable import TelemetryKit

/// The arithmetic on the Mac's counters, on figures made up for it; and one real pass on
/// whatever Mac runs the tests, held only to what every Mac has.
@Suite struct LoadSourceTests {

    @Test func theLoadIsTheShareOfTicksSpentBusy() {
        let before = MacProbes.CPUTicks(busy: 1000, total: 4000)
        let after = MacProbes.CPUTicks(busy: 1300, total: 5000)
        #expect(MacProbes.load(from: before, to: after) == 0.3)
        // A counter that went backwards is a wrap, not a reading.
        #expect(MacProbes.load(from: after, to: before) == nil)
        #expect(MacProbes.load(from: before, to: before) == nil)
    }

    @Test func aRateNeedsTwoReadingsAndACounterThatOnlyGrows() {
        #expect(MacProbes.rate(from: nil, to: 500, over: 2) == nil)
        #expect(MacProbes.rate(from: 1_000, to: 5_000, over: 2) == 2_000)
        #expect(MacProbes.rate(from: 5_000, to: 1_000, over: 2) == nil)
        #expect(MacProbes.rate(from: 1_000, to: 5_000, over: 0) == nil)
    }

    /// An app sees only the low 32 bits of each interface's count, so a count that went
    /// back has wrapped; one too large to have wrapped was reset, and adds nothing.
    @Test func networkTrafficAllowsForEachCounterWrapping() throws {
        let old: [UInt16: MacProbes.Counters] = [
            14: .init(received: 4_294_967_000, sent: 1_000), 16: .init(received: 10, sent: 10),
        ]
        let new: [UInt16: MacProbes.Counters] = [
            14: .init(received: 704, sent: 3_000), 16: .init(received: 1_010, sent: 10),
            // An interface that just appeared has nothing to compare with.
            17: .init(received: 9_999, sent: 9_999),
        ]
        let traffic = try #require(MacProbes.traffic(from: old, to: new, over: 2))
        #expect(traffic.received == Double(1_000 + 1_000) / 2)
        #expect(traffic.sent == 1_000)
        #expect(MacProbes.delta(from: 5_000_000_000, to: 10) == nil)
        #expect(MacProbes.traffic(from: old, to: new, over: 0) == nil)
    }

    /// As Activity Monitor divides it: app memory, wired and compressed are used; a page an
    /// app has said may go is not.
    @Test func usedMemoryIsAppMemoryWiredAndCompressed() {
        let memory = MacProbes.memory(
            anonymous: 1000, purgeable: 200, wired: 300, compressed: 100, pageSize: 16_384)
        #expect(memory.used == Double(800 + 300 + 100) * 16_384)
        #expect(memory.wired == 300 * 16_384)
        #expect(memory.compressed == 100 * 16_384)
        // More purgeable than anonymous, as a moment's counts can be, is no negative memory.
        let odd = MacProbes.memory(
            anonymous: 10, purgeable: 20, wired: 0, compressed: 0, pageSize: 16_384)
        #expect(odd.used == 0)
    }

    @Test func theKernelsLevelsBecomeWords() {
        #expect(MacProbes.pressure(level: 1) == "normal")
        #expect(MacProbes.pressure(level: 2) == "warning")
        #expect(MacProbes.pressure(level: 4) == "critical")
        #expect(MacProbes.pressure(level: 3) == nil)
        #expect(MacProbes.thermal(.nominal) == "nominal")
        #expect(MacProbes.thermal(.serious) == "serious")
    }

    /// The die's sensors and the SSD's, by Apple Silicon's names; the rest are not
    /// temperatures of anything the operator knows, and a reading of −9203 °C is a sensor
    /// not reading.
    @Test func theHottestSensorOfEachKindIsTheReading() {
        #expect(Thermometer.group("PMU tdie6") == .soc)
        #expect(Thermometer.group("NAND CH0 temp") == .ssd)
        #expect(Thermometer.group("PMU tdev1") == nil)
        #expect(Thermometer.group("PMU tcal") == nil)
        #expect(Thermometer.group("gas gauge battery") == nil)
        let heat = Thermometer.hottest([
            (.soc, 36.4), (.soc, 41.2), (.soc, -9202.9), (.ssd, 32), (.soc, 38),
        ])
        #expect(heat.soc == 41.2)
        #expect(heat.ssd == 32)
        #expect(Thermometer.hottest([]).soc == nil)
    }

    @Test func fanSpeedsAreReadInEitherOfTheSMCsShapes() {
        let float = FanReader.fourCC("flt ")
        let bits = Float(2317).bitPattern
        let bytes = [
            UInt8(bits & 0xff), UInt8(bits >> 8 & 0xff), UInt8(bits >> 16 & 0xff),
            UInt8(bits >> 24),
        ]
        #expect(FanReader.number((float, bytes)) == 2317)
        // Intel: fixed point, two bits after the point, most significant byte first.
        #expect(FanReader.number((FanReader.fourCC("fpe2"), [0x24, 0x34])) == 2317)
        #expect(FanReader.number((FanReader.fourCC("ui8 "), [2])) == nil)
        #expect(FanReader.integer((FanReader.fourCC("ui8 "), [2])) == 2)
        #expect(FanReader.fourCC("FNum") == 0x464E_756D)
    }

    @Test func slowFiguresAreAskedForOnlyWhenDue() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(LoadSampler.due(nil, at: start, every: 10))
        #expect(!LoadSampler.due(start, at: start.addingTimeInterval(9), every: 10))
        #expect(LoadSampler.due(start, at: start.addingTimeInterval(10), every: 10))
        // A clock set back is no reason to wait for it to catch up.
        #expect(LoadSampler.due(start, at: start.addingTimeInterval(-60), every: 10))
    }

    @Test func aSessionsShareIsOfEveryCore() {
        // Two seconds of CPU over two seconds of wall time on four cores: a quarter.
        #expect(ProcessMeter.share(2_000_000_000, over: 2_000_000_000, cores: 4) == 0.25)
        #expect(ProcessMeter.share(1, over: 0, cores: 4) == nil)
        #expect(ProcessMeter.share(9_000_000_000, over: 1_000_000_000, cores: 2) == 1)
    }

    /// This test runs as a child of the test runner: the runner's tree holds it.
    @Test func aProcessTreeHoldsItsChildren() {
        let tree = ProcessMeter.tree(getppid())
        #expect(tree.first == getppid())
        #expect(tree.contains(getpid()))
    }

    /// One real pass after another on the Mac running the tests. Only what every Mac has
    /// is required; everything read must be in range.
    @Test func twoPassesOnThisMacReadItsLoad() throws {
        let sampler = LoadSampler()
        let me = SessionKey("this-test")
        _ = sampler.sample([me: getpid()], at: Date())
        var x = 0.0
        let start = Date()
        while Date().timeIntervalSince(start) < 0.3 { x += sin(x + 1) }
        withExtendedLifetime(x) {}
        let readings = sampler.sample([me: getpid()], at: Date())
        func amount(_ field: Field) -> Double? {
            readings.first { $0.field == field && $0.subject == .machine }?.value.amount
        }
        let load = try #require(amount(.cpuLoad))
        #expect((0...1).contains(load))
        #expect(try #require(amount(.memoryTotal)) > 0)
        #expect(try #require(amount(.memoryUsed)) > 0)
        #expect(readings.contains { $0.field == .thermalState })
        for field in [Field.gpuLoad] {
            if let share = amount(field) { #expect((0...1).contains(share)) }
        }
        for field in [Field.systemPower, .socTemperature, .ssdTemperature, .batteryTemperature] {
            if let figure = amount(field) { #expect((0...500).contains(figure), "\(field)") }
        }
        let mine = readings.filter { $0.subject == .session(me) }
        #expect(mine.contains { $0.field == .processMemory && ($0.value.amount ?? 0) > 0 })
        let share = try #require(mine.first { $0.field == .processCPU }?.value.amount)
        #expect(share > 0 && share <= 1)
    }
}
