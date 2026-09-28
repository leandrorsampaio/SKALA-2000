import AppKit
import ConsoleKit
import DeskArt
import FakeSources
import Foundation
import Metal
import Testing

@testable import DeskView

/// The whole desk, drawn by the real layer tree, against the reference SwiftUI desk in the
/// same states: the scripted day at 09:05, both themes, under LAMP TEST and with MAINS off.
///
/// The goldens are half-size JPEGs written by `swift run DeskReference test-goldens`.
/// The tolerance is a mean difference in 255 levels: sub-pixel antialiasing and the JPEG
/// cost about 3 over the whole desk; a painter that goes wrong costs far more in its own
/// instruments, and the per-instrument check catches it.
@Suite(
    .enabled(
        if: MTLCreateSystemDefaultDevice() != nil
            && ProcessInfo.processInfo.environment["CI"] != "true"))
struct GoldenTests {

    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Goldens")

    @MainActor
    static func scriptedDay() -> (ConsoleModel, ManualClock) {
        let clock = ManualClock()
        let model = ConsoleModel(clock: clock, store: MemoryConsoleStore(), log: MemoryConsoleLog())
        var day = FakeDay(start: clock.now)
        while day.elapsed < 1.1 * 3600 {
            let readings = day.step()
            clock.now = day.now
            model.ingest(readings)
            model.advance()
        }
        clock.advance(by: 1)
        model.advance()
        return (model, clock)
    }

    struct Pixels: Sendable {
        let width: Int
        let height: Int
        var data: [UInt8]

        init(_ image: CGImage) {
            width = image.width
            height = image.height
            data = [UInt8](repeating: 0, count: width * height * 4)
            let ctx = CGContext(
                data: &data, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        /// The smallest mean difference over `rect` with this image moved up to one pixel
        /// either way: the reference rounds its layout to whole pixels, the table to halves.
        func shiftedError(against other: Pixels, in rect: CGRect, scale: CGFloat) -> Double {
            var best = Double.infinity
            for dx in -1...1 {
                for dy in -1...1 {
                    best = min(best, error(against: other, in: rect, scale: scale, dx: dx, dy: dy))
                }
            }
            return best
        }

        /// Mean absolute difference per channel over `rect` (desk units).
        func error(
            against other: Pixels, in rect: CGRect, scale: CGFloat, dx: Int = 0, dy: Int = 0
        ) -> Double {
            let x0 = max(0, Int(rect.minX * scale))
            let y0 = max(0, Int(rect.minY * scale))
            let x1 = min(width, Int(rect.maxX * scale))
            let y1 = min(height, Int(rect.maxY * scale))
            guard x1 > x0, y1 > y0 else { return 0 }
            var total = 0
            data.withUnsafeBufferPointer { mine in
                other.data.withUnsafeBufferPointer { theirs in
                    for y in y0..<y1 {
                        let sy = min(height - 1, max(0, y + dy))
                        for x in x0..<x1 {
                            let sx = min(width - 1, max(0, x + dx))
                            let i = (sy * width + sx) * 4
                            let j = (y * width + x) * 4
                            total += abs(Int(mine[i]) - Int(theirs[j]))
                            total += abs(Int(mine[i + 1]) - Int(theirs[j + 1]))
                            total += abs(Int(mine[i + 2]) - Int(theirs[j + 2]))
                        }
                    }
                }
            }
            return Double(total) / Double((x1 - x0) * (y1 - y0) * 3)
        }
    }

    /// Draws on the main actor, compares off it: the comparison is seconds of arithmetic,
    /// and the main thread has other tests' timers to run.
    func compare(_ name: String, _ snapshot: ConsoleSnapshot, night: Bool) async throws {
        // Drawn at full size and averaged down, as the goldens were.
        let scale: CGFloat = 0.5
        let url = Self.folder.appendingPathComponent("\(name).jpg")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let golden = Pixels(try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)))
        let drawn = await MainActor.run {
            DeskPrinter.image(snapshot, style: ArtStyle(night: night), scale: 1)
        }
        let full = try #require(drawn)
        let mine = Pixels(try #require(DeskImages.halved(full)))
        // Compared pixel by pixel below: images of different sizes would read past one.
        try #require(mine.width == golden.width && mine.height == golden.height)

        let whole = mine.error(
            against: golden, in: CGRect(origin: .zero, size: DeskLayout.size), scale: scale)
        #expect(whole < 5, "\(name): the desk differs from the reference by \(whole)")
        for kind in [
            "panel", "lamp", "lens", "cap", "roundCap", "nixie", "drum", "meter", "guard", "plate",
        ] {
            // A flashing lamp is at whatever point of its flash each render caught it.
            for element in DeskLayout.all(kind)
            where snapshot.lamp(InstrumentID(element.id)) != .flash {
                let error = mine.shiftedError(against: golden, in: element.rect, scale: scale)
                // Bright lettering on black bakelite turns half a unit of placement into a
                // large difference. A lit lens is 22 pixels here and mostly glow, a blur in
                // both pipelines: two outside runs saw one reach 18 and 20, which this Mac
                // never has. A lit cap's spill is the same kind of blur: PRINT TO LOG, beside
                // the lit SELECTED tube, reaches 16.5. Everything else must match closely;
                // a lens or cap painted wrong differs by far more than 24.
                let limit: Double =
                    switch kind {
                    case "plate": 30
                    case "lens": 24
                    case "cap": 20
                    default: 16
                    }
                #expect(
                    error < limit,
                    "\(name): \(kind) \(element.id) \(element.text()) differs by \(error)")
            }
        }
    }

    @Test func theScriptedDayByDayAndByNight() async throws {
        let snapshot = await MainActor.run { Self.scriptedDay().0.snapshot }
        try await compare("day", snapshot, night: false)
        try await compare("night", snapshot, night: true)
    }

    @Test func lampTestAndMainsOff() async throws {
        let (testing, off) = await MainActor.run {
            let (model, clock) = Self.scriptedDay()
            model.send(.press(PK4.lampTest))
            let testing = model.snapshot
            model.send(.release(PK4.lampTest))
            clock.advance(by: 2)
            model.advance()
            model.send(.mains(false))
            return (testing, model.snapshot)
        }
        try await compare("lamp-test-day", testing, night: false)
        try await compare("lamp-test-night", testing, night: true)
        try await compare("mains-off", off, night: false)
    }
}
