import ConsoleKit
import CoreGraphics
import Foundation
import os

/// One image and where it goes, in desk units. The frame is snapped to the device pixel
/// grid it was rendered for, so the image lands pixel for pixel.
public struct Sprite: @unchecked Sendable {
    public let picture: Picture
    public let frame: CGRect
}

/// Everything the desk needs drawn, for one style at one pixel scale: the static art and
/// every sprite. Rendered off the main thread in one go and swapped in whole, so the desk
/// never shows half of one style and half of another.
public final class ArtSet: @unchecked Sendable {

    public let style: ArtStyle
    /// Device pixels per desk unit.
    public let scale: CGFloat
    public let background: Picture

    public struct Cap: @unchecked Sendable {
        public let face: Sprite
        public let lit: Sprite?
        public let bright: Sprite
        public let shadow: Sprite
        public let glow: Sprite?
        public let hole: Sprite?
    }

    public struct Guard: @unchecked Sendable {
        public let flap: Sprite
        public let shadow: Sprite
        public let hinge: Sprite
    }

    public private(set) var lamps: [InstrumentID: Sprite] = [:]
    public private(set) var caps: [InstrumentID: Cap] = [:]
    public private(set) var guards: [InstrumentID: Guard] = [:]
    public private(set) var keySlots: [InstrumentID: Sprite] = [:]
    /// Nixie glyphs by character, for regular and XL tubes, drawn in a cell with room for
    /// their halo: `nixieCell` is where the tube's own cell sits inside the image.
    public private(set) var nixieGlyphs: [Bool: [Character: Picture]] = [:]
    public private(set) var nixieGlyphMargin: CGFloat = 0
    public private(set) var nixieGlass: [InstrumentID: Sprite] = [:]
    public private(set) var drumStrip: Sprite?
    public private(set) var drumGlass: [InstrumentID: Sprite] = [:]
    public private(set) var needle: Sprite?
    public private(set) var meterGlass: [InstrumentID: Sprite] = [:]
    public private(set) var pointer: Sprite?
    public private(set) var knob: Sprite?
    public private(set) var knobHighlight: Sprite?
    public private(set) var lever: Sprite?
    public private(set) var buzzer: Sprite?

    /// Every byte of every picture, for the memory log.
    public var bytes: Int {
        var total = background.bytes
        let sprites: [Sprite?] =
            Array(lamps.values) + Array(keySlots.values) + Array(nixieGlass.values)
            + Array(drumGlass.values) + Array(meterGlass.values)
            + [drumStrip, needle, pointer, knob, knobHighlight, lever, buzzer]
        total += sprites.compactMap { $0?.picture.bytes }.reduce(0, +)
        for cap in caps.values {
            total += [cap.face, cap.lit, cap.bright, cap.shadow, cap.glow, cap.hole].compactMap {
                $0?.picture.bytes
            }
            .reduce(0, +)
        }
        for g in guards.values {
            total += g.flap.picture.bytes + g.shadow.picture.bytes + g.hinge.picture.bytes
        }
        for glyphs in nixieGlyphs.values { total += glyphs.values.map(\.bytes).reduce(0, +) }
        return total
    }

    /// How long the render took, for the performance log.
    public private(set) var renderSeconds: Double = 0

    static let signposts = OSSignposter(
        subsystem: "com.leandrorossisampaio.skala2000", category: "art")

    init(style: ArtStyle, scale: CGFloat, background: Picture) {
        self.style = style
        self.scale = scale
        self.background = background
    }

    // MARK: - Rendering

    /// Renders the whole set. Thread-safe and synchronous: call it off the main thread.
    public static func render(style: ArtStyle, scale: CGFloat) -> ArtSet {
        let state = signposts.beginInterval("render art", "\(style.key) @\(scale)")
        defer { signposts.endInterval("render art", state) }
        let started = Date()
        DeskFonts.register()
        let background = picture(frame: CGRect(origin: .zero, size: DeskLayout.size), scale: scale)
        { pen in
            StaticPainter.paint(into: pen.ctx, scale: scale, style: style)
        }!
        let set = ArtSet(style: style, scale: scale, background: background)
        set.renderSprites()
        set.renderSeconds = Date().timeIntervalSince(started)
        return set
    }

