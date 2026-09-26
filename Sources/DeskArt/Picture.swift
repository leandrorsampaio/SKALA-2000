import CoreGraphics
import Foundation
import IOSurface

/// A rendered image in an IOSurface: Core Animation shows it as layer contents without
/// copying it, so each picture exists once in memory. Given a `CGImage` instead, Core
/// Animation keeps its own copy beside ours, and the desk at 5K full screen held every
/// pixel three times over (measured: 346 MB).
public final class Picture: @unchecked Sendable {

    public let surface: IOSurface
    public let width: Int
    public let height: Int

    init?(width: Int, height: Int, draw: (CGContext) -> Void) {
        let width = max(1, width)
        let height = max(1, height)
        guard
            let surface = IOSurface(properties: [
                .width: width, .height: height, .bytesPerElement: 4,
                .pixelFormat: 0x4247_5241,  // 'BGRA'
            ])
        else { return nil }
        self.surface = surface
        self.width = width
        self.height = height
        surface.lock(options: [], seed: nil)
        defer { surface.unlock(options: [], seed: nil) }
        memset(surface.baseAddress, 0, surface.bytesPerRow * height)
        guard
            let ctx = CGContext(
                data: surface.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: surface.bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        draw(ctx)
        ctx.flush()
    }

    /// A picture drawn in horizontal bands, one per core. Each band's context reaches
    /// `margin` rows past the band on both sides, over the same surface, but is clipped to
    /// its own rows: a shape just outside a band still casts its shadow in, and no band
    /// ever writes another's pixels. `draw` gets the context, the context's first row from
    /// the top, and its height in rows.
    init?(
        width: Int, height: Int, bands: Int, margin: Int,
        draw: @Sendable (CGContext, Int, Int) -> Void
    ) {
        let width = max(1, width)
        let height = max(1, height)
        guard
            let surface = IOSurface(properties: [
                .width: width, .height: height, .bytesPerElement: 4,
                .pixelFormat: 0x4247_5241,  // 'BGRA'
            ])
        else { return nil }
        self.surface = surface
        self.width = width
        self.height = height
        surface.lock(options: [], seed: nil)
        defer { surface.unlock(options: [], seed: nil) }
        let bytesPerRow = surface.bytesPerRow
        memset(surface.baseAddress, 0, bytesPerRow * height)
        let rowsPerBand = (height + bands - 1) / bands
        nonisolated(unsafe) let memory = surface.baseAddress
        DispatchQueue.concurrentPerform(iterations: bands) { band in
            let top = band * rowsPerBand
            let rows = min(rowsPerBand, height - top)
            guard rows > 0 else { return }
            let first = max(0, top - margin)
            let last = min(height, top + rows + margin)
            guard
                let ctx = CGContext(
                    data: memory.advanced(by: first * bytesPerRow), width: width,
                    height: last - first,
                    bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return }
            // The context's own coordinates have y up from its last row: the band's rows are
            // (last − top − rows) to (last − top) from the bottom.
            ctx.clip(to: CGRect(x: 0, y: last - top - rows, width: width, height: rows))
            draw(ctx, first, last - first)
            ctx.flush()
        }
    }

    /// A picture whose rows are copied in from elsewhere: the disk cache.
    init?(width: Int, height: Int, rows fill: (UnsafeMutableRawPointer, Int) -> Void) {
        guard
            let surface = IOSurface(properties: [
                .width: width, .height: height, .bytesPerElement: 4,
                .pixelFormat: 0x4247_5241,  // 'BGRA'
            ])
        else { return nil }
        self.surface = surface
        self.width = width
        self.height = height
        surface.lock(options: [], seed: nil)
        fill(surface.baseAddress, surface.bytesPerRow)
        surface.unlock(options: [], seed: nil)
    }

    /// Appends the picture's rows, tightly packed, for the disk cache.
    func appendRows(to data: inout Data) {
        surface.lock(options: .readOnly, seed: nil)
        defer { surface.unlock(options: .readOnly, seed: nil) }
        let row = width * 4
        for index in 0..<height {
            data.append(
                surface.baseAddress.advanced(by: index * surface.bytesPerRow).assumingMemoryBound(
                    to: UInt8.self), count: row)
        }
    }

    /// What the layer shows: the surface itself.
    public var contents: Any { surface }

    /// A copy as a `CGImage`, for tests and the comparison tools.
    public func image() -> CGImage? {
        surface.lock(options: .readOnly, seed: nil)
        defer { surface.unlock(options: .readOnly, seed: nil) }
        let bytes = surface.bytesPerRow * height
        let data = Data(bytes: surface.baseAddress, count: bytes)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: surface.bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    public var bytes: Int { surface.allocationSize }
}
