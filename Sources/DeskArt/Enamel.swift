import ConsoleKit
import CoreGraphics
import Foundation

/// The grain and the coat, generated once per finish as one 512-unit tile.
///
/// Both noises are centred on mid-grey so that, composited in overlay mode, they leave the
/// paint colour exact. The same numbers as the reference, so the paint is the same paint.
enum EnamelTexture {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Finish: CGImage] = [:]

    static func image(for finish: Finish) -> CGImage {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[finish] { return cached }
        let (grain, mottle, seed): (Double, Double, UInt64) =
            switch finish {
            case .greyGreen: (0.08, 0.10, 7)
            case .ivory: (0.06, 0.09, 11)
            case .graphite: (0.15, 0.12, 23)
            }
        let image = make(grain: grain, mottle: mottle, seed: seed)
        cache[finish] = image
        return image
    }

    static func make(grain: Double, mottle: Double, seed: UInt64) -> CGImage {
        let size = 512
        var random = SplitMix64(seed: seed)

        // The coat: a coarse grid of values, blended smoothly, about 170 units a cell.
        let cells = 4
        var coarse = [Double](repeating: 0, count: (cells + 1) * (cells + 1))
        for index in coarse.indices { coarse[index] = random.unit() * 2 - 1 }
        // Wrap the last row and column onto the first so the tile has no seam.
        for i in 0...cells {
            coarse[i * (cells + 1) + cells] = coarse[i * (cells + 1)]
            coarse[cells * (cells + 1) + i] = coarse[i]
        }
        func coat(_ x: Double, _ y: Double) -> Double {
            let fx = x / Double(size) * Double(cells)
            let fy = y / Double(size) * Double(cells)
            let x0 = min(cells - 1, Int(fx))
            let y0 = min(cells - 1, Int(fy))
            let tx = smooth(fx - Double(x0))
            let ty = smooth(fy - Double(y0))
            let a = coarse[y0 * (cells + 1) + x0]
            let b = coarse[y0 * (cells + 1) + x0 + 1]
            let c = coarse[(y0 + 1) * (cells + 1) + x0]
            let d = coarse[(y0 + 1) * (cells + 1) + x0 + 1]
            return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
        }

        var pixels = [UInt8](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let fine = (random.unit() * 2 - 1) * grain
                let broad = coat(Double(x), Double(y)) * mottle * 0.5
                let value = min(1, max(0, 0.5 + fine + broad))
                pixels[y * size + x] = UInt8(value * 255)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

    private static func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
}

/// Small, fast and the same numbers on every machine, so a screw's slot and the paint's
/// grain never change between launches.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    static func seed(_ text: String) -> UInt64 {
        text.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01B3 }
    }
}

extension Pen {

    /// Smooth sprayed satin enamel on flat steel: the finish, its grain and coat, and room
    /// light falling off across the sheet. Each sub-panel gets its own falloff, so plates
    /// read as separate sheets.
    func enamel(
        _ rect: CGRect, radius: CGFloat, finish: Finish, palette: Palette, falloff: Bool = true
    ) {
        let paint = palette.paint(finish)
        clip(Pen.rect(rect, radius: radius)) {
            fill(rect, paint.ground)
            ctx.saveGState()
            // The grain casts no shadow: in the reference it is a blended image, and a
            // shadow of it would darken the whole sheet.
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.setBlendMode(.overlay)
            ctx.interpolationQuality = .low
            // Tiles from the sheet's own corner, one texel a unit, top row at the top as
            // SwiftUI draws an image: the context is flipped, so the tile is flipped back.
            ctx.translateBy(x: rect.minX, y: rect.minY + 512)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(
                EnamelTexture.image(for: finish), in: CGRect(x: 0, y: 0, width: 512, height: 512),
                byTiling: true)
            ctx.restoreGState()
            guard falloff else { return }
            let w = rect.width
            let h = rect.height
            // A soft highlight from the top-left corner, gone by 60% across.
            let highlight = CGRect(
                x: rect.minX + w * 0.18 - w * 0.6, y: rect.minY - h * 0.9, width: w * 1.2,
                height: h * 1.8)
            elliptical(
                Pen.rect(rect), [(white(0.20), 0), (white(0), 1)],
                center: CGPoint(x: 0.18, y: 0), frame: highlight, endFraction: 0.6)
            // And a darkening toward the bottom-right.
            let shade = CGRect(
                x: rect.minX + w - w * 1.2, y: rect.minY + h - h, width: w * 2.4, height: h * 2)
            elliptical(
                Pen.rect(rect), [(black(0.16), 0), (black(0), 1)], center: .center, frame: shade,
                endFraction: 0.65)
        }
    }
}
