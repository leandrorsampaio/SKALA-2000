import AppKit
import SwiftUI

/// Renders small SwiftUI test views and samples them, to learn exactly what a SwiftUI
/// drawing primitive does before porting it.
@MainActor
enum Probe {
    static func pixels(_ view: some View, size: CGSize) -> Compare.Pixels {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        return Compare.Pixels(renderer.cgImage!)
    }

    static func run() {
        // Elliptical gradient radii.
        let size = CGSize(width: 400, height: 200)
        let e = pixels(
            ZStack {
                Color.white
                EllipticalGradient(
                    colors: [.black, .white], center: .center, startRadiusFraction: 0,
                    endRadiusFraction: 0.5)
            }, size: size)
        let rowX = (0..<400).filter { e.at($0, 100).0 >= 250 }.first ?? -1
        let colY = (0..<200).filter { e.at(200, $0).0 >= 250 }.first ?? -1
        print(
            "elliptical 0.5 in 400×200: white from x=\(rowX) on the centre row, y=\(colY) on the centre column; centre \(e.at(200, 100).0)"
        )
        print("  samples along x:", stride(from: 200, to: 400, by: 25).map { e.at($0, 100).0 })
        print("  samples along y:", stride(from: 100, to: 200, by: 12).map { e.at(200, $0).0 })

        // Shadow radius: a black square's shadow falloff on white.
        let s = pixels(
            ZStack {
                Color.white
                Rectangle().fill(.black).frame(width: 100, height: 100).shadow(
                    color: .black, radius: 10
                )
                .overlay(Rectangle().fill(.white).frame(width: 100, height: 100))
            }, size: CGSize(width: 200, height: 200))
        print("shadow radius 10, from the edge outward:", (150..<185).map { s.at($0, 100).0 })

        // Blur radius.
        let b = pixels(
            ZStack {
                Color.white
                Rectangle().fill(.black).frame(width: 100, height: 100).blur(radius: 10)
            }, size: CGSize(width: 200, height: 200))
        print("blur radius 10, across the edge at x=150:", (130..<175).map { b.at($0, 100).0 })

        // Linear gradient on a non-square rect, topLeading → bottomTrailing: where is 50%?
        let l = pixels(
            LinearGradient(
                colors: [.black, .white], startPoint: .topLeading, endPoint: .bottomTrailing),
            size: CGSize(width: 400, height: 100))
        print(
            "linear diagonal 400×100: top-right corner \(l.at(399, 0).0), bottom-left \(l.at(0, 99).0), centre \(l.at(200, 50).0)"
        )

        // Alpha-only gradient: black at 100% to black at 0% over white.
        let ag = pixels(
            ZStack {
                Color.white;
                LinearGradient(
                    colors: [.black, .black.opacity(0)], startPoint: .leading, endPoint: .trailing)
            },
            size: CGSize(width: 400, height: 10))
        print(
            "alpha gradient black→clear:", stride(from: 0, to: 400, by: 50).map { ag.at($0, 5).0 })
        // Two colours: red to green.
        let rg = pixels(
            LinearGradient(
                colors: [Color(red: 1, green: 0, blue: 0), Color(red: 0, green: 1, blue: 0)],
                startPoint: .leading, endPoint: .trailing),
            size: CGSize(width: 400, height: 10))
        print("red→green midpoint:", rg.at(200, 5), "quarter:", rg.at(100, 5))
        // Colour to clear: white to clear over black.
        let wc = pixels(
            ZStack {
                Color.black;
                LinearGradient(
                    colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
            },
            size: CGSize(width: 400, height: 10))
        print("white→clear over black:", stride(from: 0, to: 400, by: 50).map { wc.at($0, 5).0 })
        // Core Graphics: a shadow with blur 20 at scale 1, for comparison.
        let ctx = CGContext(
            data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1));
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 20, color: CGColor(gray: 0, alpha: 1))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1));
        ctx.fill(CGRect(x: 50, y: 50, width: 100, height: 100)); ctx.restoreGState()
        ctx.setFillColor(CGColor(gray: 1, alpha: 1));
        ctx.fill(CGRect(x: 50, y: 50, width: 100, height: 100))
        let cg = Compare.Pixels(ctx.makeImage()!)
        print("CG shadow blur 20, from the edge outward:", (150..<185).map { cg.at($0, 100).0 })

        // Text frame and baseline: Dosis 13, one line.
        let t = pixels(
            ZStack(alignment: .topLeading) {
                Color.white
                Text("HHHH").font(.custom("Dosis-SemiBold", fixedSize: 13)).foregroundStyle(.black)
                    .background(Color.red.opacity(0.3))
            }, size: CGSize(width: 100, height: 40))
        let inkRows = (0..<40).filter { y in (0..<60).contains { t.at($0, y).0 < 90 } }
        let boxRows = (0..<40).filter { y in
            (0..<60).contains {
                let p = t.at($0, y); return p.0 > 200 && p.1 < 220
            }
        }
        print(
            "Dosis 13 frame rows \(boxRows.first ?? -1)…\(boxRows.last ?? -1), ink rows \(inkRows.first ?? -1)…\(inkRows.last ?? -1)"
        )
    }
}