    /// Only the static art, for comparisons.
    public static func renderBackground(style: ArtStyle, scale: CGFloat) -> CGImage {
        DeskFonts.register()
        return picture(frame: CGRect(origin: .zero, size: DeskLayout.size), scale: scale) { pen in
            StaticPainter.paint(into: pen.ctx, scale: scale, style: style)
        }!.image()!
    }

    /// `frame` snapped outward to whole device pixels.
    func snap(_ frame: CGRect) -> CGRect {
        let minX = (frame.minX * scale).rounded(.down) / scale
        let minY = (frame.minY * scale).rounded(.down) / scale
        let maxX = (frame.maxX * scale).rounded(.up) / scale
        let maxY = (frame.maxY * scale).rounded(.up) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Draws into a fresh picture covering `frame` (desk units), with the pen in desk units.
    static func picture(frame: CGRect, scale: CGFloat, _ draw: (Pen) -> Void) -> Picture? {
        let width = max(1, Int((frame.width * scale).rounded()))
        let height = max(1, Int((frame.height * scale).rounded()))
        return Picture(width: width, height: height) { ctx in
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: scale, y: -scale)
            ctx.translateBy(x: -frame.minX, y: -frame.minY)
            ctx.setAllowsFontSmoothing(true)
            ctx.setShouldSmoothFonts(true)
            ctx.interpolationQuality = .high
            draw(Pen(ctx: ctx, scale: scale))
        }
    }

