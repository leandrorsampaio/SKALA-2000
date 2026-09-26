import ConsoleKit
import CoreGraphics
import Foundation

/// Paints everything on the desk that never changes, in its dark and off state: paint,
/// plates, tags, screws, bezels and unlit glass, dials, holes, the header, the fuses.
///
/// A port of the reference `PK4Skin` views, one primitive at a time, placed by
/// `DeskLayout`. Thread-safe: it touches nothing but its context, so the art renders off
/// the main thread.
public struct StaticPainter {

    let pen: Pen
    let style: ArtStyle
    var palette: Palette { style.palette }
    var paint: (ground: CGColor, edge: CGColor, ink: CGColor) { palette.paint(style.finish) }

    /// Draws the whole static desk into `ctx`, whose current transform maps desk units to
    /// device pixels with the origin top left.
    public static func paint(into ctx: CGContext, scale: CGFloat, style: ArtStyle) {
        let painter = StaticPainter(pen: Pen(ctx: ctx, scale: scale), style: style)
        painter.paintDesk()
    }

    func all(_ kind: String) -> [DeskLayout.Element] { DeskLayout.all(kind) }

    func paintDesk() {
        pen.fill(CGRect(origin: .zero, size: DeskLayout.size), Palette.surround)
        if let desk = all("desk").first { deskPlate(desk.rect) }
        for panel in all("panel") { self.panel(panel.rect) }
        header()

        // Housings under what sits in them.
        for meter in all("meter") { housing(meter.rect) }
        for meter in all("edgewise") { housing(meter.rect) }
        for guarded in all("guard") { guardWell(guarded) }

        for plate in all("plate") { self.plate(plate) }
        for tag in all("tag") { self.tag(tag) }
        for instruction in all("instruction") { self.instruction(instruction) }
        for blank in all("blanking") { blanking(blank) }
        for caption in all("caption") {
            pen.text(
                caption.text().uppercased(), engraved(12, tracking: 1.08, paint.ink),
                in: caption.rect)
        }
        for unit in all("unit") {
            pen.text(unit.text().uppercased(), label(13, tracking: 0.78, paint.ink), in: unit.rect)
        }
        for numeral in all("numeral") {
            pen.text(numeral.text(), label(30, bold: true, paint.ink), in: numeral.rect)
        }
        for screw in all("screw") { self.screw(screw.rect, seed: screw.id) }

        for lamp in all("lamp") { lampWindow(lamp) }
        for lens in all("lens") {
            lensStatic(lens.rect, color: LampColor(rawValue: lens.text("color")) ?? .white)
        }
        for cap in all("cap") { capWell(cap.rect) }
        for cap in all("roundCap") { roundWell(cap.rect) }
        for key in all("key") { keyPlate(key.rect) }
        for nixie in all("nixie") { nixieHousing(nixie.rect) }
        for drum in all("drum") { drumHousing(drum) }
        for dial in all("dial") { meterDial(dial) }
        for dial in all("edgeDial") { edgewiseDial(dial.rect) }
        for selector in all("selector") { selectorPlate(selector.rect) }
        for toggle in all("toggle") { togglePlate(toggle.rect) }
        for pencil in all("pencil") { pencilHolder(pencil.rect) }
        for fuse in all("fuse") { self.fuse(fuse.rect) }
        for bolt in all("groundBolt") { groundBolt(bolt.rect) }
        for earth in all("earth") { self.earth(earth.rect) }
    }

    // MARK: - Type

    func engraved(_ size: CGFloat, tracking: CGFloat, _ color: CGColor) -> Pen.Style {
        Pen.Style(font: DeskFonts.dosis, size: size, tracking: tracking, color: color)
    }

    func label(
        _ size: CGFloat, bold: Bool = false, tracking: CGFloat = 0, _ color: CGColor
    )
        -> Pen.Style
    {
        Pen.Style(
            font: bold ? DeskFonts.barlowBold : DeskFonts.barlowSemiBold, size: size,
            tracking: tracking, color: color)
    }

    /// Text with hard shadows, as `.shadow(color:radius: 0, y:)` chained: each later shadow
    /// copies everything before it, so the list is drawn last-first under the text.
    func stamped(
        _ text: String, _ style: Pen.Style, in rect: CGRect, shadows: [(CGColor, CGFloat)],
        wrap: Bool = false
    ) {
        for (color, dy) in shadows.reversed() {
            pen.text(text, style, in: rect.offsetBy(dx: 0, dy: dy), wrap: wrap, color: color)
        }
        pen.text(text, style, in: rect, wrap: wrap)
    }

