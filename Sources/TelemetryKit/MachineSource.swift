import AppKit
import CoreGraphics
import Foundation
import IOKit.ps

/// What the Mac itself reports: where its power comes from, how full the battery is, and
/// whether its display or the whole machine is asleep.
///
/// Power is read when IOKit says it changed and every ten seconds regardless; sleep and
/// wake arrive as workspace notifications. Nothing here needs an entitlement, so it runs
/// in both builds.
@MainActor
public final class MachineSource {

    public nonisolated static let interval: TimeInterval = 10
    public nonisolated static let ttl = TTL.polled(every: interval)

    private let deliver: @MainActor ([Reading]) -> Void
    private var timer: Timer?
    private var runLoopSource: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private var displayAsleep = false
    private var systemAsleep = false

    public init(deliver: @escaping @MainActor ([Reading]) -> Void) {
        self.deliver = deliver
    }

    /// IOKit holds this object unretained: should an owner forget `stop()`, its source must
    /// not call into freed memory.
    deinit {
        if let runLoopSource { CFRunLoopSourceInvalidate(runLoopSource) }
    }

    public func start() {
        guard timer == nil else { return }
        displayAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        systemAsleep = false

        let workspace = NSWorkspace.shared.notificationCenter
        let watch: [(Notification.Name, (MachineSource) -> Void)] = [
            (NSWorkspace.screensDidSleepNotification, { $0.displayAsleep = true }),
            (NSWorkspace.screensDidWakeNotification, { $0.displayAsleep = false }),
            // Said on the way down, which is the last chance to light SLEEP MODE's lens.
            (NSWorkspace.willSleepNotification, { $0.systemAsleep = true }),
            (NSWorkspace.didWakeNotification, { $0.systemAsleep = false }),
        ]
        observers = watch.map { name, change in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    change(self)
                    self.report()
                }
            }
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(
            { context in
                guard let context else { return }
                let source = Unmanaged<MachineSource>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { source.report() }
            }, context)?.takeRetainedValue()
        {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        }

        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
        report()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
    }

    private func report() {
        let now = Date()
        var readings = Self.power(at: now)
        readings.append(
            Reading(.machine, .displayAsleep, .flag(displayAsleep), at: now, ttl: Self.ttl))
        readings.append(
            Reading(.machine, .systemAsleep, .flag(systemAsleep), at: now, ttl: Self.ttl))
        deliver(readings)
    }

    /// The first power source IOKit lists. A Mac without a battery reports mains and no
    /// charge, which leaves the battery meter on its stop and BATT LOW dark.
    public nonisolated static func power(at moment: Date) -> [Reading] {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return [Reading(.machine, .onMains, .flag(true), at: moment, ttl: ttl)]
        }
        for source in sources {
            guard
                let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                    as? [String: Any]
            else { continue }
            return readings(from: info, at: moment)
        }
        return [Reading(.machine, .onMains, .flag(true), at: moment, ttl: ttl)]
    }

    /// One power source's description, as readings. Separate so it can be tested without
    /// a battery.
    nonisolated static func readings(from info: [String: Any], at moment: Date) -> [Reading] {
        var out: [Reading] = []
        if let state = info[kIOPSPowerSourceStateKey] as? String {
            out.append(
                Reading(.machine, .onMains, .flag(state == kIOPSACPowerValue), at: moment, ttl: ttl)
            )
        }
        if let capacity = info[kIOPSCurrentCapacityKey] as? Int,
            let maximum = info[kIOPSMaxCapacityKey] as? Int, maximum > 0
        {
            let fraction = min(1, max(0, Double(capacity) / Double(maximum)))
            out.append(Reading(.machine, .batteryFraction, .amount(fraction), at: moment, ttl: ttl))
        }
        if let charging = info[kIOPSIsChargingKey] as? Bool {
            out.append(Reading(.machine, .charging, .flag(charging), at: moment, ttl: ttl))
        }
        return out
    }
}
