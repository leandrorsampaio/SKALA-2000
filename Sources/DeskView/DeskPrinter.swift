import AppKit
import ConsoleKit
import CoreImage
import DeskArt
import Metal
import QuartzCore

/// Renders the real layer tree for a snapshot into an image, with no window: the same
/// layers, sprites and art the view shows, composited by Core Animation into a Metal
/// texture. For the golden comparisons and the render tests.
@MainActor
public enum DeskPrinter {

    /// The desk at `scale` pixels per unit, with every animation at its end state.
    public static func image(
        _ snapshot: ConsoleSnapshot, style: ArtStyle, scale: CGFloat
    ) -> CGImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let width = Int((DeskLayout.size.width * scale).rounded())
        let height = Int((DeskLayout.size.height * scale).rounded())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        guard let art = ArtSet.render(style: style, scale: scale) else { return nil }
        let layers = DeskLayers()
        layers.install(art)
        layers.apply(snapshot, animated: false)

        // Our own queue, so we can wait for the GPU before reading the texture back.
        guard let queue = device.makeCommandQueue() else { return nil }
        let renderer = CARenderer(
            mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        root.anchorPoint = .zero
        root.position = .zero
        root.isGeometryFlipped = true
        root.backgroundColor = Palette.surround
        root.addSublayer(layers.desk)
        layers.desk.position = .zero
        layers.desk.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        renderer.layer = root
        renderer.bounds = root.bounds
        CATransaction.commit()
        CATransaction.flush()

        // The first frame prepares the tree; the second draws it whole.
        for _ in 0..<2 {
            renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
            renderer.addUpdate(renderer.bounds)
            renderer.render()
            renderer.endFrame()
        }
        let fence = queue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()

        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(
            &bytes, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0)
        // Core Animation drew with its origin bottom left; the texture's first row is its top.
        var rows = [UInt8](repeating: 0, count: bytes.count)
        for row in 0..<height {
            let from = (height - 1 - row) * bytesPerRow
            rows.replaceSubrange(
                row * bytesPerRow..<(row + 1) * bytesPerRow, with: bytes[from..<from + bytesPerRow])
        }
        let data = Data(rows)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
