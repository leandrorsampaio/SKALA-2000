import ConsoleKit
import CoreGraphics
import Foundation

/// The parts of the desk that move or light, each drawn once into its own small image.
/// The view only moves, swaps and fades them.
///
/// Every function draws in desk units with the origin at the element's own top-left corner,
/// exactly where the reference drew it; the sprite's frame adds a margin for glow and
/// shadow around that.
enum SpritePainters {

    // MARK: - Lamp window, lit

    /// Everything a lit window adds over the unlit one: the spill of light on the paint
    /// around it (not under its bezel), the lit glass with its two bulb spots, the lettering
    /// in the lit ink, the glass, and the bezel's inner edge catching the lamp.
    static func lampLit(_ pen: Pen, element: DeskLayout.Element, style: ArtStyle) {
        let palette = style.palette
        let color = LampColor(rawValue: element.text("color")) ?? .white
        let glass = palette.glass(color)
        let rect = element.rect

        // The spill: under the bezel in the reference, so the bezel's own area is left out.
        pen.save {
            let outside = CGMutablePath()
            outside.addRect(rect.insetBy(dx: -60, dy: -60))
            outside.addPath(Pen.rect(rect, radius: 4))
            pen.ctx.addPath(outside)
            pen.ctx.clip(using: .evenOdd)
            pen.blurred(
                radius: palette.spillRadius / 2, color: glass.on.opacity(palette.spillOpacity)
            ) {
                pen.fill(Pen.rect(rect.insetBy(dx: -5, dy: -5), radius: 4), rgb(0x000000))
            }
        }

        let pane = rect.insetBy(dx: 4, dy: 4)
        pen.clip(Pen.rect(pane, radius: 1)) {
            pen.fill(pane, glass.on)
            pen.linear(pane, [(white(0.10), 0), (black(0.10), 1)], from: .top, to: .bottom)
            hotSpots(pen, pane: pane, hot: glass.hot)
            LampLettering(element: element, style: style).draw(
                pen, ink: glass.inkOn, halo: glass.lightInk)
            StaticPainter(pen: pen, style: style).glassFace(pane)
        }
        pen.strokeBorder(pane, radius: 1, glass.hot.opacity(0.42), width: 1.5)
    }

    /// The two soft bulb spots at 24% and 76% across, falling off to nothing by the centre.
    static func hotSpots(_ pen: Pen, pane: CGRect, hot: CGColor) {
        let w = pane.width
        let h = pane.height
        for x in [0.24, 0.76] as [CGFloat] {
            let frame = CGRect(
                x: pane.minX + w * x - w * 0.34, y: pane.minY + h / 2 - h * 1.1, width: w * 0.68,
                height: h * 2.2)
            pen.elliptical(
                Pen.rect(pane), [(hot, 0), (hot.opacity(0.6), 0.45), (hot.opacity(0), 1)],
                center: .center, frame: frame)
        }
    }

    // MARK: - Lens, lit

    static func lensLit(_ pen: Pen, rect: CGRect, color: LampColor, palette: Palette) {
        let glass = palette.glass(color)
        // The glow a lit lens spills on the paint, over the collar as in the reference.
        pen.blurred(radius: palette.spillRadius / 2, color: glass.on.opacity(palette.spillOpacity))
        {
            pen.fill(Pen.circle(rect.insetBy(dx: -5, dy: -5)), rgb(0x000000))
        }
        let pane = rect.insetBy(dx: 6, dy: 6)
        pen.clip(Pen.circle(pane)) {
            pen.fill(pane, glass.on)
            pen.radial(
                Pen.circle(pane),
                [(white(1), 0), (white(1), 0.09), (white(0.6), 0.2), (white(0), 0.52)],
                center: CGPoint(x: 0.5, y: 0.54), in: pane, endRadius: 16)
            pen.radial(
                Pen.circle(pane), [(black(0), 0), (black(0.4), 1)], center: .center, in: pane,
                startRadius: 9, endRadius: 16)
            LensDome.draw(pen, pane: pane)
        }
        pen.strokeBorderCircle(pane, rgb(0x0D0D0C), width: 1.5)
    }

    // MARK: - Square cap

