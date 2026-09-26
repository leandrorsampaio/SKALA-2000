import CoreGraphics
import CoreText
import Foundation

/// Core Graphics with SwiftUI's vocabulary: unit-point gradients, `shadow(radius:)`,
/// `blur(radius:)`, `strokeBorder`, tracked text. The painters are ported from SwiftUI
/// views, and this keeps each port a line-for-line translation.
///
/// Drawing is in desk units with the origin top left. `scale` is device pixels per unit,
/// which shadows and blurs need: Core Graphics measures them in device space.
struct Pen {
    let ctx: CGContext
    let scale: CGFloat

    /// SwiftUI's shadow and blur radii, as Core Graphics blur. Calibrated against the
    /// reference renders.
    /// A SwiftUI radius r blurs with a standard deviation of about r; Core Graphics' blur b
    /// with about 0.4 b. Measured, not assumed (see `DeskReference probe`).
    nonisolated(unsafe) static var shadowFactor: CGFloat = 2.35
    nonisolated(unsafe) static var blurFactor: CGFloat = 2.45

    // MARK: - State

    func save(_ body: () -> Void) {
        ctx.saveGState()
        body()
        ctx.restoreGState()
    }

    func clip(_ path: CGPath, _ body: () -> Void) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        body()
        ctx.restoreGState()
    }

    func translate(_ x: CGFloat, _ y: CGFloat, _ body: () -> Void) {
        ctx.saveGState()
        ctx.translateBy(x: x, y: y)
        body()
        ctx.restoreGState()
    }

    /// A SwiftUI `.shadow`. With `group`, everything drawn inside casts one shadow as a
    /// whole, through a transparency layer bounded to that rect; without, each thing drawn
    /// casts its own, which is the same for a single shape and much cheaper.
    func shadow(
        _ color: CGColor, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0, group: CGRect? = nil,
        _ body: () -> Void
    ) {
        ctx.saveGState()
        // Device space has y up; the desk has y down.
        ctx.setShadow(
            offset: CGSize(width: x * scale, height: -y * scale),
            blur: radius * scale * Self.shadowFactor, color: color)
        if let group {
            let margin = radius * 3 + max(abs(x), abs(y)) + 2
            ctx.beginTransparencyLayer(
                in: group.insetBy(dx: -margin, dy: -margin), auxiliaryInfo: nil)
            body()
            ctx.endTransparencyLayer()
        } else {
            body()
        }
        ctx.restoreGState()
    }

    /// Draws `body` with no shadow, inside a scope that has one.
    func unshadowed(_ body: () -> Void) {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        body()
        ctx.restoreGState()
    }

    /// Several shadows applied in turn, the first innermost, as chained SwiftUI modifiers.
    /// Each outer shadow is cast by everything inside it, so they are grouped in `bounds`.
    func shadows(
        _ list: [(color: CGColor, radius: CGFloat, x: CGFloat, y: CGFloat)], bounds: CGRect,
        _ body: () -> Void
    ) {
        guard let last = list.last else {
            body()
            return
        }
        shadow(
            last.color, radius: last.radius, x: last.x, y: last.y,
            group: list.count > 1 ? bounds : nil
        ) {
            shadows(Array(list.dropLast()), bounds: bounds, body)
        }
    }

    /// Draws `body` blurred, as SwiftUI's `.blur(radius:)`. Only the alpha of what is drawn
    /// counts; it comes out in `color`. Done with a shadow thrown from far off the canvas,
    /// so each shape drawn inside blurs on its own: use it for single shapes.
    func blurred(radius: CGFloat, color: CGColor, _ body: () -> Void) {
        let away: CGFloat = 20_000
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: away * scale, height: 0),
            blur: radius * scale * Self.blurFactor, color: color)
        ctx.translateBy(x: -away, y: 0)
        body()
        ctx.restoreGState()
    }

    func opacity(_ alpha: CGFloat, _ body: () -> Void) {
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    // MARK: - Shapes

    static func rect(_ r: CGRect, radius: CGFloat = 0) -> CGPath {
        radius <= 0
            ? CGPath(rect: r, transform: nil)
            : CGPath(
                roundedRect: r, cornerWidth: min(radius, r.width / 2),
                cornerHeight: min(radius, r.height / 2), transform: nil)
    }

    static func circle(_ r: CGRect) -> CGPath { CGPath(ellipseIn: r, transform: nil) }

    static func circle(center: CGPoint, radius: CGFloat) -> CGPath {
        CGPath(
            ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius),
            transform: nil)
    }

    static func capsule(_ r: CGRect) -> CGPath { rect(r, radius: min(r.width, r.height) / 2) }

    // MARK: - Fills

    func fill(_ path: CGPath, _ color: CGColor) {
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    func fill(_ rect: CGRect, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.fill(rect)
    }

    func stroke(_ path: CGPath, _ color: CGColor, width: CGFloat) {
        ctx.addPath(path)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.strokePath()
    }

    /// SwiftUI's `strokeBorder`: the stroke lies inside the shape.
    func strokeBorder(_ rect: CGRect, radius: CGFloat, _ color: CGColor, width: CGFloat) {
        let inset = rect.insetBy(dx: width / 2, dy: width / 2)
        stroke(Pen.rect(inset, radius: max(0, radius - width / 2)), color, width: width)
    }

    func strokeBorderCircle(_ rect: CGRect, _ color: CGColor, width: CGFloat) {
        stroke(Pen.circle(rect.insetBy(dx: width / 2, dy: width / 2)), color, width: width)
    }

    /// A gradient as SwiftUI draws it: colours mix in Oklab, a perceptual space, so a
    /// black-to-white ramp is 39% grey at its middle, not 50%; alpha mixes linearly.
    /// Measured on the reference (see `DeskReference probe`). Core Graphics mixes in sRGB,
    /// so each span is sampled into short sRGB steps.
    static func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func rgba(_ color: CGColor) -> [CGFloat] {
            let c = color.converted(to: space, intent: .defaultIntent, options: nil) ?? color
            let parts = c.components ?? [0, 0, 0, 1]
            return parts.count >= 4
                ? Array(parts.prefix(4)) : [parts[0], parts[0], parts[0], parts.last ?? 1]
        }
        var colors: [CGFloat] = []
        var locations: [CGFloat] = []
        for index in stops.indices {
            let (color, location) = stops[index]
            let a = rgba(color)
            if index == 0 {
                colors += a
                locations.append(location)
                continue
            }
            var from = rgba(stops[index - 1].0)
            var to = a
            // A clear end takes the other end's colour, as premultiplied mixing does.
            if from[3] == 0 { from = [to[0], to[1], to[2], 0] }
            if to[3] == 0 { to = [from[0], from[1], from[2], 0] }
            let start = stops[index - 1].1
            let sameColour = from[0] == to[0] && from[1] == to[1] && from[2] == to[2]
            let steps = sameColour || location <= start ? 1 : 12
            let labFrom = Oklab(srgb: from), labTo = Oklab(srgb: to)
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let mixed = labFrom.mixed(with: labTo, t).srgb
                colors += [mixed[0], mixed[1], mixed[2], from[3] + (to[3] - from[3]) * t]
                locations.append(start + (location - start) * t)
            }
        }
        return CGGradient(
            colorSpace: space, colorComponents: colors, locations: locations,
            count: locations.count)!
    }

    /// Evenly spaced, as SwiftUI spaces `colors:`.
    static func even(_ colors: [CGColor]) -> [(CGColor, CGFloat)] {
        guard colors.count > 1 else { return colors.map { ($0, 0) } }
        return colors.enumerated().map {
            ($0.element, CGFloat($0.offset) / CGFloat(colors.count - 1))
        }
    }

    /// `LinearGradient(stops:startPoint:endPoint:)` filling `path`, with the unit points
    /// taken in `frame`.
    func linear(
        _ path: CGPath, _ stops: [(CGColor, CGFloat)], from start: CGPoint, to end: CGPoint,
        in frame: CGRect
    ) {
        clip(path) {
            ctx.drawLinearGradient(
                Pen.gradient(stops), start: point(start, in: frame), end: point(end, in: frame),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }

    func linear(
        _ rect: CGRect, radius: CGFloat = 0, _ stops: [(CGColor, CGFloat)], from: CGPoint,
        to: CGPoint
    ) {
        linear(Pen.rect(rect, radius: radius), stops, from: from, to: to, in: rect)
    }

    /// `RadialGradient(stops:center:startRadius:endRadius:)`.
    func radial(
        _ path: CGPath, _ stops: [(CGColor, CGFloat)], center: CGPoint, in frame: CGRect,
        startRadius: CGFloat = 0, endRadius: CGFloat
    ) {
        let c = point(center, in: frame)
        clip(path) {
            ctx.drawRadialGradient(
                Pen.gradient(stops), startCenter: c, startRadius: startRadius, endCenter: c,
                endRadius: endRadius, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }

    /// `EllipticalGradient`: a radial gradient stretched to `frame`'s proportions, its radii
    /// fractions of `frame`'s size.
    func elliptical(
        _ path: CGPath, _ stops: [(CGColor, CGFloat)], center: CGPoint, frame: CGRect,
        startFraction: CGFloat = 0, endFraction: CGFloat = 0.5
    ) {
        guard frame.width > 0, frame.height > 0 else { return }
        clip(path) {
            let c = point(center, in: frame)
            ctx.translateBy(x: c.x, y: c.y)
            ctx.scaleBy(x: frame.width, y: frame.height)
            ctx.drawRadialGradient(
                Pen.gradient(stops), startCenter: .zero, startRadius: startFraction,
                endCenter: .zero, endRadius: endFraction,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }

    /// `AngularGradient(colors:center:angle:)`, starting at `degrees` and turning clockwise.
    func angular(
        _ path: CGPath, _ colors: [CGColor], center: CGPoint, in frame: CGRect, degrees: CGFloat
    ) {
        clip(path) {
            CGContextDrawConicGradient(
                ctx, Pen.gradient(Pen.even(colors)), point(center, in: frame), degrees * .pi / 180)
        }
    }

    func point(_ unit: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + unit.x * frame.width, y: frame.minY + unit.y * frame.height)
    }

    /// A one-point bright edge top and left, dark bottom and right: something raised off
    /// the paint, lit from above left.
    func bevel(_ rect: CGRect, radius: CGFloat, light: CGFloat, dark: CGFloat) {
        let border = Pen.rect(rect.insetBy(dx: 0.5, dy: 0.5), radius: max(0, radius - 0.5))
        let stroked = border.copy(
            strokingWithWidth: 1, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        linear(
            stroked, [(white(light), 0), (white(0), 1)], from: .topLeading, to: .center, in: rect)
        linear(
            stroked, [(black(0), 0), (black(dark), 1)], from: .center, to: .bottomTrailing, in: rect
        )
    }

    // MARK: - Text

    /// One run of text, set the way SwiftUI's `Text` sets it.
    struct Style {
        var font: String
        var size: CGFloat
        var tracking: CGFloat = 0
        var color: CGColor
        /// Added between lines, as `lineSpacing`; negative tightens.
        var lineSpacing: CGFloat = 0

        var ctFont: CTFont { Fonts.font(font, size) }
    }

    enum Align { case leading, center, trailing }

    func lines(_ text: String, _ style: Style, wrap width: CGFloat? = nil) -> [CTLine] {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): style.ctFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): style.color,
            NSAttributedString.Key(kCTKernAttributeName as String): style.tracking,
        ]
        var out: [CTLine] = []
        for paragraph in text.components(separatedBy: "\n") {
            let string = NSAttributedString(string: paragraph, attributes: attributes)
            guard let width, string.length > 0 else {
                out.append(CTLineCreateWithAttributedString(string))
                continue
            }
            let typesetter = CTTypesetterCreateWithAttributedString(string)
            var start = 0
            while start < string.length {
                let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width) + 0.5)
                let range = CFRange(location: start, length: max(1, count))
                // Trailing spaces hang, as they do in SwiftUI: `width(_:)` leaves them out.
                out.append(CTTypesetterCreateLine(typesetter, range))
                start += max(1, count)
            }
        }
        return out
    }

    static func lineHeight(_ font: CTFont) -> CGFloat {
        CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    /// A line's width as SwiftUI measures it when it centres text: without trailing
    /// spaces, and without the tracking after the last letter.
    static func width(_ line: CTLine, tracking: CGFloat = 0) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            - CGFloat(CTLineGetTrailingWhitespaceWidth(line)) - tracking
    }

    /// Where the first baseline sits below the top of a line box, per face and size.
    /// Core Text's ascent, nudged where SwiftUI's rounding of the line box puts it
    /// elsewhere; measured against the reference renders.
    nonisolated(unsafe) static var baselineNudge: [String: CGFloat] = [
        DeskFonts.dosis: -0.35, DeskFonts.barlowSemiBold: -0.25, DeskFonts.barlowBold: -0.1,
    ]

    static func baseline(_ font: CTFont, name: String, size: CGFloat) -> CGFloat {
        CTFontGetAscent(font) + (baselineNudge["\(name)@\(size)"] ?? baselineNudge[name] ?? 0)
    }

    /// Sets `text` in `rect`, each line aligned and the block centred vertically.
    func text(
        _ text: String, _ style: Style, in rect: CGRect, align: Align = .center,
        wrap: Bool = false, color: CGColor? = nil
    ) {
        var style = style
        if let color { style.color = color }
        let set = lines(text, style, wrap: wrap ? rect.width : nil)
        let font = style.ctFont
        let height = Pen.lineHeight(font)
        let block = CGFloat(set.count) * height + CGFloat(max(0, set.count - 1)) * style.lineSpacing
        var top = rect.midY - block / 2
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for line in set {
            let width = Pen.width(line, tracking: style.tracking)
            let x: CGFloat
            switch align {
            case .leading: x = rect.minX
            case .center: x = rect.midX - width / 2
            case .trailing: x = rect.maxX - width
            }
            ctx.textPosition = CGPoint(
                x: x, y: top + Pen.baseline(font, name: style.font, size: style.size))
            CTLineDraw(line, ctx)
            top += height + style.lineSpacing
        }
        ctx.restoreGState()
    }

    /// Text centred on a point, as a Canvas draws it with `anchor: .center`.
    func text(_ text: String, _ style: Style, centeredAt point: CGPoint, anchor: Align = .center) {
        let line = lines(text, style).first!
        let font = style.ctFont
        let width = Pen.width(line, tracking: style.tracking)
        let height = Pen.lineHeight(font)
        let x: CGFloat
        switch anchor {
        case .leading: x = point.x
        case .center: x = point.x - width / 2
        case .trailing: x = point.x - width
        }
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(
            x: x, y: point.y - height / 2 + Pen.baseline(font, name: style.font, size: style.size))
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

extension CGPoint {
    static let topLeading = CGPoint(x: 0, y: 0)
    static let top = CGPoint(x: 0.5, y: 0)
    static let topTrailing = CGPoint(x: 1, y: 0)
    static let leading = CGPoint(x: 0, y: 0.5)
    static let center = CGPoint(x: 0.5, y: 0.5)
    static let trailing = CGPoint(x: 1, y: 0.5)
    static let bottomLeading = CGPoint(x: 0, y: 1)
    static let bottom = CGPoint(x: 0.5, y: 1)
    static let bottomTrailing = CGPoint(x: 1, y: 1)
}

/// The desk's faces as Core Text fonts, cached: creating a `CTFont` is not free, and the
/// painters ask for the same dozen hundreds of times.
enum Fonts {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: CTFont] = [:]

    static func font(_ name: String, _ size: CGFloat) -> CTFont {
        let key = "\(name)@\(size)"
        lock.lock()
        defer { lock.unlock() }
        if let font = cache[key] { return font }
        DeskFonts.register()
        let font = CTFontCreateWithName(name as CFString, size, nil)
        cache[key] = font
        return font
    }

    static func label(_ size: CGFloat, bold: Bool = false) -> String {
        bold ? DeskFonts.barlowBold : DeskFonts.barlowSemiBold
    }
}

/// Tuning hooks for the development tools that calibrate the painters against the
/// reference. The app never calls these.
public enum ArtCalibration {
    public static func setBaselineNudge(_ key: String, _ value: CGFloat) {
        Pen.baselineNudge[key] = value
    }
    public static func setShadowFactor(_ value: CGFloat) { Pen.shadowFactor = value }
    public static func setBlurFactor(_ value: CGFloat) { Pen.blurFactor = value }
}

/// A colour in Oklab, Björn Ottosson's perceptual space, for mixing gradients the way
/// SwiftUI does.
struct Oklab {
    var l: CGFloat
    var a: CGFloat
    var b: CGFloat

    init(srgb c: [CGFloat]) {
        func linear(_ v: CGFloat) -> CGFloat {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = linear(c[0]), g = linear(c[1]), bl = linear(c[2])
        let lm = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let mm = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let sm = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        l = 0.2104542553 * lm + 0.7936177850 * mm - 0.0040720468 * sm
        a = 1.9779984951 * lm - 2.4285922050 * mm + 0.4505937099 * sm
        b = 0.0259040371 * lm + 0.7827717662 * mm - 0.8086757660 * sm
    }

    private init(l: CGFloat, a: CGFloat, b: CGFloat) {
        self.l = l
        self.a = a
        self.b = b
    }

    func mixed(with other: Oklab, _ t: CGFloat) -> Oklab {
        Oklab(l: l + (other.l - l) * t, a: a + (other.a - a) * t, b: b + (other.b - b) * t)
    }

    var srgb: [CGFloat] {
        let lm = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let mm = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let sm = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
        let r = 4.0767416621 * lm - 3.3077115913 * mm + 0.2309699292 * sm
        let g = -1.2684380046 * lm + 2.6097574011 * mm - 0.3413193965 * sm
        let bl = -0.0041960863 * lm - 0.7034186147 * mm + 1.7076147010 * sm
        func encode(_ v: CGFloat) -> CGFloat {
            let v = min(1, max(0, v))
            return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
        return [encode(r), encode(g), encode(bl)]
    }
}
