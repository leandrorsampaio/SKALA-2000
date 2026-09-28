import Darwin
import Foundation
import IOKit

/// One look at each of the Mac's own counters and gauges. Every call reads what the
/// system already keeps for anyone to see: no privileges, no entitlement, nothing sent
/// anywhere. A figure this Mac does not have — a desktop has no battery to report its
/// draw — is `nil`, and its instrument stays dark.
///
/// The arithmetic on what they return is kept apart from the reading, so it can be tested
/// without the machine.
enum MacProbes {

    // MARK: - Processors

    /// Every core's ticks since boot, busy and in all.
    struct CPUTicks: Equatable {
        var busy: UInt64
        var total: UInt64
    }

    static func cpuTicks() -> CPUTicks? {
        var cores: natural_t = 0
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        guard
            host_processor_info(
                mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cores, &info, &count) == KERN_SUCCESS,
            let info
        else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                vm_size_t(Int(count) * MemoryLayout<integer_t>.stride))
        }
        var ticks = CPUTicks(busy: 0, total: 0)
        for core in 0..<Int(cores) {
            let base = core * Int(CPU_STATE_MAX)
            func state(_ index: Int32) -> UInt64 {
                UInt64(UInt32(bitPattern: info[base + Int(index)]))
            }
            let busy = state(CPU_STATE_USER) + state(CPU_STATE_SYSTEM) + state(CPU_STATE_NICE)
            ticks.busy += busy
            ticks.total += busy + state(CPU_STATE_IDLE)
        }
        return ticks
    }

    /// The share of all the cores at work between two readings; `nil` if the counters
    /// went backwards, which they do only when one wraps.
    static func load(from old: CPUTicks, to new: CPUTicks) -> Double? {
        guard new.total > old.total, new.busy >= old.busy else { return nil }
        return min(1, Double(new.busy - old.busy) / Double(new.total - old.total))
    }

    // MARK: - Memory

    /// Memory as Activity Monitor divides it, in bytes. Used is app memory, wired and
    /// compressed together; files cached and anything the system may reclaim at once
    /// are not.
    struct Memory: Equatable {
        var used: Double
        var wired: Double
        var compressed: Double
    }

    static func memory() -> Memory? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var page: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(mach_host_self(), &page) == KERN_SUCCESS
        else { return nil }
        return memory(
            anonymous: UInt64(stats.internal_page_count), purgeable: UInt64(stats.purgeable_count),
            wired: UInt64(stats.wire_count), compressed: UInt64(stats.compressor_page_count),
            pageSize: UInt64(page))
    }

    static func memory(
        anonymous: UInt64, purgeable: UInt64, wired: UInt64, compressed: UInt64, pageSize: UInt64
    ) -> Memory {
        let page = Double(pageSize)
        // App memory: pages no file backs, less those an app has said may be thrown away.
        let app = Double(anonymous) - Double(purgeable)
        let wiredBytes = Double(wired) * page
        let compressedBytes = Double(compressed) * page
        return Memory(
            used: max(0, app) * page + wiredBytes + compressedBytes, wired: wiredBytes,
            compressed: compressedBytes)
    }

    static func swapUsed() -> Double? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return Double(usage.xsu_used)
    }

    /// The level Activity Monitor colours its memory graph by.
    static func memoryPressure() -> String? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0
        else { return nil }
        return pressure(level: level)
    }

    static func pressure(level: Int32) -> String? {
        switch level {
        case 1: "normal"
        case 2: "warning"
        case 4: "critical"
        default: nil
        }
    }

    static func thermal(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "critical"
        }
    }

    // MARK: - GPU and power

    /// How busy the GPU is, as its driver reports it: the busiest, should there be two.
    static func gpuLoad() -> Double? {
        var busiest: Double?
        forEachService("IOAccelerator") { service in
            guard let stats = property(service, "PerformanceStatistics") as? [String: Any],
                let busy = stats["Device Utilization %"] as? NSNumber
            else { return }
            busiest = max(busiest ?? 0, busy.doubleValue / 100)
        }
        return busiest.map { min(1, max(0, $0)) }
    }

    /// What the whole Mac draws, in watts, as its battery controller measures it: on a
    /// charger or not, everything the logic board uses. A Mac without a battery has no
    /// such figure.
    static func systemPower() -> Double? {
        battery { service in
            guard let telemetry = property(service, "PowerTelemetryData") as? [String: Any],
                let milliwatts = telemetry["SystemLoad"] as? NSNumber
            else { return nil }
            return max(0, milliwatts.doubleValue / 1000)
        }
    }

    /// The battery's own temperature, which it reports in hundredths of a degree.
    static func batteryTemperature() -> Double? {
        battery { service in
            (property(service, "Temperature") as? NSNumber).map { $0.doubleValue / 100 }
        }
    }

    // MARK: - Disk and network

    /// Bytes read and written since boot, by every disk the Mac has attached.
    static func diskBytes() -> (read: UInt64, written: UInt64)? {
        var read: UInt64 = 0
        var written: UInt64 = 0
        var found = false
        forEachService("IOBlockStorageDriver") { service in
            guard let stats = property(service, "Statistics") as? [String: Any] else { return }
            found = true
            read &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            written &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return found ? (read, written) : nil
    }

    /// Room on the startup disk, as the Finder counts it: what the system would clear to
    /// make room is room.
    static func diskFree() -> Double? {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey
        ])
        return values?.volumeAvailableCapacityForImportantUsage.map(Double.init)
    }

    /// Bytes in and out over each of the Mac's Ethernet-type links, Wi-Fi among them, by
    /// interface: the loopback and tunnels are left out, as a VPN's traffic would count
    /// twice. An app is told only the low 32 bits of each count, to the kilobyte, so they
    /// wrap every 4 GiB; `traffic` allows for it.
    static func networkCounters() -> [UInt16: Counters]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return nil }
        var out: [UInt16: Counters] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let size = Int(header.ifm_msglen)
                guard size > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                    offset + MemoryLayout<if_msghdr2>.size <= length
                {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if Int32(message.ifm_data.ifi_type) == IFT_ETHER {
                        out[message.ifm_index] = Counters(
                            received: message.ifm_data.ifi_ibytes, sent: message.ifm_data.ifi_obytes
                        )
                    }
                }
                offset += size
            }
        }
        return out
    }

    struct Counters: Equatable {
        var received: UInt64
        var sent: UInt64
    }

    /// Bytes a second in and out between two readings of every interface, each counter
    /// allowed to have wrapped once. An interface that came or went, or whose counter went
    /// back while too large to have wrapped, adds nothing.
    static func traffic(
        from old: [UInt16: Counters], to new: [UInt16: Counters], over seconds: TimeInterval
    ) -> (received: Double, sent: Double)? {
        guard seconds > 0 else { return nil }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (index, now) in new {
            guard let before = old[index] else { continue }
            received &+= delta(from: before.received, to: now.received) ?? 0
            sent &+= delta(from: before.sent, to: now.sent) ?? 0
        }
        return (Double(received) / seconds, Double(sent) / seconds)
    }

    static func delta(from old: UInt64, to new: UInt64) -> UInt64? {
        if new >= old { return new - old }
        let wrap: UInt64 = 1 << 32
        guard old < wrap, new < wrap else { return nil }
        return new + wrap - old
    }

    /// Bytes a second between two readings of a counter; `nil` for the first reading, or
    /// a counter that went backwards (a disk ejected, an interface reset).
    static func rate(from old: UInt64?, to new: UInt64, over seconds: TimeInterval) -> Double? {
        guard let old, new >= old, seconds > 0 else { return nil }
        return Double(new - old) / seconds
    }

    // MARK: - IOKit

    static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }

    static func forEachService(_ className: String, _ body: (io_service_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS
        else { return }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            body(service)
            IOObjectRelease(service)
        }
    }

    private static func battery<T>(_ read: (io_service_t) -> T?) -> T? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return read(service)
    }
}