    // MARK: - Paint

    func deskPlate(_ rect: CGRect) {
        pen.enamel(rect, radius: 6, finish: style.finish, palette: palette)
        pen.bevel(rect, radius: 6, light: 0.35, dark: 0.4)
    }

    /// One painted steel plate screwed into the desk.
    ///
    /// SwiftUI's `.shadow` on a container shadows each thing inside it separately, and the
    /// reference relies on that throughout: here the light falloff and the bevel each cast
    /// the panel's shadow across the sheet as well as the sheet casting it on the desk.
    /// Core Graphics shadows each drawing operation separately too, so the port keeps it.
    func panel(_ rect: CGRect) {
        let shape = Pen.rect(rect, radius: 4)
        pen.shadow(black(0.4), radius: 3, y: 2) {
            pen.fill(shape, paint.ground)
            pen.enamel(rect, radius: 4, finish: style.finish, palette: palette)
            pen.strokeBorder(rect, radius: 4, paint.edge, width: 1)
            pen.bevel(rect, radius: 4, light: 0.4, dark: 0.35)
        }
    }

    /// A domed slotted screw in a dark countersink, its slot at an angle of its own.
    func screw(_ rect: CGRect, seed: String) {
        var random = SplitMix64(seed: SplitMix64.seed(seed))
        let angle = CGFloat(random.unit() * 170 - 85)
        let k = rect.width / 20
        pen.translate(rect.minX, rect.minY) {
            func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGPath {
                Pen.circle(
                    CGRect(x: (x - r) * k, y: (y - r) * k, width: 2 * r * k, height: 2 * r * k))
            }
            pen.fill(circle(10, 10.6, 9.4), black(0.45))
            pen.fill(circle(10, 10, 8.6), rgb(0x1D1F1C))
            pen.clip(circle(10, 10, 7.6)) {
                pen.ctx.drawRadialGradient(
                    Pen.gradient([
                        (rgb(0xFFFFFF), 0), (rgb(0xD6D8D1), 0.3), (rgb(0x8B8E86), 0.7),
                        (rgb(0x4C4F48), 1),
                    ]), startCenter: CGPoint(x: 7.2 * k, y: 6 * k), startRadius: 0,
                    endCenter: CGPoint(x: 7.2 * k, y: 6 * k), endRadius: 12 * k,
                    options: [.drawsAfterEndLocation])
            }
            pen.save {
                pen.ctx.translateBy(x: 10 * k, y: 10 * k)
                pen.ctx.rotate(by: angle * .pi / 180)
                pen.fill(
                    Pen.rect(
                        CGRect(x: -7.4 * k, y: -1.1 * k, width: 14.8 * k, height: 2.4 * k),
                        radius: 0.6 * k),
                    rgb(0x15160F))
                pen.fill(
                    CGRect(x: -7.4 * k, y: 1.2 * k, width: 14.8 * k, height: 0.7 * k), white(0.55))
            }
        }
    }

    // MARK: - Plates and tags

    /// Bakelite with its lettering cut in: a dark line above each letter, a faint light
    /// line below.
    func plate(_ element: DeskLayout.Element) {
        let rect = element.rect
        let kind = element.text("style")
        let size: CGFloat = kind == "title" ? 20 : kind == "row" ? 14 : 13
        if kind != "bare" {
            pen.shadow(black(0.45), radius: 1.5, y: 2) {
                pen.linear(
                    rect, radius: 2,
                    [(rgb(0x31312E), 0), (palette.bakelite, 0.55), (rgb(0x0E0E0D), 1)], from: .top,
                    to: .bottom)
                pen.bevel(rect, radius: 2, light: 0.28, dark: 0.7)
            }
        }
        stamped(
            element.text().uppercased(), engraved(size, tracking: size * 0.09, palette.engraving),
            in: rect.insetBy(dx: 8, dy: 4), shadows: [(black(0.95), -1), (white(0.14), 1)],
            wrap: true)
    }

