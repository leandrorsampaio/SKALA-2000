import Foundation
import IOKit

/// The fans' speeds, from the System Management Controller.
///
/// The SMC's keys are not documented, though every fan utility reads them the same way:
/// `FNum` says how many fans there are, and `F0Ac`, `F1Ac` how fast each turns. Only
/// reading; nothing here ever writes a key. A Mac without fans, or an SMC that will not
/// answer, gives no speeds and FAN 1 and FAN 2 stay dark.
final class FanReader {

    /// The SMC's request and answer, laid out as its C struct is: 80 bytes. The key
    /// information is padded to twelve, as C pads it; left at nine, every field after it
    /// lands in the wrong place and the SMC refuses the call.
    private struct Request {
        struct Version {
            var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0,
                release: UInt16 = 0
        }
        struct Limits {
            var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0,
                memory: UInt32 = 0
        }
        struct KeyInfo {
            var size: UInt32 = 0
            var type: UInt32 = 0
            var attributes: UInt8 = 0
            var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
        }
        var key: UInt32 = 0
        var version = Version()
        var limits = Limits()
        var info = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
    }

    private static let readBytes: UInt8 = 5
    private static let readInfo: UInt8 = 9

    private var connection: io_connect_t = 0
    /// How many fans, asked once: a Mac does not grow one.
    private var count: Int?
    /// Each key's size and type, asked once, so a speed costs one call rather than two.
    private var infos: [UInt32: (size: UInt32, type: UInt32)] = [:]

    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != KERN_SUCCESS {
            connection = 0
        }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    /// Each fan's speed in rpm, the first two; empty without fans. A fan at rest reads 0.
    func speeds() -> [Double] {
        guard connection != 0 else { return [] }
        // Asked until the SMC answers once; a refusal is not taken for "no fans".
        if count == nil { count = read("FNum").flatMap(Self.integer) }
        guard let count, count > 0 else { return [] }
        return (0..<min(count, 2)).compactMap { fan in
            read("F\(fan)Ac").flatMap(Self.number)
        }
    }

    // MARK: - Keys

    static func fourCC(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    /// A key's value: its type, and its bytes as the SMC holds them.
    private func read(_ key: String) -> (type: UInt32, bytes: [UInt8])? {
        let code = Self.fourCC(key)
        if infos[code] == nil {
            var ask = Request()
            ask.key = code
            ask.command = Self.readInfo
            guard let answer = call(&ask) else { return nil }
            infos[code] = (answer.info.size, answer.info.type)
        }
        guard let info = infos[code] else { return nil }
        var fetch = Request()
        fetch.key = code
        fetch.info.size = info.size
        fetch.command = Self.readBytes
        guard var answer = call(&fetch) else { return nil }
        let size = min(Int(info.size), 32)
        let bytes = withUnsafeBytes(of: &answer.bytes) { Array($0.prefix(size)) }
        return (info.type, bytes)
    }

    private func call(_ request: inout Request) -> Request? {
        var answer = Request()
        var size = MemoryLayout<Request>.stride
        let result = IOConnectCallStructMethod(
            connection, 2, &request, MemoryLayout<Request>.stride, &answer, &size)
        return result == KERN_SUCCESS && answer.result == 0 ? answer : nil
    }

    /// `ui8 `, as `FNum` is.
    static func integer(_ value: (type: UInt32, bytes: [UInt8])) -> Int? {
        guard value.type == fourCC("ui8 "), let first = value.bytes.first else { return nil }
        return Int(first)
    }

    /// A speed: a little-endian float on Apple Silicon, `flt `; unsigned fixed point with
    /// two fractional bits on Intel Macs, `fpe2`.
    static func number(_ value: (type: UInt32, bytes: [UInt8])) -> Double? {
        let bytes = value.bytes
        switch value.type {
        case fourCC("flt ") where bytes.count >= 4:
            let bits =
                UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
            let speed = Double(Float(bitPattern: bits))
            return speed.isFinite && speed >= 0 ? speed : nil
        case fourCC("fpe2") where bytes.count >= 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        default:
            return nil
        }
    }
}