    enum CapTone: String { case cream, amber, red }

    static func glass(_ tone: CapTone, _ palette: Palette) -> LampGlass {
        switch tone {
        case .cream: palette.glass(.white)
        case .amber: palette.glass(.amber)
        case .red: palette.glass(.red)
        }
    }

    /// The cap's face in its hole: 52 units square inside the 64-unit frame, drawn at its
    /// own origin. `lit` is the machine's answer; `bright` the no-answer blink.
    static func capFace(
        _ pen: Pen, text: String, tone: CapTone, lit: Bool, bright: Bool, style: ArtStyle,
        textRect: CGRect?
    ) {
        let palette = style.palette
        let glass = glass(tone, palette)
        let face = CGRect(x: 0, y: 0, width: 52, height: 52)
        let shape = Pen.rect(face, radius: 6)
        func body() {
            pen.fill(shape, tone == .red ? glass.on : (lit ? glass.on : glass.off))
            if lit {
                pen.radial(
                    shape, [(glass.hot, 0), (glass.hot.opacity(0), 1)], center: .center, in: face,
                    endRadius: 32)
            }
            pen.linear(
                shape, [(white(0.34), 0), (white(0), 0.38), (black(0.2), 1)], from: .top,
                to: .bottom,
                in: face)
            let letters = Pen.Style(
                font: DeskFonts.barlowBold, size: 15, tracking: 0.9,
                color: lit ? glass.inkOn : glass.inkOff)
            let rect = textRect ?? face
            if lit && glass.lightInk {
                pen.shadow(white(0.55), radius: 2.5, group: face) {
                    pen.text(text.uppercased(), letters, in: rect)
                }
            } else {
                pen.text(text.uppercased(), letters, in: rect)
            }
        }
        if bright {
            // SwiftUI's `.brightness(0.25)`: a quarter added to every channel.
            pen.save {
                pen.ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                body()
                pen.ctx.setBlendMode(.plusLighter)
                pen.clip(shape) {
                    pen.fill(face, CGColor(srgbRed: 0.25, green: 0.25, blue: 0.25, alpha: 1))
                }
                pen.ctx.endTransparencyLayer()
            }
        } else {
            body()
        }
        pen.bevel(face, radius: 6, light: 0.65, dark: 0.28)
    }

    /// The soft shadow a raised cap throws into its hole.
    static func capShadow(_ pen: Pen) {
        let face = CGRect(x: 0, y: 0, width: 52, height: 52)
        pen.shadow(black(0.65), radius: 2, y: 3) {
            pen.fill(Pen.rect(face, radius: 6), rgb(0x000000))
        }
        // Only the shadow: the cap itself is its own layer.
        pen.save {
            pen.ctx.setBlendMode(.clear)
            pen.fill(Pen.rect(face, radius: 6), rgb(0x000000))
        }
    }

    /// The light a lit cap spills around itself.
    static func capGlow(_ pen: Pen, tone: CapTone, palette: Palette) {
        let glass = glass(tone, palette)
        let face = CGRect(x: 0, y: 0, width: 52, height: 52)
        // A shadow in the lamp's colour, as the reference casts it; the face covers the rest.
        pen.shadow(glass.on.opacity(palette.spillOpacity), radius: 11) {
            pen.fill(Pen.rect(face, radius: 6), rgb(0x000000))
        }
        pen.save {
            pen.ctx.setBlendMode(.clear)
            pen.fill(Pen.rect(face, radius: 6), rgb(0x000000))
        }
    }

    /// The shadow the hole throws across a sunk cap.
    static func holeShadow(_ pen: Pen) {
        let face = CGRect(x: 0, y: 0, width: 52, height: 52)
        pen.linear(
            Pen.rect(face, radius: 6), [(black(0.85), 0), (black(0), 0.25)], from: .top,
            to: .bottom, in: face)
    }

    // MARK: - Round cap