    /// A stamped aluminium designator tag.
    func tag(_ element: DeskLayout.Element) {
        let rect = element.rect
        pen.shadow(black(0.45), radius: 1, y: 1) {
            pen.linear(
                rect, radius: 1, [(rgb(0xECEEE8), 0), (palette.tag, 0.6), (rgb(0xAEB1A8), 1)],
                from: .top, to: .bottom)
            pen.strokeBorder(rect, radius: 1, black(0.45), width: 1)
        }
        stamped(
            element.text(), engraved(11, tracking: 0.44, palette.tagInk),
            in: rect.insetBy(dx: 4, dy: 1), shadows: [(white(0.6), 1)])
    }

    /// A riveted yellow instruction plate.
    func instruction(_ element: DeskLayout.Element) {
        let rect = element.rect
        let shape = Pen.rect(rect, radius: 2)
        pen.shadow(black(0.45), radius: 1.5, y: 2) {
            pen.fill(shape, palette.instruction)
            pen.linear(
                rect, radius: 2, [(white(0.22), 0), (black(0.06), 1)], from: .top, to: .bottom)
            pen.strokeBorder(rect, radius: 2, palette.bezel, width: 1)
        }
        for rivet in DeskLayout.all("rivet", in: rect) { self.rivet(rivet.rect) }
        if let text = DeskLayout.all("instructionText", in: rect).first {
            pen.text(
                element.text().uppercased(), engraved(13, tracking: 1.17, palette.tagInk),
                in: text.rect, wrap: true)
        }
    }

    func rivet(_ rect: CGRect) {
        let shape = Pen.circle(rect)
        pen.shadow(black(0.6), radius: 0.5, y: 1) { pen.fill(shape, rgb(0xC9CBC3)) }
        pen.radial(
            shape, Pen.even([rgb(0xFFFFFF), rgb(0xC9CBC3), rgb(0x6F726B)]),
            center: CGPoint(x: 0.35, y: 0.3), in: rect, endRadius: 5)
    }

    /// A reserved cut-out, covered by a plate of the panel's own paint, raised one level.
    func blanking(_ element: DeskLayout.Element) {
        let rect = element.rect
        pen.shadow(black(0.45), radius: 1.5, y: 1) {
            pen.fill(Pen.rect(rect, radius: 3), paint.ground)
            pen.enamel(rect, radius: 3, finish: style.finish, palette: palette, falloff: false)
            pen.strokeBorder(rect, radius: 3, paint.edge, width: 1)
            pen.bevel(rect, radius: 3, light: 0.4, dark: 0.35)
        }
        pen.text(
            element.text().uppercased(), engraved(13, tracking: 1.17, paint.ink),
            in: rect.insetBy(dx: 6, dy: 6), wrap: true)
    }

    // MARK: - Header

    func header() {
        for title in all("headerTitle") {
            pen.text(
                title.text().uppercased(), label(40, bold: true, tracking: 2.4, paint.ink),
                in: title.rect)
        }
        for subtitle in all("headerSubtitle") {
            pen.text(
                subtitle.text().uppercased(), label(20, tracking: 1.2, paint.ink), in: subtitle.rect
            )
        }
        // The paper card slid into its holder; the version typed on it is live.
        if let card = all("programCard").first {
            pen.shadow(black(0.45), radius: 1.5, y: 2) {
                pen.fill(Pen.rect(card.rect, radius: 2), rgb(0x9A9D95))
            }
            pen.linear(
                card.rect, radius: 2, Pen.even([rgb(0xF4F5F0), rgb(0x9A9D95), rgb(0x74776F)]),
                from: .topLeading, to: .bottomTrailing)
        }
        if let paper = all("programPaper").first { pen.fill(paper.rect, palette.paper) }

        // The riveted aluminium factory nameplate.
        if let plate = all("nameplate").first {
            let rect = plate.rect
            pen.shadow(black(0.45), radius: 1.5, y: 2) {
                pen.linear(
                    rect, radius: 2,
                    [(rgb(0xECEEE8), 0), (palette.aluminium, 0.6), (rgb(0xA4A79F), 1)],
                    from: .top, to: .bottom)
                pen.strokeBorder(rect, radius: 2, black(0.55), width: 1)
            }
            for line in all("nameplateLine") {
                stamped(
                    line.text().uppercased(), engraved(12, tracking: 1.08, palette.tagInk),
                    in: line.rect, shadows: [(white(0.6), 1)])
            }
        }
        // The stockroom's inventory number, painted by hand, crooked.
        if let inventory = all("inventory").first {
            let rect = inventory.rect
            pen.save {
                pen.ctx.translateBy(x: rect.midX, y: rect.midY)
                pen.ctx.rotate(by: -3 * .pi / 180)
                pen.text(
                    inventory.text(),
                    Pen.Style(font: DeskFonts.marker, size: 26, color: palette.stockroomRed),
                    in: CGRect(
                        x: -rect.width / 2, y: -rect.height / 2, width: rect.width,
                        height: rect.height))
            }
        }
    }

