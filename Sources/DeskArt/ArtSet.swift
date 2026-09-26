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
        /// The face sunk into its hole: no shadows, darker, a dimmer bevel.
        public let faceDown: Sprite?
        public let lit: Sprite?
        public let litDown: Sprite?
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

    /// Every sprite by name, as rendered or as read back from the disk cache; the typed
    /// views below are indexed from it.
    public private(set) var sprites: [String: Sprite] = [:]

    public private(set) var lamps: [InstrumentID: Sprite] = [:]
    public private(set) var caps: [InstrumentID: Cap] = [:]
    public private(set) var guards: [InstrumentID: Guard] = [:]
    public private(set) var keySlots: [InstrumentID: Sprite] = [:]
    /// Nixie glyphs by character, for regular and XL tubes, drawn in the tube's cell with
    /// `nixieGlyphMargin` round it for the halo.
    public private(set) var nixieGlyphs: [Bool: [Character: Picture]] = [:]
    public let nixieGlyphMargin: CGFloat = 24
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
        background.bytes + sprites.values.map(\.picture.bytes).reduce(0, +)
    }

    /// Builds the typed views from `sprites`.
    func index() {
        func id(_ name: String, _ prefix: String) -> InstrumentID? {
            name.hasPrefix(prefix) ? InstrumentID(String(name.dropFirst(prefix.count))) : nil
        }
        var glyphs: [Bool: [Character: Picture]] = [false: [:], true: [:]]
        for (name, sprite) in sprites {
            if let lamp = id(name, "lamp:") { lamps[lamp] = sprite }
            if let key = id(name, "key:") { keySlots[key] = sprite }
            if let nixie = id(name, "nixieGlass:") { nixieGlass[nixie] = sprite }
            if let drum = id(name, "drumGlass:") { drumGlass[drum] = sprite }
            if let meter = id(name, "meterGlass:") { meterGlass[meter] = sprite }
            if name.hasPrefix("glyph:"), let character = name.last {
                glyphs[name.hasPrefix("glyph:xl:")]?[character] = sprite.picture
            }
        }
        nixieGlyphs = glyphs
        for element in DeskLayout.all("cap") + DeskLayout.all("roundCap") {
            let key = element.id
            guard let face = sprites["cap.face:\(key)"], let shadow = sprites["cap.shadow:\(key)"]
            else { continue }
            caps[InstrumentID(key)] = Cap(
                face: face, faceDown: sprites["cap.faceDown:\(key)"],
                lit: sprites["cap.lit:\(key)"],
                litDown: sprites["cap.litDown:\(key)"],
                bright: sprites["cap.bright:\(key)"] ?? face,
                shadow: shadow, glow: sprites["cap.glow:\(key)"], hole: sprites["cap.hole:\(key)"])
        }
        for element in DeskLayout.all("guard") {
            let key = element.id
            guard let flap = sprites["guard.flap:\(key)"],
                let shadow = sprites["guard.shadow:\(key)"],
                let hinge = sprites["guard.hinge:\(key)"]
            else { continue }
            guards[InstrumentID(key)] = Guard(flap: flap, shadow: shadow, hinge: hinge)
        }
        drumStrip = sprites["drumStrip"]
        needle = sprites["needle"]
        pointer = sprites["pointer"]
        knob = sprites["knob"]
        knobHighlight = sprites["knobHighlight"]
        lever = sprites["lever"]
        buzzer = sprites["buzzer"]
    }

    init(style: ArtStyle, scale: CGFloat, background: Picture, sprites: [String: Sprite]) {
        self.style = style
        self.scale = scale
        self.background = background
        self.sprites = sprites
        index()
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

    /// Sets how long the render took; for sets read back from disk, how long reading took.
    func took(_ seconds: Double) { renderSeconds = seconds }

    // MARK: - Rendering

    /// Renders the whole set. Thread-safe and synchronous: call it off the main thread.
    public static func render(style: ArtStyle, scale: CGFloat) -> ArtSet {
        let state = signposts.beginInterval("render art", "\(style.key) @\(scale)")
        defer { signposts.endInterval("render art", state) }
        let started = Date()
        DeskFonts.register()
        let background = backgroundPicture(style: style, scale: scale)
        let set = ArtSet(style: style, scale: scale, background: background)
        set.renderSprites()
        set.index()
        set.renderSeconds = Date().timeIntervalSince(started)
        return set
    }

    /// Only the static art, for comparisons.
    public static func renderBackground(style: ArtStyle, scale: CGFloat) -> CGImage {
        DeskFonts.register()
        return backgroundPicture(style: style, scale: scale).image()!
    }

    /// For the tools: how many bands, or `nil` for one per core up to eight.
    public nonisolated(unsafe) static var bandCount: Int?

    /// The static art, drawn in bands on every core. Each band draws the whole desk clipped
    /// to its rows, so where bands meet the pixels are the same as one drawing would give.
    static func backgroundPicture(style: ArtStyle, scale: CGFloat) -> Picture {
        let width = Int((DeskLayout.size.width * scale).rounded())
        let height = Int((DeskLayout.size.height * scale).rounded())
        let bands = bandCount ?? min(8, max(2, ProcessInfo.processInfo.activeProcessorCount))
        return Picture(
            width: width, height: height, bands: bands, margin: Int((48 * scale).rounded(.up))
        ) {
            ctx, top, rows in
            // The band's context has its own origin: row `top` of the whole picture is its
            // top row, so the desk's transform is shifted to match.
            ctx.translateBy(x: 0, y: CGFloat(rows + top))
            ctx.scaleBy(x: scale, y: -scale)
            ctx.setAllowsFontSmoothing(true)
            ctx.setShouldSmoothFonts(true)
            ctx.interpolationQuality = .high
            StaticPainter.paint(into: ctx, scale: scale, style: style)
        }!
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

    /// One sprite to draw: its name, its frame, and how.
    private struct Job {
        let name: String
        let frame: CGRect
        let snapped: Bool
        let draw: (Pen) -> Void
    }

    private var pending: [Job] = []

    private func job(
        _ name: String, _ frame: CGRect, snapped: Bool = true, _ draw: @escaping (Pen) -> Void
    ) {
        pending.append(Job(name: name, frame: frame, snapped: snapped, draw: draw))
    }

    private func job(
        _ name: String, _ frame: CGRect, origin: CGPoint, _ draw: @escaping (Pen) -> Void
    ) {
        job(name, frame) { pen in pen.translate(origin.x, origin.y) { draw(pen) } }
    }

    /// Draws every sprite, on every core: each is independent of the others.
    private func renderSprites() {
        pending = []
        collect()
        let jobs = pending
        pending = []
        let lock = NSLock()
        var done: [String: Sprite] = [:]
        DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
            let job = jobs[index]
            let frame = job.snapped ? snap(job.frame) : job.frame
            guard let picture = ArtSet.picture(frame: frame, scale: scale, job.draw) else { return }
            lock.lock()
            done[job.name] = Sprite(picture: picture, frame: frame)
            lock.unlock()
        }
        sprites = done
    }

    /// Lists every sprite the desk needs.
    private func collect() {
        let palette = style.palette
        let style = self.style

        for element in DeskLayout.all("lamp") where !element.id.isEmpty {
            job("lamp:\(element.id)", element.rect.insetBy(dx: -40, dy: -40)) { pen in
                SpritePainters.lampLit(pen, element: element, style: style)
            }
        }
        for element in DeskLayout.all("lens") where !element.id.isEmpty {
            let color = LampColor(rawValue: element.text("color")) ?? .white
            job("lamp:\(element.id)", element.rect.insetBy(dx: -40, dy: -40)) { pen in
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
            let key = element.id
            job("cap.face:\(key)", face, origin: face.origin) { pen in
                SpritePainters.capFace(
                    pen, text: text, tone: tone, lit: false, bright: false, style: style,
                    textRect: textMark)
            }
            job("cap.faceDown:\(key)", face, origin: face.origin) { pen in
                SpritePainters.capFace(
                    pen, text: text, tone: tone, lit: false, bright: false, down: true,
                    style: style,
                    textRect: textMark)
            }
            job("cap.litDown:\(key)", face, origin: face.origin) { pen in
                SpritePainters.capFace(
                    pen, text: text, tone: tone, lit: true, bright: false, down: true, style: style,
                    textRect: textMark)
            }
            job("cap.lit:\(key)", face, origin: face.origin) { pen in
                SpritePainters.capFace(
                    pen, text: text, tone: tone, lit: true, bright: false, style: style,
                    textRect: textMark)
            }
            job("cap.bright:\(key)", face, origin: face.origin) { pen in
                SpritePainters.capFace(
                    pen, text: text, tone: tone, lit: false, bright: true, style: style,
                    textRect: textMark)
            }
            job("cap.shadow:\(key)", face.insetBy(dx: -12, dy: -12), origin: face.origin) { pen in
                SpritePainters.capShadow(pen)
            }
            job("cap.glow:\(key)", face.insetBy(dx: -44, dy: -44), origin: face.origin) { pen in
                SpritePainters.capGlow(pen, tone: tone, palette: palette)
            }
            job("cap.hole:\(key)", face, origin: face.origin) { pen in
                SpritePainters.holeShadow(pen)
            }
        }
        for element in DeskLayout.all("roundCap") {
            let id = InstrumentID(element.id)
            let face = element.rect.insetBy(dx: 8, dy: 8)
            let text = element.text()
            let textMark = DeskLayout.all("roundCapText", in: element.rect).first?.rect
                .offsetBy(dx: -face.minX, dy: -face.minY)
            job("cap.face:\(element.id)", face, origin: face.origin) { pen in
                SpritePainters.roundFace(pen, text: text, style: style, textRect: textMark)
            }
            job("cap.faceDown:\(element.id)", face, origin: face.origin) { pen in
                SpritePainters.roundFace(
                    pen, text: text, style: style, textRect: textMark, down: true)
            }
            job("cap.shadow:\(element.id)", face.insetBy(dx: -12, dy: -12), origin: face.origin) {
                pen in SpritePainters.roundShadow(pen)
            }
        }

        for element in DeskLayout.all("guard") {
            let collar = element.rect
            let flapRect = collar.insetBy(dx: 6, dy: 6)
            let size = flapRect.size
            job("guard.flap:\(element.id)", flapRect, origin: flapRect.origin) { pen in
                SpritePainters.flap(pen, size: size)
            }
            job(
                "guard.shadow:\(element.id)", flapRect.insetBy(dx: -12, dy: -12),
                origin: flapRect.origin
            ) {
                pen in SpritePainters.flapShadow(pen, size: size, raised: false)
            }
            job(
                "guard.hinge:\(element.id)",
                CGRect(x: collar.minX, y: collar.minY - 1, width: collar.width, height: 7).insetBy(
                    dx: -4, dy: -4),
                origin: CGPoint(x: collar.minX, y: collar.minY - 1)
            ) { pen in SpritePainters.hinge(pen, width: collar.width) }
        }
        for element in DeskLayout.all("key") {
            let slot = CGRect(
                x: element.rect.midX - 2, y: element.rect.midY - 11, width: 4, height: 22)
            job("key:\(element.id)", slot, origin: slot.origin) { pen in
                SpritePainters.keySlot(pen)
            }
        }

        // Nixie glyphs: one image per character and size, drawn in the tube's cell with a
        // margin for the halo.
        let margin = nixieGlyphMargin
        for xl in [false, true] {
            let cell = xl ? CGSize(width: 54, height: 84) : CGSize(width: 28, height: 48)
            for character in "0123456789:." {
                let size = character.isNumber ? cell : CGSize(width: 10, height: cell.height)
                let frame = CGRect(
                    x: -margin, y: -margin, width: size.width + 2 * margin,
                    height: size.height + 2 * margin)
                job("glyph:\(xl ? "xl" : "regular"):\(character)", frame, snapped: false) { pen in
                    SpritePainters.nixieGlyph(
                        pen, character: character, xl: xl, size: size, palette: palette)
                }
            }
        }
        for element in DeskLayout.all("nixie") where !element.id.isEmpty {
            let pane = element.rect.insetBy(dx: 4, dy: 4)
            job("nixieGlass:\(element.id)", pane) { pen in
                SpritePainters.nixieGlass(pen, pane: pane)
            }
        }

        if let wheel = DeskLayout.all("wheel").first {
            let size = wheel.rect.size
            let cells = CGFloat(SpritePainters.stripCells)
            job("drumStrip", CGRect(x: 0, y: 0, width: size.width, height: size.height * cells)) {
                pen in
                SpritePainters.drumStrip(pen, wheel: size, palette: palette)
            }
        }
        for element in DeskLayout.all("drum") where !element.id.isEmpty {
            let window = element.rect.insetBy(dx: 4, dy: 4)
            let wheels = DeskLayout.all("wheel").filter { $0.id == element.id }.map(\.rect)
            job("drumGlass:\(element.id)", window) { pen in
                SpritePainters.drumGlass(pen, window: window, wheels: wheels)
            }
        }

        job("needle", CGRect(x: 0, y: 0, width: 2.5, height: 84)) { pen in
            SpritePainters.needle(pen)
        }
        for element in DeskLayout.all("dial") where !element.id.isEmpty {
            let dial = element.rect
            job("meterGlass:\(element.id)", dial, origin: dial.origin) { pen in
                SpritePainters.pivot(pen)
                SpritePainters.meterGlass(pen, size: dial.size, radius: 6)
            }
        }
        job("pointer", CGRect(x: 10, y: -7, width: 32, height: 14)) { pen in
            SpritePainters.pointer(pen)
        }
        for element in DeskLayout.all("edgeDial") where !element.id.isEmpty {
            let dial = element.rect
            job("meterGlass:\(element.id)", dial, origin: dial.origin) { pen in
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
            job("knob", rect, scaled(SelectorArt.knob))
            job("knobHighlight", rect, scaled(SelectorArt.highlight))
        }
        if let toggle = DeskLayout.all("toggle").first {
            job("lever", toggle.rect.insetBy(dx: -12, dy: -12), origin: toggle.rect.origin) {
                pen in
                SpritePainters.lever(pen)
            }
        }
        if let element = DeskLayout.all("buzzer").first {
            job("buzzer", element.rect.insetBy(dx: -12, dy: -12), origin: element.rect.origin) {
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
