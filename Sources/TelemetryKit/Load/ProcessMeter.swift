import Darwin
import Foundation

/// What each seated session's processes cost the Mac: the session and everything it
/// started — its shell commands, its MCP servers, the builds it runs — since that is what
/// the session makes the Mac do.
///
/// Only the operator's own processes can be looked into, and a session is one of them.
/// Nothing is read but the process tree, CPU time and memory.
struct ProcessMeter {

    struct Sample: Equatable {
        /// Its share of all the Mac's cores since the last look; `nil` the first time.
        var share: Double?
        /// Bytes, as Activity Monitor's Memory column counts them.
        var memory: Double
    }

    /// CPU time of every process measured last time, in nanoseconds.
    private var seen: [pid_t: UInt64] = [:]
    /// When that was, on the clock processes are started by.
    private var seenAt: UInt64?
    private let timebase: mach_timebase_info_data_t
    private let cores: Double

    init() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        self.timebase = timebase
        cores = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
    }

    mutating func measure(_ sessions: [SessionKey: pid_t]) -> [SessionKey: Sample] {
        let now = nanoseconds(mach_absolute_time())
        var times: [pid_t: UInt64] = [:]
        var out: [SessionKey: Sample] = [:]
        for (key, root) in sessions {
            var used: UInt64 = 0
            var memory: UInt64 = 0
            var measured = false
            for pid in Self.tree(root) {
                guard let usage = Self.usage(pid) else { continue }
                measured = true
                let time = nanoseconds(usage.ri_user_time &+ usage.ri_system_time)
                times[pid] = time
                memory &+= usage.ri_phys_footprint
                if let before = seen[pid] {
                    used &+= time >= before ? time - before : 0
                } else if let seenAt, nanoseconds(usage.ri_proc_start_abstime) >= seenAt {
                    // Started since the last look: all its time was spent since then.
                    used &+= time
                }
            }
            guard measured else { continue }
            out[key] = Sample(
                share: seenAt.flatMap { Self.share(used, over: now &- $0, cores: cores) },
                memory: Double(memory))
        }
        seen = times
        seenAt = now
        return out
    }

    /// CPU nanoseconds as a share of every core over a wall-clock stretch.
    static func share(_ used: UInt64, over wall: UInt64, cores: Double) -> Double? {
        guard wall > 0 else { return nil }
        return min(1, Double(used) / (Double(wall) * cores))
    }

    /// The process and all its descendants. A process that has gone is simply not there.
    static func tree(_ root: pid_t) -> [pid_t] {
        var out: [pid_t] = []
        var queue: [pid_t] = [root]
        var buffer = [pid_t](repeating: 0, count: 512)
        while let pid = queue.popLast(), out.count < 4096 {
            out.append(pid)
            let count = proc_listchildpids(
                pid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.stride))
            guard count > 0 else { continue }
            queue += buffer.prefix(min(Int(count), buffer.count)).filter { $0 > 0 }
        }
        return out
    }

    private static func usage(_ pid: pid_t) -> rusage_info_v4? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? usage : nil
    }

    /// CPU times and start times are in the machine's ticks: nanoseconds on an Intel Mac,
    /// 125/3 of one each on Apple Silicon.
    private func nanoseconds(_ ticks: UInt64) -> UInt64 {
        guard timebase.denom > 0 else { return ticks }
        return ticks.multipliedFullWidth(by: UInt64(timebase.numer)).high == 0
            ? ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
            : ticks / UInt64(timebase.denom) * UInt64(timebase.numer)
    }
}