    // MARK: - Lamps

    /// The bezel of a lamp window, a nixie row or a drum: dark metal, bevelled, lit from
    /// the top left, with a bright lip below and a soft shadow.
    func bezel(_ rect: CGRect, radius: CGFloat, colors: [CGColor]) {
        let shape = Pen.rect(rect, radius: radius)
        pen.shadows([(white(0.4), 0, 0, 1), (black(0.5), 1.5, 0, 2)], bounds: rect) {
            pen.linear(shape, Pen.even(colors), from: .topLeading, to: .bottomTrailing, in: rect)
        }
    }

    static let bezelColors = [rgb(0x4D4D48), rgb(0x3B3B37), rgb(0x1C1C1A), rgb(0x0C0C0B)]

    /// A lamp window, unlit: bezel, dark glass, its lettering in the unlit ink, the glass.
    func lampWindow(_ element: DeskLayout.Element) {
        let rect = element.rect
        let color = LampColor(rawValue: element.text("color")) ?? .white
        let glass = palette.glass(color)
        bezel(rect, radius: 4, colors: Self.bezelColors)
        let pane = rect.insetBy(dx: 4, dy: 4)
        pen.clip(Pen.rect(pane, radius: 1)) {
            pen.fill(pane, glass.off)
            if style.increasedContrast { pen.fill(pane, black(0.18)) }
            let ink =
                style.increasedContrast
                ? (glass.lightInk ? glass.inkOff : palette.bakelite) : glass.inkOff
            LampLettering(element: element, style: style).draw(pen, ink: ink, halo: false)
            glassFace(pane)
        }
    }

    /// The fixed glass on top of everything: the shadow the bezel throws onto it, a dark
    /// inner line, and one diagonal sheen. It never changes with state.
    func glassFace(_ pane: CGRect, sheen: CGFloat = 0.30) {
        pen.linear(
            pane,
            [(white(sheen), 0), (white(0.08), 0.44), (white(0), 0.45), (black(0.14), 1)],
            from: CGPoint(x: 0.43, y: 0), to: CGPoint(x: 0.57, y: 1))
        pen.linear(pane, [(black(0.55), 0), (black(0), 0.14)], from: .top, to: .bottom)
        pen.strokeBorder(pane, radius: 0, black(0.4), width: 1)
    }

    static let chrome = [
        rgb(0xF6F7F2), rgb(0x8E9189), rgb(0xECEDE7), rgb(0x6C6F68), rgb(0xDCDDD6), rgb(0x868981),
        rgb(0xF6F7F2),
    ]

    /// A round signal lamp, unlit: chrome collar, dark domed glass.
    func lensStatic(_ rect: CGRect, color: LampColor) {
        let glass = palette.glass(color)
        let collar = Pen.circle(rect)
        // The collar and its dark rim each cast the shadow: the rim's falls inside the collar.
        pen.shadow(black(0.55), radius: 1.5, y: 2) {
            pen.angular(collar, Self.chrome, center: .center, in: rect, degrees: 125)
            pen.strokeBorderCircle(rect, palette.bezel, width: 1.5)
        }
        let pane = rect.insetBy(dx: 6, dy: 6)
        pen.clip(Pen.circle(pane)) {
            pen.fill(pane, glass.off)
            pen.radial(
                Pen.circle(pane), [(black(0.28), 0), (black(0.45), 0.45), (black(0.8), 1)],
                center: .center, in: pane, endRadius: 16)
            LensDome.draw(pen, pane: pane)
        }
        pen.strokeBorderCircle(pane, rgb(0x0D0D0C), width: 1.5)
    }

    // MARK: - Buttons

    /// A square button's dark frame and the black hole its cap sinks into.
    func capWell(_ rect: CGRect) {
        let frame = Pen.rect(rect, radius: 10)
        pen.shadow(white(0.4), radius: 0, y: 1) {
            pen.linear(
                frame, Pen.even([rgb(0x55554F), rgb(0x121211)]), from: .topLeading,
                to: .bottomTrailing, in: rect)
            pen.strokeBorder(rect, radius: 10, rgb(0x000000), width: 1)
        }
        pen.fill(Pen.rect(rect.insetBy(dx: 6, dy: 6), radius: 6), rgb(0x050504))
    }

