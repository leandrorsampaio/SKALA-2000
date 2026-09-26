import AppKit
import ConsoleKit
import DeskArt
import Foundation

/// Paints the new renderer's static art and measures it against the reference's goldens,
/// element by element, so a painter that is off is found by number rather than by eye.
enum Compare {

    struct Pixels {
        let width: Int
        let height: Int
        var data: [UInt8]  // RGBA

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

        func at(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * width + x) * 4
            return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
        }
    }

    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func write(_ image: CGImage, _ url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }

    /// Mean absolute difference per channel, 0…255, over `rect` in desk units.
    static func error(_ a: Pixels, _ b: Pixels, _ rect: CGRect, scale: CGFloat) -> Double {
        let x0 = max(0, Int(rect.minX * scale)), y0 = max(0, Int(rect.minY * scale))
        let x1 = min(a.width, Int(rect.maxX * scale)), y1 = min(a.height, Int(rect.maxY * scale))
        guard x1 > x0, y1 > y0 else { return 0 }
        var total = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let p = a.at(x, y), q = b.at(x, y)
                total += abs(p.0 - q.0) + abs(p.1 - q.1) + abs(p.2 - q.2)
            }
        }
        return Double(total) / Double((x1 - x0) * (y1 - y0) * 3)
    }

    static func run(goldens: URL, out: URL, scale: CGFloat, only: String?) throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let styles: [(String, ArtStyle)] = [
            ("static-day-greyGreen", ArtStyle(night: false, finish: .greyGreen)),
            ("static-night-greyGreen", ArtStyle(night: true, finish: .greyGreen)),
            ("static-day-ivory", ArtStyle(night: false, finish: .ivory)),
            ("static-day-graphite", ArtStyle(night: false, finish: .graphite)),
            ("static-night-ivory", ArtStyle(night: true, finish: .ivory)),
            ("static-night-graphite", ArtStyle(night: true, finish: .graphite)),
        ]
        for (name, style) in styles where only == nil || name.contains(only!) {
            let started = Date()
            let mine = ArtSet.renderBackground(style: style, scale: scale)
            let seconds = Date().timeIntervalSince(started)
            try write(mine, out.appendingPathComponent("\(name)-mine.png"))
            guard let golden = load(goldens.appendingPathComponent("\(name).png")) else {
                print("no golden for \(name)")
                continue
            }
            let a = Pixels(mine), b = Pixels(golden)
            guard a.width == b.width, a.height == b.height else {
                print("\(name): size \(a.width)×\(a.height) vs golden \(b.width)×\(b.height)")
                continue
            }
            let whole = error(
                a, b, CGRect(origin: .zero, size: DeskArt.DeskLayout.size), scale: scale)
            print(
                String(
                    format: "%@: rendered in %.0f ms, mean error %.2f", name, seconds * 1000, whole)
            )
            var byKind: [String: [Double]] = [:]
            for element in DeskArt.DeskLayout.elements {
                byKind[element.kind, default: []].append(error(a, b, element.rect, scale: scale))
            }
            for (kind, errors) in byKind.sorted(by: { $0.key < $1.key }) {
                let mean = errors.reduce(0, +) / Double(errors.count)
                print(
                    String(
                        format: "  %-16@ %6.2f  (worst %6.2f, %d)", kind as NSString, mean,
                        errors.max() ?? 0, errors.count))
            }
            // A difference image, amplified four times.
            var diff = [UInt8](repeating: 255, count: a.width * a.height * 4)
            for i in stride(from: 0, to: diff.count, by: 4) {
                for c in 0..<3 {
                    diff[i + c] = UInt8(min(255, abs(Int(a.data[i + c]) - Int(b.data[i + c])) * 4))
                }
            }
            let ctx = CGContext(
                data: &diff, width: a.width, height: a.height, bitsPerComponent: 8,
                bytesPerRow: a.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            try write(ctx.makeImage()!, out.appendingPathComponent("\(name)-diff.png"))
        }
    }
}