    /// Draws into a fresh image covering `frame` (desk units), with the pen in desk units.
    static func image(
        frame: CGRect, scale: CGFloat, opaque: Bool = false, _ draw: (Pen) -> Void
    ) -> CGImage? {
        let width = max(1, Int((frame.width * scale).rounded()))
        let height = max(1, Int((frame.height * scale).rounded()))
        guard
            let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipFirst : .premultipliedFirst).rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -frame.minX, y: -frame.minY)
        ctx.setAllowsFontSmoothing(true)
        ctx.setShouldSmoothFonts(true)
        ctx.interpolationQuality = .high
        draw(Pen(ctx: ctx, scale: scale))
        return ctx.makeImage()
    }

    func sprite(_ frame: CGRect, _ draw: (Pen) -> Void) -> Sprite {
        let snapped = snap(frame)
        let picture = ArtSet.picture(frame: snapped, scale: scale, draw)!
        return Sprite(picture: picture, frame: snapped)
    }

    /// Draws with the origin moved to `origin`, so the sprite painters' local coordinates
    /// land where the element is.
    func sprite(_ frame: CGRect, origin: CGPoint, _ draw: @escaping (Pen) -> Void) -> Sprite {
        sprite(frame) { pen in pen.translate(origin.x, origin.y) { draw(pen) } }
    }

    private func renderSprites() {
        let palette = style.palette
        let style = self.style

        for element in DeskLayout.all("lamp") where !element.id.isEmpty {
            lamps[InstrumentID(element.id)] = sprite(element.rect.insetBy(dx: -40, dy: -40)) {
                pen in
                SpritePainters.lampLit(pen, element: element, style: style)
            }
        }
        for element in DeskLayout.all("lens") where !element.id.isEmpty {
            let color = LampColor(rawValue: element.text("color")) ?? .white
            lamps[InstrumentID(element.id)] = sprite(element.rect.insetBy(dx: -40, dy: -40)) {
                pen in
                SpritePainters.lensLit(pen, rect: element.rect, color: color, palette: palette)
            }
        }

        for element in DeskLayout.all("cap") {
            let id = InstrumentID(element.id)
            let tone = SpritePainters.CapTone(rawValue: element.text("tone")) ?? .cream
            let face = element.rect.insetBy(dx: 6, dy: 6)
            let text = element.text()
            let textMark = DeskLayout.all("capText", in: element.rect).first?.rect
                .offsetBy(dx: -face.minX, dy: -face.minY)
            // A test button's cap never lights in the machine's colour: it burns while its
            // test shows, which is the same lit face.
            caps[id] = Cap(
                face: sprite(face, origin: face.origin) { pen in
                    SpritePainters.capFace(
                        pen, text: text, tone: tone, lit: false, bright: false, style: style,
                        textRect: textMark)
                },
                lit: sprite(face, origin: face.origin) { pen in
                    SpritePainters.capFace(
                        pen, text: text, tone: tone, lit: true, bright: false, style: style,
                        textRect: textMark)
                },
                bright: sprite(face, origin: face.origin) { pen in
                    SpritePainters.capFace(
                        pen, text: text, tone: tone, lit: false, bright: true, style: style,
                        textRect: textMark)
                },
                shadow: sprite(face.insetBy(dx: -12, dy: -12), origin: face.origin) { pen in
                    SpritePainters.capShadow(pen)
                },
                glow: sprite(face.insetBy(dx: -44, dy: -44), origin: face.origin) { pen in
                    SpritePainters.capGlow(pen, tone: tone, palette: palette)
                },
                hole: sprite(face, origin: face.origin) { pen in SpritePainters.holeShadow(pen) })
        }
        for element in DeskLayout.all("roundCap") {
            let id = InstrumentID(element.id)
            let face = element.rect.insetBy(dx: 8, dy: 8)
            let text = element.text()
            let textMark = DeskLayout.all("roundCapText", in: element.rect).first?.rect
                .offsetBy(dx: -face.minX, dy: -face.minY)
            let faceSprite = sprite(face, origin: face.origin) { pen in
                SpritePainters.roundFace(pen, text: text, style: style, textRect: textMark)
            }
            caps[id] = Cap(
                face: faceSprite, lit: nil, bright: faceSprite,
                shadow: sprite(face.insetBy(dx: -12, dy: -12), origin: face.origin) { pen in
                    SpritePainters.roundShadow(pen)
                }, glow: nil, hole: nil)
        }

        for element in DeskLayout.all("guard") {
            let collar = element.rect
            let flapRect = collar.insetBy(dx: 6, dy: 6)
            let size = flapRect.size
            guards[InstrumentID(element.id)] = Guard(
                flap: sprite(flapRect, origin: flapRect.origin) { pen in
                    SpritePainters.flap(pen, size: size)
                },
                shadow: sprite(flapRect.insetBy(dx: -12, dy: -12), origin: flapRect.origin) { pen in
                    SpritePainters.flapShadow(pen, size: size, raised: false)
                },
                hinge: sprite(
                    CGRect(x: collar.minX, y: collar.minY - 1, width: collar.width, height: 7)
                        .insetBy(dx: -4, dy: -4),
                    origin: CGPoint(x: collar.minX, y: collar.minY - 1)
                ) { pen in SpritePainters.hinge(pen, width: collar.width) })
        }
        for element in DeskLayout.all("key") {
            let slot = CGRect(
                x: element.rect.midX - 2, y: element.rect.midY - 11, width: 4, height: 22)
            keySlots[InstrumentID(element.id)] = sprite(slot, origin: slot.origin) { pen in
                SpritePainters.keySlot(pen)
            }
        }

        // Nixie glyphs: one image per character and size, drawn in the tube's cell with a
        // margin for the halo.
        let margin: CGFloat = 24
        nixieGlyphMargin = margin
        for xl in [false, true] {
            let cell = xl ? CGSize(width: 54, height: 84) : CGSize(width: 28, height: 48)
            var glyphs: [Character: Picture] = [:]
            for character in "0123456789:." {
                let size = character.isNumber ? cell : CGSize(width: 10, height: cell.height)
                let frame = CGRect(
                    x: -margin, y: -margin, width: size.width + 2 * margin,
                    height: size.height + 2 * margin)
                glyphs[character] = ArtSet.picture(frame: frame, scale: scale) { pen in
                    SpritePainters.nixieGlyph(
                        pen, character: character, xl: xl, size: size, palette: palette)
                }
            }
            nixieGlyphs[xl] = glyphs
        }
        for element in DeskLayout.all("nixie") where !element.id.isEmpty {
            let pane = element.rect.insetBy(dx: 4, dy: 4)
            nixieGlass[InstrumentID(element.id)] = sprite(pane) { pen in
                SpritePainters.nixieGlass(pen, pane: pane)
            }
        }

        if let wheel = DeskLayout.all("wheel").first {
            let size = wheel.rect.size
            let cells = CGFloat(SpritePainters.stripCells)
            drumStrip = sprite(CGRect(x: 0, y: 0, width: size.width, height: size.height * cells)) {
                pen in
                SpritePainters.drumStrip(pen, wheel: size, palette: palette)
            }
        }
        for element in DeskLayout.all("drum") where !element.id.isEmpty {
            let window = element.rect.insetBy(dx: 4, dy: 4)
            let wheels = DeskLayout.all("wheel").filter { $0.id == element.id }.map(\.rect)
            drumGlass[InstrumentID(element.id)] = sprite(window) { pen in
                SpritePainters.drumGlass(pen, window: window, wheels: wheels)
            }
        }

        needle = sprite(CGRect(x: 0, y: 0, width: 2.5, height: 84)) { pen in
            SpritePainters.needle(pen)
        }
        for element in DeskLayout.all("dial") where !element.id.isEmpty {
            let dial = element.rect
            meterGlass[InstrumentID(element.id)] = sprite(dial, origin: dial.origin) { pen in
                SpritePainters.pivot(pen)
                SpritePainters.meterGlass(pen, size: dial.size, radius: 6)
            }
        }
        pointer = sprite(CGRect(x: 10, y: -7, width: 32, height: 14)) { pen in
            SpritePainters.pointer(pen)
        }
        for element in DeskLayout.all("edgeDial") where !element.id.isEmpty {
            let dial = element.rect
            meterGlass[InstrumentID(element.id)] = sprite(dial, origin: dial.origin) { pen in
                SpritePainters.meterGlass(pen, size: dial.size, radius: 3)
            }
        }

        if let selector = DeskLayout.all("selector").first {
            let rect = selector.rect
            let k = rect.width / 240
            func scaled(_ draw: @escaping (Pen) -> Void) -> (Pen) -> Void {
                { pen in
                    pen.save {
                        pen.ctx.translateBy(x: rect.minX, y: rect.minY)
                        pen.ctx.scaleBy(x: k, y: k)
                        draw(Pen(ctx: pen.ctx, scale: pen.scale * k))
                    }
                }
            }
            knob = sprite(rect, scaled(SelectorArt.knob))
            knobHighlight = sprite(rect, scaled(SelectorArt.highlight))
        }
        if let toggle = DeskLayout.all("toggle").first {
            lever = sprite(toggle.rect.insetBy(dx: -12, dy: -12), origin: toggle.rect.origin) {
                pen in
                SpritePainters.lever(pen)
            }
        }
        if let element = DeskLayout.all("buzzer").first {
            buzzer = sprite(element.rect.insetBy(dx: -12, dy: -12), origin: element.rect.origin) {
                pen in
                SpritePainters.buzzer(pen, palette: palette)
            }
        }
    }

    // MARK: - Text on paper

    /// A pencil strip's writing, for the paper inside `holder`.
    public func pencil(_ text: String, holder: CGRect) -> Sprite {
        let paper = holder.insetBy(dx: 4, dy: 4)
        return sprite(paper, origin: paper.origin) { pen in
            SpritePainters.pencil(pen, text: text, size: paper.size)
        }
    }

    /// The version typed on the PROGRAM BUILD card.
    public func programBuild(_ text: String, in rect: CGRect) -> Sprite {
        let palette = style.palette
        return sprite(rect, origin: rect.origin) { pen in
            SpritePainters.programBuild(pen, text: text, size: rect.size, palette: palette)
        }
    }
}
