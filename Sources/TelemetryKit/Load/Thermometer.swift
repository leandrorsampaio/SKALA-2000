import Darwin
import Foundation

/// The Mac's temperature sensors: the hottest point of the processor die, and the SSD.
///
/// Apple Silicon keeps its sensors behind IOKit's HID event system, whose functions are
/// exported but not documented. They are looked up by name when this starts, so a macOS
/// without them costs the two readouts and nothing else: no crash, no link error. Reading
/// needs no privilege.
///
/// Each sensor is a round trip to its controller, about three quarters of a millisecond of
/// waiting though hardly any work, so the sampler asks every ten seconds, not every two.
final class Thermometer {

    enum Group: Equatable {
        case soc, ssd
    }

    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEvent =
        @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<
            AnyObject
        >?
    private typealias FloatValue = @convention(c) (AnyObject, Int32) -> Double

    private static let temperatureEvent: Int64 = 15
    private static let temperatureField = Int32(15 << 16)

    private let client: AnyObject?
    private let copyEvent: CopyEvent?
    private let floatValue: FloatValue?
    /// Only the sensors this reads, found once: asking all seventy-odd every two seconds
    /// would cost more than everything else together.
    private let sensors: [(group: Group, service: AnyObject)]

    init() {
        let kit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        func symbol<T>(_ name: String, _ type: T.Type) -> T? {
            dlsym(kit, name).map { unsafeBitCast($0, to: type) }
        }
        guard let create = symbol("IOHIDEventSystemClientCreate", Create.self),
            let setMatching = symbol("IOHIDEventSystemClientSetMatching", SetMatching.self),
            let copyServices = symbol("IOHIDEventSystemClientCopyServices", CopyServices.self),
            let copyProperty = symbol("IOHIDServiceClientCopyProperty", CopyProperty.self),
            let copyEvent = symbol("IOHIDServiceClientCopyEvent", CopyEvent.self),
            let floatValue = symbol("IOHIDEventGetFloatValue", FloatValue.self),
            let client = create(kCFAllocatorDefault)?.takeRetainedValue()
        else {
            client = nil
            self.copyEvent = nil
            self.floatValue = nil
            sensors = []
            return
        }
        // Apple's vendor page, usage 5: a temperature sensor.
        _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        let services = (copyServices(client)?.takeRetainedValue() as? [AnyObject]) ?? []
        self.client = client
        self.copyEvent = copyEvent
        self.floatValue = floatValue
        sensors = services.compactMap { service in
            let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String
            return name.flatMap(Self.group).map { ($0, service) }
        }
    }

    /// The sensors this reads, by the names Apple Silicon gives them: the PMU's die
    /// sensors, `PMU tdie1` and on, and the SSD's `NAND CH0 temp`. The PMU's `tdev` and
    /// `tcal` channels are not temperatures of anything the operator knows.
    static func group(_ name: String) -> Group? {
        if name.hasPrefix("PMU tdie") { return .soc }
        if name.hasPrefix("NAND") { return .ssd }
        return nil
    }

    /// The hottest of each group, in °C. A sensor reading outside anything a Mac can be is
    /// a sensor not reading, and is left out.
    static func hottest(
        _ samples: [(group: Group, celsius: Double)]
    ) -> (
        soc: Double?, ssd: Double?
    ) {
        func top(_ group: Group) -> Double? {
            samples.filter { $0.group == group && (-20...150).contains($0.celsius) }
                .map(\.celsius).max()
        }
        return (top(.soc), top(.ssd))
    }

    func read() -> (soc: Double?, ssd: Double?) {
        guard let copyEvent, let floatValue else { return (nil, nil) }
        let samples = sensors.compactMap { sensor -> (group: Group, celsius: Double)? in
            guard
                let event = copyEvent(sensor.service, Self.temperatureEvent, 0, 0)?
                    .takeRetainedValue()
            else { return nil }
            return (sensor.group, floatValue(event, Self.temperatureField))
        }
        return Self.hottest(samples)
    }
}
