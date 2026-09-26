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