    /// Black bakelite, never lit: 48 units inside its 64-unit collar.
    static func roundFace(_ pen: Pen, text: String, style: ArtStyle, textRect: CGRect?) {
        let face = CGRect(x: 0, y: 0, width: 48, height: 48)
        pen.radial(
            Pen.circle(face), [(rgb(0x66665F), 0), (rgb(0x2A2A27), 0.38), (rgb(0x0C0C0B), 1)],
            center: CGPoint(x: 0.38, y: 0.28), in: face, endRadius: 30)
        pen.text(
            text.uppercased(),
            Pen.Style(
                font: DeskFonts.barlowBold, size: 14, tracking: 0.84, color: style.palette.engraving
            ),
            in: textRect ?? face)
    }

    static func roundShadow(_ pen: Pen) {
        let face = CGRect(x: 0, y: 0, width: 48, height: 48)
        pen.shadow(black(0.7), radius: 2, y: 3) { pen.fill(Pen.circle(face), rgb(0x000000)) }
        pen.save {
            pen.ctx.setBlendMode(.clear)
            pen.fill(Pen.circle(face), rgb(0x000000))
        }
    }

    // MARK: - Guard

    /// Plain translucent red acrylic, without its shadow: the flap is 12 units narrower and
    /// shorter than the collar it covers.
    static func flap(_ pen: Pen, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        pen.fill(
            Pen.rect(rect, radius: 4),
            CGColor(srgbRed: 200 / 255, green: 50 / 255, blue: 31 / 255, alpha: 0.74))
        pen.linear(
            rect, radius: 4,
            [(white(0.38), 0), (white(0), 0.28), (white(0), 0.62), (white(0.16), 1)],
            from: CGPoint(x: 0.3, y: 0), to: CGPoint(x: 0.7, y: 1))
        pen.strokeBorder(
            rect, radius: 4, CGColor(srgbRed: 90 / 255, green: 12 / 255, blue: 4 / 255, alpha: 0.9),
            width: 2)
    }

    /// The flap's shadow on the well when it is down.
    static func flapShadow(_ pen: Pen, size: CGSize, raised: Bool) {
        let rect = CGRect(origin: .zero, size: size)
        let (opacity, radius, y): (CGFloat, CGFloat, CGFloat) =
            raised ? (0.35, 5, -6) : (0.5, 2.5, 3)
        pen.shadow(black(opacity), radius: radius, y: y) {
            pen.fill(Pen.rect(rect, radius: 4), rgb(0x000000))
        }
        pen.save {
            pen.ctx.setBlendMode(.clear)
            pen.fill(Pen.rect(rect, radius: 4), rgb(0x000000))
        }
    }

    /// The hinge rod across the collar's top edge.
    static func hinge(_ pen: Pen, width: CGFloat) {
        let rod = CGRect(x: 0, y: 0, width: width, height: 7)
        pen.shadow(black(0.6), radius: 1, y: 1) {
            pen.linear(
                Pen.capsule(rod), [(rgb(0xF0F1EC), 0), (rgb(0x7D8079), 0.55), (rgb(0xB9BBB4), 1)],
                from: .top, to: .bottom, in: rod)
        }
    }

    /// F10's key slot, upright; the layer turns it.
    static func keySlot(_ pen: Pen) {
        pen.fill(CGRect(x: 0, y: 0, width: 4, height: 22), rgb(0x111111))
    }

    // MARK: - Nixie

    /// One digit on its cathode, with its halo, centred in a cell of `size`.
    static func nixieGlyph(
        _ pen: Pen, character: Character, xl: Bool, size: CGSize, palette: Palette
    ) {
        guard character != " " else { return }
        let style = Pen.Style(font: DeskFonts.nixie, size: xl ? 60 : 34, color: palette.nixieGlow)
        let rect = CGRect(origin: .zero, size: size)
        pen.shadow(palette.nixieHalo.opacity(0.5), radius: 9, group: rect) {
            pen.shadow(palette.nixieHalo, radius: 4.5, group: rect) {
                pen.text(String(character), style, in: rect)
            }
        }
    }