    /// A round button's chrome collar and its hole.
    func roundWell(_ rect: CGRect) {
        pen.shadow(black(0.55), radius: 1.5, y: 2) {
            pen.angular(Pen.circle(rect), Self.chrome, center: .center, in: rect, degrees: 125)
            pen.strokeBorderCircle(rect, palette.bezel, width: 1.5)
        }
        pen.fill(Pen.circle(rect.insetBy(dx: 8, dy: 8)), rgb(0x050504))
    }

    /// The guarded button's cast red collar, hazard-striped well and painted frame. The
    /// flap and the hinge rod over it are layers of their own.
    func guardWell(_ element: DeskLayout.Element) {
        let collar = element.rect
        let shape = Pen.rect(collar, radius: 7)
        pen.shadow(black(0.5), radius: 3, y: 3) {
            pen.linear(
                shape, Pen.even([rgb(0xE4604A), rgb(0xD24431), rgb(0xA3281A), rgb(0x7C1B0F)]),
                from: .topLeading, to: .bottomTrailing, in: collar)
            pen.strokeBorder(
                collar, radius: 7, CGColor(srgbRed: 0.16, green: 0.02, blue: 0.01, alpha: 0.8),
                width: 1)
        }

        let well = collar.insetBy(dx: 5, dy: 5)
        pen.clip(Pen.rect(well, radius: 3)) {
            pen.fill(well, palette.bakelite)
            let stripe: CGFloat = 10 * 1.414
            let h = well.height
            var x = -h
            while x < well.width + h {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: well.minX + x, y: well.minY))
                path.addLine(to: CGPoint(x: well.minX + x + stripe, y: well.minY))
                path.addLine(to: CGPoint(x: well.minX + x + stripe - h, y: well.maxY))
                path.addLine(to: CGPoint(x: well.minX + x - h, y: well.maxY))
                path.closeSubpath()
                pen.fill(path, rgb(0xF0B323))
                x += stripe * 2
            }
            pen.linear(
                well, [(black(0.5), 0), (black(0), 1)], from: .top, to: CGPoint(x: 0.5, y: 0.1))
        }

        let frame = collar.insetBy(dx: 10, dy: 10)
        pen.enamel(frame, radius: 3, finish: style.finish, palette: palette, falloff: false)
        pen.clip(Pen.rect(frame, radius: 3)) {
            pen.linear(
                frame, [(black(0.45), 0), (black(0), 1)], from: .top, to: CGPoint(x: 0.5, y: 0.15))
        }
    }

    /// F10's key switch body; the slot that turns is a layer.
    func keyPlate(_ rect: CGRect) {
        pen.radial(
            Pen.circle(rect),
            [
                (palette.aluminium, 0), (palette.aluminium, 0.43), (rgb(0x8D8D86), 0.46),
                (rgb(0x8D8D86), 0.5), (palette.aluminium, 0.54),
            ], center: .center, in: rect, endRadius: 28)
        pen.strokeBorderCircle(rect, palette.bezel, width: 3)
    }

    // MARK: - Readouts

    /// A nixie row's bezel and dark-orange filter. The digits and the glass over them are
    /// layers.
    func nixieHousing(_ rect: CGRect) {
        bezel(rect, radius: 4, colors: Self.bezelColors)
        let pane = rect.insetBy(dx: 4, dy: 4)
        pen.fill(Pen.rect(pane, radius: 1), palette.nixieGlass)
    }

    /// A drum counter's housing, black window and the shading of each wheel; the digits and
    /// the glass are layers.
    func drumHousing(_ element: DeskLayout.Element) {
        let rect = element.rect
        bezel(rect, radius: 4, colors: [rgb(0x4D4D48), rgb(0x1C1C1A), rgb(0x0C0C0B)])
        let window = rect.insetBy(dx: 4, dy: 4)
        pen.fill(window, rgb(0x111111))
        for wheel in DeskLayout.all("wheel").filter({ $0.id == element.id }) {
            pen.linear(
                wheel.rect,
                [
                    (rgb(0x6F6D64), 0), (palette.drumWheel, 0.3), (rgb(0xFFFFFF), 0.5),
                    (palette.drumWheel, 0.7), (rgb(0x5F5D55), 1),
                ], from: .top, to: .bottom)
        }
    }

    // MARK: - Meters

    func housing(_ rect: CGRect) {
        let shape = Pen.rect(rect, radius: 6)
        pen.shadow(black(0.5), radius: 2.5, y: 3) {
            pen.linear(
                shape, [(rgb(0x3A3A36), 0), (palette.bakelite, 0.4), (rgb(0x0B0B0A), 1)],
                from: CGPoint(x: 0.35, y: 0), to: CGPoint(x: 0.65, y: 1), in: rect)
            pen.bevel(rect, radius: 6, light: 0.3, dark: 0.8)
        }
    }

    /// A moving-coil meter's yellowed dial: a 120° arc, 0 / 50 / 100, an optional red
    /// sector.
    func meterDial(_ element: DeskLayout.Element) {
        let rect = element.rect
        let face = palette.meterFace
        let ink = palette.tagInk
        let centre = CGPoint(x: 110, y: 118)
        let radius: CGFloat = 88
        func point(_ fraction: CGFloat, _ r: CGFloat) -> CGPoint {
            let angle = (210 + 120 * fraction) * .pi / 180
            return CGPoint(x: centre.x + r * cos(angle), y: centre.y + r * sin(angle))
        }
        func arc(_ from: CGFloat, _ to: CGFloat, _ r: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.addArc(
                center: centre, radius: r, startAngle: (210 + 120 * from) * .pi / 180,
                endAngle: (210 + 120 * to) * .pi / 180, clockwise: false)
            return path
        }
        pen.translate(rect.minX, rect.minY) {
            let plate = Pen.rect(CGRect(x: 1, y: 1, width: 218, height: 138), radius: 6)
            pen.fill(plate, face)
            pen.stroke(plate, palette.bezel, width: 2)
            pen.stroke(arc(0, 1, radius), ink, width: 2)
            let red = element.text("red").split(separator: "-").compactMap { Double($0) }
            if red.count == 2 {
                pen.stroke(
                    arc(CGFloat(red[0]), CGFloat(red[1]), radius - 7), rgb(0xC8321F), width: 9)
            }
            for tick in 0...10 {
                let major = tick % 5 == 0
                let path = CGMutablePath()
                path.move(to: point(CGFloat(tick) / 10, radius))
                path.addLine(to: point(CGFloat(tick) / 10, radius - (major ? 14 : 8)))
                pen.stroke(path, ink, width: major ? 2 : 1)
            }
            for (index, text) in ["0", "50", "100"].enumerated() {
                pen.text(text, label(15, ink), centeredAt: point(CGFloat(index) / 2, radius - 28))
            }
            pen.text(
                element.text("unit").uppercased(), label(15, ink),
                centeredAt: CGPoint(x: 110, y: 94))
        }
    }

    /// The battery's narrow profile dial: a straight scale and a red sector from 0 to 20.
    func edgewiseDial(_ rect: CGRect) {
        let ink = palette.tagInk
        let top: CGFloat = 16
        let bottom: CGFloat = 204
        let span = bottom - top
        pen.translate(rect.minX, rect.minY) {
            let plate = Pen.rect(CGRect(x: 1, y: 1, width: 68, height: 218), radius: 3)
            pen.fill(plate, palette.meterFace)
            pen.stroke(plate, palette.bezel, width: 2)
            pen.fill(
                CGRect(x: 6, y: bottom - span * 0.2, width: 6, height: span * 0.2), rgb(0xC8321F))
            for tick in 0...10 {
                let y = bottom - span * CGFloat(tick) / 10
                let major = tick % 5 == 0
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 14, y: y))
                path.addLine(to: CGPoint(x: 14 + (major ? 18 : 10), y: y))
                pen.stroke(path, ink, width: major ? 2 : 1)
                if major {
                    pen.text(
                        String(tick * 10), label(15, ink), centeredAt: CGPoint(x: 62, y: y),
                        anchor: .trailing)
                }
            }
        }
    }

    // MARK: - Selector, toggle, pencil

    /// The session selector's brushed dial with its numerals, stop pins and the bakelite
    /// skirt; the knob that turns is a layer. Drawn at 240 and scaled to the frame.
    func selectorPlate(_ rect: CGRect) {
        let k = rect.width / 240
        pen.save {
            pen.ctx.translateBy(x: rect.minX, y: rect.minY)
            pen.ctx.scaleBy(x: k, y: k)
            let scaled = Pen(ctx: pen.ctx, scale: pen.scale * k)
            SelectorArt.plate(scaled, palette: palette)
        }
    }

    /// MAINS: the brushed plate, its screws, ON and OFF, the nut; the lever is a layer.
    func togglePlate(_ rect: CGRect) {
        let ink = palette.tagInk
        pen.translate(rect.minX, rect.minY) {
            let plate = Pen.rect(CGRect(x: 1, y: 1, width: 70, height: 138), radius: 5)
            pen.linear(
                plate, Pen.even([rgb(0xECEEE8), rgb(0xC3C5BD), rgb(0x9DA097)]),
                from: .zero, to: CGPoint(x: 1, y: 1), in: CGRect(x: 0, y: 0, width: 72, height: 140)
            )
            pen.stroke(plate, rgb(0x2A2A27), width: 2)
            for point in [
                CGPoint(x: 9, y: 9), CGPoint(x: 63, y: 9), CGPoint(x: 9, y: 131),
                CGPoint(x: 63, y: 131),
            ] {
                let screw = Pen.circle(center: point, radius: 3.5)
                pen.fill(screw, rgb(0xB4B7AF))
                pen.stroke(screw, rgb(0x2A2A27), width: 1)
            }
            pen.text("ON", label(12, bold: true, ink), centeredAt: CGPoint(x: 36, y: 15))
            pen.text("OFF", label(12, bold: true, ink), centeredAt: CGPoint(x: 36, y: 126))
            let nut = CGMutablePath()
            for index in 0..<6 {
                let angle = CGFloat(index) * .pi / 3
                let point = CGPoint(x: 36 + 17 * cos(angle), y: 70 + 17 * sin(angle))
                index == 0 ? nut.move(to: point) : nut.addLine(to: point)
            }
            nut.closeSubpath()
            pen.translate(2, 3) { pen.fill(nut, black(0.4)) }
            pen.fill(nut, rgb(0xC9CBC3))
            pen.stroke(nut, rgb(0x33352F), width: 1)
            pen.fill(Pen.circle(CGRect(x: 25, y: 59, width: 22, height: 22)), rgb(0x8A8D85))
            pen.fill(Pen.circle(CGRect(x: 28, y: 62, width: 16, height: 16)), rgb(0x0C0C0B))
        }
    }

    /// A paper strip in its aluminium card holder; the pencil on it is a layer.
    func pencilHolder(_ rect: CGRect) {
        let holder = Pen.rect(rect, radius: 3)
        pen.shadow(black(0.45), radius: 1.5, y: 2) {
            pen.linear(
                holder, Pen.even([rgb(0xF4F5F0), rgb(0xDFE0D9), rgb(0x9A9D95), rgb(0x74776F)]),
                from: .topLeading, to: .bottomTrailing, in: rect)
            pen.strokeBorder(rect, radius: 3, black(0.55), width: 1)
        }
        let paper = rect.insetBy(dx: 4, dy: 4)
        pen.fill(paper, palette.paper)
        pen.linear(
            paper, [(black(0.06), 0), (black(0), 1)], from: .top, to: CGPoint(x: 0.5, y: 0.3))
    }

    // MARK: - Panel E hardware

    /// A fuse holder. Decorative.
    func fuse(_ rect: CGRect) {
        pen.translate(rect.minX, rect.minY) {
            pen.fill(Pen.circle(CGRect(x: 2, y: 3.5, width: 40, height: 40)), black(0.45))
            pen.fill(Pen.circle(CGRect(x: 2.5, y: 2.5, width: 39, height: 39)), rgb(0x2B2B28))
            pen.fill(Pen.circle(CGRect(x: 9, y: 9, width: 26, height: 26)), rgb(0x151513))
            pen.stroke(
                Pen.circle(CGRect(x: 9, y: 9, width: 26, height: 26)), rgb(0x4A4A45), width: 1)
            pen.fill(Pen.circle(CGRect(x: 13, y: 12, width: 8, height: 8)), white(0.22))
            pen.fill(Pen.rect(CGRect(x: 10, y: 20, width: 24, height: 4), radius: 1), rgb(0x050505))
            pen.fill(CGRect(x: 10, y: 24, width: 24, height: 1), white(0.3))
        }
    }

    /// The brass grounding bolt.
    func groundBolt(_ rect: CGRect) {
        pen.translate(rect.minX, rect.minY) {
            let points: [(CGFloat, CGFloat)] = [
                (32, 7), (53, 19), (53, 45), (32, 57), (11, 45), (11, 19),
            ]
            let hexagon = CGMutablePath()
            hexagon.move(to: CGPoint(x: points[0].0, y: points[0].1))
            for point in points.dropFirst() { hexagon.addLine(to: CGPoint(x: point.0, y: point.1)) }
            hexagon.closeSubpath()
            pen.translate(2, 3) { pen.fill(hexagon, black(0.4)) }
            pen.fill(hexagon, palette.brass)
            pen.stroke(hexagon, rgb(0x2A2A27), width: 1.5)
            let face = CGMutablePath()
            face.move(to: CGPoint(x: 32, y: 7))
            face.addLine(to: CGPoint(x: 53, y: 19))
            face.addLine(to: CGPoint(x: 32, y: 32))
            face.addLine(to: CGPoint(x: 11, y: 19))
            face.closeSubpath()
            pen.fill(face, white(0.3))
            let nut = Pen.circle(CGRect(x: 22, y: 22, width: 20, height: 20))
            pen.fill(nut, rgb(0x8A7636))
            pen.stroke(nut, rgb(0x2A2A27), width: 1.5)
        }
    }

    /// The IEC earth symbol: the only pictogram on the desk.
    func earth(_ rect: CGRect) {
        pen.translate(rect.minX, rect.minY) {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 14, y: 2))
            path.addLine(to: CGPoint(x: 14, y: 14))
            path.move(to: CGPoint(x: 2, y: 14))
            path.addLine(to: CGPoint(x: 26, y: 14))
            path.move(to: CGPoint(x: 6, y: 19))
            path.addLine(to: CGPoint(x: 22, y: 19))
            path.move(to: CGPoint(x: 10, y: 24))
            path.addLine(to: CGPoint(x: 18, y: 24))
            pen.stroke(path, paint.ink, width: 2.2)
        }
    }
}