extension Compare {
    /// For each text-bearing element, the shift of the new render that best matches the
    /// golden, in pixels: a systematic offset per font shows as a peak.
    static func align(goldens: URL, scale: CGFloat, kinds: [String]) throws {
        let style = ArtStyle(night: false, finish: .greyGreen)
        let mine = Pixels(ArtSet.renderBackground(style: style, scale: scale))
        guard let goldenImage = load(goldens.appendingPathComponent("static-day-greyGreen.png"))
        else { return }
        let golden = Pixels(goldenImage)
        for kind in kinds {
            var votes: [String: Int] = [:]
            var gains: [Double] = []
            for element in DeskArt.DeskLayout.all(kind) {
                let r = element.rect
                let x0 = Int(r.minX * scale), y0 = Int(r.minY * scale)
                let x1 = Int(r.maxX * scale), y1 = Int(r.maxY * scale)
                func err(_ dx: Int, _ dy: Int) -> Int {
                    var total = 0
                    for y in y0..<y1 {
                        for x in x0..<x1 {
                            let sx = x - dx, sy = y - dy
                            guard sx >= 0, sy >= 0, sx < mine.width, sy < mine.height else {
                                continue
                            }
                            let p = mine.at(sx, sy), q = golden.at(x, y)
                            total += abs(p.0 - q.0) + abs(p.1 - q.1) + abs(p.2 - q.2)
                        }
                    }
                    return total
                }
                let base = err(0, 0)
                var best = (0, 0, base)
                for dy in -4...4 {
                    for dx in -3...3 {
                        let e = err(dx, dy)
                        if e < best.2 { best = (dx, dy, e) }
                    }
                }
                votes["\(best.0),\(best.1)", default: 0] += 1
                gains.append(base > 0 ? Double(base - best.2) / Double(base) : 0)
            }
            let top = votes.sorted { $0.value > $1.value }.prefix(4).map {
                "(\($0.key))×\($0.value)"
            }
            let gain = gains.isEmpty ? 0 : gains.reduce(0, +) / Double(gains.count)
            print(
                String(
                    format: "%-16@ best shift dx,dy: %@   error cut %.0f%%", kind as NSString,
                    top.joined(separator: " ") as NSString, gain * 100))
        }
    }
}

extension Compare {
    /// Sweeps a baseline nudge per face and reports the text error for each value.
    static func sweepBaselines(goldens: URL, scale: CGFloat) throws {
        guard let goldenImage = load(goldens.appendingPathComponent("static-day-greyGreen.png"))
        else { return }
        let golden = Pixels(goldenImage)
        let faces: [(String, [String])] = [
            (DeskFonts.dosis, ["plate", "tag", "caption", "nameplateLine", "instructionText"]),
            (DeskFonts.barlowSemiBold, ["unit", "lampLabel", "lampCode", "headerSubtitle"]),
            (DeskFonts.barlowBold, ["numeral", "headerTitle"]),
        ]
        let style = ArtStyle(night: false, finish: .greyGreen)
        for (face, kinds) in faces {
            var line = "\(face):"
            for nudge in stride(from: -1.0, through: 0.5, by: 0.25) {
                ArtCalibration.setBaselineNudge(face, CGFloat(nudge))
                let mine = Pixels(ArtSet.renderBackground(style: style, scale: scale))
                var parts: [String] = []
                for kind in kinds {
                    let errors = DeskArt.DeskLayout.all(kind).map {
                        error(mine, golden, $0.rect, scale: scale)
                    }
                    parts.append(
                        String(
                            format: "%@ %.1f", kind,
                            errors.reduce(0, +) / Double(max(1, errors.count))))
                }
                line += String(format: "\n  %+.2f  ", nudge) + parts.joined(separator: "  ")
            }
            ArtCalibration.setBaselineNudge(face, 0)
            print(line)
        }
    }
}

extension Compare {
    static func sweepShadows(goldens: URL, scale: CGFloat) throws {
        guard let goldenImage = load(goldens.appendingPathComponent("static-day-greyGreen.png"))
        else { return }
        let golden = Pixels(goldenImage)
        let kinds = [
            "panel", "plate", "tag", "lamp", "meter", "instruction", "nameplate", "pencil", "nixie",
            "lens",
        ]
        let style = ArtStyle(night: false, finish: .greyGreen)
        for factor in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0] {
            ArtCalibration.setShadowFactor(CGFloat(factor))
            let mine = Pixels(ArtSet.renderBackground(style: style, scale: scale))
            var parts: [String] = []
            var sum = 0.0
            for kind in kinds {
                // A ring around each element, where its shadow falls, plus the element.
                let errors = DeskArt.DeskLayout.all(kind).map {
                    error(mine, golden, $0.rect.insetBy(dx: -6, dy: -6), scale: scale)
                }
                let mean = errors.reduce(0, +) / Double(max(1, errors.count))
                sum += mean
                parts.append(String(format: "%@ %.2f", kind, mean))
            }
            print(
                String(format: "shadow ×%.2f  total %.2f  ", factor, sum)
                    + parts.joined(separator: "  "))
        }
        ArtCalibration.setShadowFactor(1)
    }
}