    /// The glass over a row of tubes: the deep shadow across its top, a soft dark rim, one
    /// faint sheen. Fixed, and over the digits.
    static func nixieGlass(_ pen: Pen, pane: CGRect) {
        pen.clip(Pen.rect(pane, radius: 1)) {
            pen.linear(pane, [(black(0.75), 0), (black(0), 0.18)], from: .top, to: .bottom)
            pen.blurred(radius: 1, color: black(0.5)) {
                pen.strokeBorder(pane, radius: 1, rgb(0x000000), width: 1)
            }
            pen.linear(
                pane, [(white(0.16), 0), (white(0.04), 0.40), (white(0), 0.41)],
                from: CGPoint(x: 0.43, y: 0), to: CGPoint(x: 0.57, y: 1))
        }
    }

    // MARK: - Drum

    /// A wheel's digits twice round and 0 again, top to bottom, one wheel-height apart: the
    /// strip rolls up behind the window, and a roll from any digit to any other, forward
    /// only, fits on it.
    static let stripCells = 21

    static func drumStrip(_ pen: Pen, wheel: CGSize, palette: Palette) {
        for index in 0..<stripCells {
            let cell = CGRect(
                x: 0, y: CGFloat(index) * wheel.height, width: wheel.width, height: wheel.height)
            pen.text(
                String(index % 10),
                Pen.Style(font: DeskFonts.barlowSemiBold, size: 24, color: palette.drumInk),
                in: cell)
        }
    }

    /// Over the wheels: the black line between each, the window's top shadow and sheen.
    static func drumGlass(_ pen: Pen, window: CGRect, wheels: [CGRect]) {
        for wheel in wheels {
            pen.fill(
                CGRect(x: wheel.minX, y: wheel.minY, width: 1, height: wheel.height), rgb(0x000000))
        }
        pen.linear(window, [(black(0.75), 0), (black(0), 0.2)], from: .top, to: .bottom)
        pen.linear(
            window, [(white(0.16), 0), (white(0.04), 0.40), (white(0), 0.41)],
            from: CGPoint(x: 0.43, y: 0), to: CGPoint(x: 0.57, y: 1))
    }

    // MARK: - Meters

    /// The needle, upright, its pivot at the bottom centre of a 2.5 × 84 bar.
    static func needle(_ pen: Pen) {
        pen.fill(CGRect(x: 0, y: 0, width: 2.5, height: 84), rgb(0x111111))
    }

    /// The glass over a dial: the housing's shadow across the top, one soft diagonal band
    /// of room light, a dark rim.
    static func meterGlass(_ pen: Pen, size: CGSize, radius: CGFloat) {
        let rect = CGRect(origin: .zero, size: size)
        pen.clip(Pen.rect(rect, radius: radius)) {
            pen.linear(
                rect, [(black(0.55), 0), (black(0.12), 0.12), (black(0), 0.3)], from: .top,
                to: .bottom)
            pen.blurred(radius: max(3, size.width * 0.03), color: white(1)) {
                pen.linear(
                    rect,
                    [(white(0), 0), (white(0.2), 0.18), (white(0.08), 0.34), (white(0), 0.5)],
                    from: .topLeading, to: CGPoint(x: 1, y: 0.35))
            }
            pen.strokeBorder(rect, radius: radius, black(0.6), width: 2)
        }
    }

    /// The moving-coil meter's pivot cap, over the needle.
    static func pivot(_ pen: Pen) {
        pen.fill(Pen.circle(center: CGPoint(x: 110, y: 118), radius: 7), rgb(0x111111))
    }