/// A lamp window's lettering: the label, and its HL designator under it.
struct LampLettering {
    let element: DeskLayout.Element
    let style: ArtStyle

    func draw(_ pen: Pen, ink: CGColor, halo: Bool) {
        let rect = element.rect
        let labelText = element.text("label").uppercased()
        let code = element.text("code")
        guard let labelMark = DeskLayout.all("lampLabel", in: rect).first else { return }
        let size = CGFloat(Double(labelMark.text("size")) ?? 13)
        let labelStyle = Pen.Style(
            font: DeskFonts.barlowSemiBold, size: size, tracking: size * 0.06, color: ink,
            lineSpacing: -size * 0.25)
        var labelRect = labelMark.rect
        let codeMark = DeskLayout.all("lampCode", in: rect).first
        if !style.lampCodes, codeMark != nil {
            // Without its designator the label sits alone in the middle of the glass.
            labelRect.origin.y = rect.midY - labelRect.height / 2
        }
        func letters() {
            pen.text(labelText, labelStyle, in: labelRect)
            if style.lampCodes, let codeMark, !code.isEmpty {
                let codeSize = CGFloat(Double(codeMark.text("size")) ?? 10)
                pen.text(
                    code,
                    Pen.Style(
                        font: DeskFonts.barlowSemiBold, size: codeSize, tracking: 0.4, color: ink),
                    in: codeMark.rect)
            }
        }
        if halo {
            pen.shadow(white(0.55), radius: 2.5, group: rect) { letters() }
        } else {
            letters()
        }
    }
}

/// The fixed highlights of a lens's glass dome, over whatever the glass shows.
enum LensDome {
    static func draw(_ pen: Pen, pane: CGRect) {
        let c = CGPoint(x: pane.midX, y: pane.midY)
        let spot = CGRect(x: c.x - 7 - 3.5, y: c.y - 4.5 - 6, width: 14, height: 9)
        pen.radial(
            Pen.circle(spot), [(white(0.7), 0), (white(0), 1)], center: .center, in: spot,
            endRadius: 8)
        let low = CGRect(x: c.x - 4.5 + 3.5, y: c.y - 2 + 10, width: 9, height: 4)
        pen.blurred(radius: 1, color: white(0.14)) { pen.fill(Pen.circle(low), rgb(0x000000)) }
        pen.strokeBorderCircle(pane.insetBy(dx: 6, dy: 6), white(0.10), width: 0.8)
    }
}
