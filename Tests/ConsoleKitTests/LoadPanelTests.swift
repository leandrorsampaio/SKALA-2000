import Foundation
import Testing

@testable import ConsoleKit
@testable import TelemetryKit

/// Panel F: what the Mac is doing, and what each seated session's processes cost it.
@MainActor
@Suite struct LoadPanelTests {

    let gigabyte = 1_073_741_824.0

    func mac(_ bench: Bench, _ readings: [(Field, Value)]) {
        bench.feed(readings.map { bench.machine($0.0, $0.1, ttl: 6) })
    }

    @Test func theMetersShowTheMacsLoad() {
        let bench = Bench()
        #expect(bench.snap.meter(PK4.loadMeter(.cpu)) == Needle.leftStop)
        mac(bench, [
            (.cpuLoad, .amount(0.42)), (.gpuLoad, .amount(0.1)), (.systemPower, .amount(35)),
            (.memoryUsed, .amount(18 * gigabyte)), (.memoryTotal, .amount(24 * gigabyte)),
        ])
        #expect(bench.snap.meter(PK4.loadMeter(.cpu)) == 0.42)
        #expect(bench.snap.meter(PK4.loadMeter(.gpu)) == 0.1)
        // Watts on a scale of 0 to 100, and a Mac drawing more pins the needle there.
        #expect(bench.snap.meter(PK4.loadMeter(.power)) == 0.35)
        #expect(bench.snap.meter(PK4.loadMeter(.memory)) == 0.75)
        mac(bench, [(.systemPower, .amount(140))])
        #expect(bench.snap.meter(PK4.loadMeter(.power)) == 1)

        // Readings that stop coming let the needles fall.
        bench.run(for: 7)
        #expect(bench.snap.meter(PK4.loadMeter(.cpu)) == Needle.leftStop)
    }

    /// A lamp for each state; the red ones flash for as long as they hold.
    @Test func thermalStateAndMemoryPressureLightTheirLamps() {
        let bench = Bench()
        mac(bench, [(.thermalState, .text("nominal")), (.memoryPressure, .text("normal"))])
        #expect(bench.lamp(PK4.thermal(.nominal)) == .on)
        #expect(bench.lamp(PK4.pressure(.normal)) == .on)
        #expect(bench.lamp(PK4.thermal(.fair)) == .off)

        mac(bench, [(.thermalState, .text("serious")), (.memoryPressure, .text("warning"))])
        #expect(bench.lamp(PK4.thermal(.nominal)) == .off)
        #expect(bench.lamp(PK4.thermal(.serious)) == .flash)
        #expect(bench.lamp(PK4.pressure(.warning)) == .on)

        mac(bench, [(.memoryPressure, .text("critical"))])
        #expect(bench.lamp(PK4.pressure(.critical)) == .flash)
        // A word the desk has no lamp for lights nothing.
        mac(bench, [(.thermalState, .text("molten"))])
        #expect(PK4.Thermal.allCases.allSatisfy { bench.lamp(PK4.thermal($0)) == .off })
    }

    @Test func theTubesReadInTheirUnits() {
        let bench = Bench()
        #expect(bench.snap.nixie(PK4.gauge(.socTemp)) == "   ")
        mac(bench, [
            (.socTemperature, .amount(47.6)), (.fan1Speed, .amount(2317.4)),
            (.memoryUsed, .amount(18.24 * gigabyte)), (.swapUsed, .amount(0.93 * gigabyte)),
            (.diskFree, .amount(32_900_000_000)), (.diskRead, .amount(12_340_000)),
            (.networkIn, .amount(1_250_000_000)),
        ])
        #expect(bench.snap.nixie(PK4.gauge(.socTemp)) == "048")
        #expect(bench.snap.nixie(PK4.gauge(.fan1)) == "2317")
        #expect(bench.snap.nixie(PK4.gauge(.memoryUsed)) == "18.2")
        #expect(bench.snap.nixie(PK4.gauge(.swap)) == "00.9")
        // The Finder's gigabytes, whole ones: what is free, not a rounding up of it.
        #expect(bench.snap.nixie(PK4.gauge(.diskFree)) == "0032")
        #expect(bench.snap.nixie(PK4.gauge(.diskRead)) == "012.3")
        // Faster than the tubes can say: all nines.
        #expect(bench.snap.nixie(PK4.gauge(.networkIn)) == "999.9")
        // A Mac without a second fan leaves its tubes dark.
        #expect(bench.snap.nixie(PK4.gauge(.fan2)) == "    ")
    }

    @Test func eachSeatedSessionShowsWhatItsProcessesCost() {
        let bench = Bench()
        bench.feed(bench.poll(["a", "b"]))
        bench.feed([
            bench.reading("a", .processCPU, .amount(0.083)),
            bench.reading("a", .processMemory, .amount(0.62 * gigabyte)),
        ])
        let a = bench.slot(of: "a")!
        let b = bench.slot(of: "b")!
        #expect(bench.snap.nixie(PK4.sessionCPU(slot: a)) == "008")
        #expect(bench.snap.nixie(PK4.sessionMemory(slot: a)) == "00.6")
        #expect(bench.snap.nixie(PK4.sessionCPU(slot: b)) == "   ")
    }

    /// Measured from outside, a process still running is no sign that Claude Code still
    /// reports on its session: the session still goes stale, and a session that has left
    /// is not brought back by a measurement that was on its way.
    @Test func processReadingsNeitherKeepASessionAliveNorBringOneBack() {
        let bench = Bench()
        bench.feed(bench.poll(["a"]))
        let slot = bench.slot(of: "a")!
        for _ in 0..<10 {
            bench.run(for: 2)
            bench.feed([bench.reading("a", .processCPU, .amount(0.05))])
        }
        #expect(bench.lamp(.run, slot) == .off)
        #expect(bench.snap.nixie(PK4.sessionCPU(slot: slot)) == "   ")

        bench.feed([bench.reading("ghost", .processMemory, .amount(gigabyte))])
        #expect(bench.model.sessions["ghost"] == nil)
    }

    /// What the load source is asked to measure: seated sessions with a process of their
    /// own. A background job has none.
    @Test func onlySeatedSessionsWithAProcessAreMeasured() {
        let bench = Bench()
        bench.feed(
            bench.poll(["a"]) + bench.agent("job", kind: "background") + [
                bench.reading("a", .pid, .count(4242)), bench.reading("job", .pid, .count(4343)),
                bench.roster(["a", "job"]),
            ])
        #expect(bench.model.seatedProcesses() == ["a": 4242])
    }

    @Test func aFigureWithAPointIsRoundedToItsLastTube() {
        #expect(NixieFormat.decimal(18.24, whole: 2, fraction: 1) == "18.2")
        #expect(NixieFormat.decimal(0.96, whole: 2, fraction: 1) == "01.0")
        #expect(NixieFormat.decimal(123.45, whole: 2, fraction: 1) == "99.9")
        #expect(NixieFormat.decimal(-3, whole: 3, fraction: 1) == "000.0")
        #expect(NixieFormat.decimal(.nan, whole: 2, fraction: 1) == "00.0")
    }
}