    /// The battery meter's red pointer, pointing left at y = 0.
    static func pointer(_ pen: Pen) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 12, y: 0))
        path.addLine(to: CGPoint(x: 40, y: -5))
        path.addLine(to: CGPoint(x: 40, y: 5))
        path.closeSubpath()
        pen.fill(path, rgb(0xC8321F))
        pen.stroke(path, rgb(0x111111), width: 1)
    }

    // MARK: - Toggle

    /// The MAINS lever, up, in the plate's 72 × 140 frame.
    static func lever(_ pen: Pen) {
        let cx: CGFloat = 36
        let cy: CGFloat = 70
        let lever = CGMutablePath()
        lever.move(to: CGPoint(x: cx - 4, y: cy))
        lever.addLine(to: CGPoint(x: cx - 7.5, y: cy - 36))
        lever.addArc(
            center: CGPoint(x: cx, y: cy - 36), radius: 7.5, startAngle: .pi, endAngle: 0,
            clockwise: false)
        lever.addLine(to: CGPoint(x: cx + 4, y: cy))
        lever.closeSubpath()
        pen.blurred(radius: 3, color: black(0.45)) {
            pen.translate(4, 3) { pen.fill(lever, rgb(0x000000)) }
        }
        pen.linear(
            lever, Pen.even([rgb(0x6F726B), rgb(0xF4F5F0), rgb(0xB4B7AF), rgb(0x55584F)]),
            from: CGPoint(x: (cx - 8) / 72, y: 0), to: CGPoint(x: (cx + 8) / 72, y: 0),
            in: CGRect(x: 0, y: 0, width: 72, height: 140))
        pen.stroke(lever, rgb(0x33352F), width: 1)
        pen.fill(Pen.circle(CGRect(x: cx - 5, y: cy - 41, width: 6, height: 6)), white(0.7))
        pen.fill(Pen.circle(CGRect(x: cx - 7.5, y: cy - 7.5, width: 15, height: 15)), rgb(0xB4B7AF))
    }

    // MARK: - Buzzer

    /// The buzzer behind its grille, whole: it trembles as one while it sounds.
    static func buzzer(_ pen: Pen, palette: Palette) {
        let rect = CGRect(x: 0, y: 0, width: 96, height: 96)
        pen.shadow(black(0.4), radius: 2, y: 2) {
            pen.fill(Pen.circle(rect.insetBy(dx: -3, dy: -3)), rgb(0x3B3B37))
        }
        pen.clip(Pen.circle(rect)) {
            var y: CGFloat = 0
            while y < 96 {
                pen.fill(CGRect(x: 0, y: y, width: 96, height: 5), palette.bakelite)
                pen.fill(CGRect(x: 0, y: y + 5, width: 96, height: 5), palette.enamelRecess)
                y += 10
            }
        }
        pen.strokeBorderCircle(rect, rgb(0x1C1C1A), width: 4)
        pen.linear(
            Pen.circle(rect), [(black(0.7), 0), (black(0), 1)], from: .top,
            to: CGPoint(x: 0.5, y: 0.2), in: rect)
    }

    // MARK: - Paper

    /// A project name in pencil, twelve characters at most; a long one is written smaller
    /// rather than off the edge.
    static func pencil(_ pen: Pen, text: String, size: CGSize) {
        guard !text.isEmpty else { return }
        let inner = CGRect(x: 4, y: 0, width: size.width - 8, height: size.height)
        var fontSize: CGFloat = 22
        let style = Pen.Style(font: DeskFonts.pencil, size: fontSize, color: rgb(0x4A4A48))
        if let line = pen.lines(text, style).first {
            let width = Pen.width(line)
            if width > inner.width { fontSize = max(22 * 0.55, 22 * inner.width / width) }
        }
        pen.text(
            text, Pen.Style(font: DeskFonts.pencil, size: fontSize, color: rgb(0x4A4A48)), in: inner
        )
    }

    /// The PROGRAM BUILD card's typed version.
    static func programBuild(_ pen: Pen, text: String, size: CGSize, palette: Palette) {
        pen.text(
            text, Pen.Style(font: DeskFonts.typewriter, size: 18, color: palette.tagInk),
            in: CGRect(origin: .zero, size: size))
    }
}

/// The session selector, drawn at its native 240 units.
enum SelectorArt {

    static func onDial(_ angle: CGFloat, _ r: CGFloat) -> CGPoint {
        CGPoint(x: 120 + r * cos(angle), y: 120 + r * sin(angle))
    }

