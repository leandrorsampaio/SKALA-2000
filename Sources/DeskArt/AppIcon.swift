import ConsoleKit
import CoreGraphics
import Foundation

/// The app's icon, drawn with the desk's own painters: a grey-green enamel plate screwed
/// to nothing, its bakelite nameplate, and "2000" burning on four XL nixie tubes.
public enum AppIcon {

    /// The icon at `pixels` square, on the macOS icon grid (an 824-unit plate in 1024).
    public static func image(pixels: Int) -> CGImage? {
        let scale = CGFloat(pixels) / 1024
        return ArtSet.image(frame: CGRect(x: 0, y: 0, width: 1024, height: 1024), scale: scale) {
            pen in
            draw(pen)
        }
    }

    static func draw(_ pen: Pen) {
        let style = ArtStyle(night: false, finish: .greyGreen)
        let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
        let radius: CGFloat = 185
        pen.shadow(black(0.5), radius: 10, y: 12) {
            pen.fill(Pen.rect(plate, radius: radius), style.palette.paint(.greyGreen).ground)
        }
        pen.enamel(plate, radius: radius, finish: .greyGreen, palette: style.palette)
        pen.strokeBorder(plate, radius: radius, style.palette.paint(.greyGreen).edge, width: 3)
        pen.bevel(plate, radius: radius, light: 0.5, dark: 0.45)

        // Everything else at the desk's own proportions, 3.2 times up.
        let k: CGFloat = 3.2
        pen.save {
            pen.ctx.translateBy(x: 512, y: 512)
            pen.ctx.scaleBy(x: k, y: k)
            let scaled = Pen(ctx: pen.ctx, scale: pen.scale * k)
            let inner = StaticPainter(pen: scaled, style: style)
            for (x, y) in [(-108.0, -108.0), (90.0, -108.0), (-108.0, 90.0), (90.0, 90.0)] {
                inner.screw(CGRect(x: x, y: y, width: 18, height: 18), seed: "icon\(x)\(y)")
            }
            inner.plate(
                DeskLayout.Element(
                    kind: "plate", id: "", info: ["text": "SKALA-2000", "style": "title"],
                    rect: CGRect(x: -74, y: -86, width: 148, height: 34)))

            // Four XL tubes, 54 wide, 2 apart, in a bezel of 8 + 4 each side.
            let tubes = CGSize(width: 4 * 54 + 3 * 2, height: 84)
            let housing = CGRect(
                x: -(tubes.width + 24) / 2, y: -34, width: tubes.width + 24,
                height: tubes.height + 14)
            inner.nixieHousing(housing)
            let pane = housing.insetBy(dx: 4, dy: 4)
            for (index, character) in "2000".enumerated() {
                let cell = CGRect(
                    x: pane.minX + 8 + CGFloat(index) * 56, y: pane.minY + 3, width: 54, height: 84)
                scaled.translate(cell.minX, cell.minY) {
                    SpritePainters.nixieGlyph(
                        scaled, character: character, xl: true, size: cell.size,
                        palette: style.palette)
                }
            }
            SpritePainters.nixieGlass(scaled, pane: pane)
        }
    }
}
