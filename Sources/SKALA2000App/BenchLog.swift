import Darwin
import Foundation

/// For measurements only (`SKALA_BENCH` set): every ten seconds, the CPU this process and
/// the children it has waited for have used, appended to `bench.log` in the data folder.
/// `ps` sees only the process itself; the Claude Code feed spends most of its time in
/// `claude agents --json`, a child.
@MainActor
final class BenchLog {
    private var timer: Timer?
    private let url: URL

    init?(folder: URL) {
        guard ProcessInfo.processInfo.environment["SKALA_BENCH"] != nil else { return nil }
        url = folder.appendingPathComponent("bench.log")
        try? Data().write(to: url)
        write()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.write() }
        }
    }

    private func write() {
        var own = rusage()
        var children = rusage()
        getrusage(RUSAGE_SELF, &own)
        getrusage(RUSAGE_CHILDREN, &children)
        func seconds(_ time: timeval) -> Double { Double(time.tv_sec) + Double(time.tv_usec) / 1e6 }
        let line = String(
            format: "%.3f %.3f %.3f\n", Date().timeIntervalSince1970,
            seconds(own.ru_utime) + seconds(own.ru_stime),
            seconds(children.ru_utime) + seconds(children.ru_stime))
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        }
    }
}

/// When this process started, from the kernel: launch is measured from exec, not from
/// `main`.
enum ProcessStart {
    static var date: Date {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return Date() }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1e6)
    }
}