    static func plate(_ pen: Pen, palette: Palette) {
        let centre = CGPoint(x: 120, y: 120)
        let dial = Pen.circle(center: centre, radius: 114)
        pen.linear(
            dial, [(rgb(0xECEEE8), 0), (rgb(0xC3C5BD), 0.45), (rgb(0x9DA097), 1)],
            from: .zero, to: CGPoint(x: 1, y: 1), in: CGRect(x: 0, y: 0, width: 240, height: 240))
        pen.stroke(dial, rgb(0x2A2A27), width: 2)
        pen.stroke(Pen.circle(center: centre, radius: 110), white(0.45), width: 1)

        for index in 0..<4 {
            let degrees: CGFloat = -90 + 60 * CGFloat(index) - 90
            let angle = degrees * .pi / 180
            let tick = CGMutablePath()
            tick.move(to: onDial(angle, 66))
            tick.addLine(to: onDial(angle, 78))
            pen.stroke(tick, rgb(0x1B1B19), width: 3)
            pen.text(
                String(index + 1),
                Pen.Style(font: DeskFonts.barlowBold, size: 30, color: palette.tagInk),
                centeredAt: onDial(angle, 96))
        }
        for x in [CGFloat(-62), 62] {
            let pin = Pen.circle(center: CGPoint(x: centre.x + x, y: centre.y + 78), radius: 4.5)
            pen.fill(pin, rgb(0xB4B7AF))
            pen.stroke(pin, rgb(0x2A2A27), width: 1)
        }

        pen.blurred(radius: 4, color: black(0.55)) {
            pen.fill(Pen.circle(center: CGPoint(x: 125, y: 128), radius: 56), rgb(0x000000))
        }
        let skirt = Pen.circle(center: centre, radius: 54)
        pen.clip(skirt) {
            pen.ctx.drawRadialGradient(
                Pen.gradient([(rgb(0x5B5B55), 0), (rgb(0x262624), 0.45), (rgb(0x080807), 1)]),
                startCenter: CGPoint(x: 99, y: 92), startRadius: 0,
                endCenter: CGPoint(x: 99, y: 92),
                endRadius: 92, options: [.drawsAfterEndLocation])
        }
        pen.stroke(skirt, rgb(0x000000), width: 1.5)
    }

    /// The parts that turn: the knurling, the bar grip with its white index line, the
    /// screw. Upright, pointing at 12 o'clock, in the 240-unit frame.
    static func knob(_ pen: Pen) {
        let c = CGPoint(x: 120, y: 120)
        // `stroke`, not `strokeBorder`: the dashes straddle the 102-unit circle.
        let knurl = Pen.circle(center: c, radius: 51)
        pen.save {
            pen.ctx.setLineDash(phase: 0, lengths: [3.2, 3.475])
            pen.stroke(knurl, black(0.75), width: 5)
        }
        let bar = CGRect(x: c.x - 15, y: c.y - 60, width: 30, height: 120)
        pen.blurred(radius: 4, color: black(0.5)) {
            pen.fill(Pen.rect(bar.offsetBy(dx: 3, dy: 5), radius: 13), rgb(0x000000))
        }
        pen.linear(
            bar, radius: 13,
            [
                (rgb(0x0B0B0A), 0), (rgb(0x4E4E49), 0.3), (rgb(0x2C2C29), 0.5),
                (rgb(0x141413), 0.8), (rgb(0x050505), 1),
            ],
            from: .leading, to: .trailing)
        pen.strokeBorder(bar, radius: 13, rgb(0x000000), width: 1)
        pen.fill(
            Pen.rect(CGRect(x: c.x - 1.75, y: c.y - 38 - 17, width: 3.5, height: 34), radius: 1.5),
            rgb(0xF1EFE6))
        let screw = CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)
        pen.linear(
            Pen.circle(screw),
            Pen.even([rgb(0x6F726B), rgb(0xF4F5F0), rgb(0xB4B7AF), rgb(0x55584F)]),
            from: .leading, to: .trailing, in: screw)
        pen.strokeBorderCircle(screw, rgb(0x111111), width: 1)
        pen.fill(CGRect(x: c.x - 6, y: c.y - 1, width: 12, height: 2), rgb(0x222222))
    }

    /// The specular highlight, fixed to the room: if it turned with the knob it would look
    /// like a sticker.
    static func highlight(_ pen: Pen) {
        let rect = CGRect(x: 120 - 54, y: 120 - 54, width: 108, height: 108)
        pen.radial(
            Pen.circle(rect), [(white(0.35), 0), (white(0), 1)], center: CGPoint(x: 0.35, y: 0.25),
            in: rect,
            endRadius: 65)
    }
}
