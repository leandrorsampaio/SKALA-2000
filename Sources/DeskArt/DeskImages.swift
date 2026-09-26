import CoreGraphics
import Foundation

/// Image helpers shared by the golden tests and the tools that write their goldens.
public enum DeskImages {

    /// Averaged down two by two, exactly: the same filter for the goldens and for the
    /// renders compared with them.
    public static func halved(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        var source = [UInt8](repeating: 0, count: width * height * 4)
        guard
            let input = CGContext(
                data: &source, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        input.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let w = width / 2
        let h = height / 2
        var target = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                for c in 0..<4 {
                    let a = Int(source[((2 * y) * width + 2 * x) * 4 + c])
                    let b = Int(source[((2 * y) * width + 2 * x + 1) * 4 + c])
                    let d = Int(source[((2 * y + 1) * width + 2 * x) * 4 + c])
                    let e = Int(source[((2 * y + 1) * width + 2 * x + 1) * 4 + c])
                    target[(y * w + x) * 4 + c] = UInt8((a + b + d + e + 2) / 4)
                }
            }
        }
        guard
            let output = CGContext(
                data: &target, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        return output.makeImage()
    }
}
