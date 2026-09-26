import ConsoleKit
import CoreGraphics
import SwiftUI

// MARK: - Paint

/// Smooth sprayed satin enamel on flat steel. It reads as real because of three quiet
/// things: room light falling off across the plate, a fine grain, and unevenness of the
/// coat you should not be able to point at. No relief, no hammer pattern.
struct EnamelPaint: View {
    var finish: Finish
    /// Each sub-panel gets its own light falloff, so plates read as separate sheets.
    var falloff = true

    @Environment(\.pk4) private var palette

    var body: some View {
        let paint = palette.paint(finish)
        ZStack {
            paint.ground
            Image(decorative: EnamelTexture.image(for: finish), scale: 1)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
            if falloff {
                GeometryReader { box in
                    let size = box.size
                    ZStack {
                        // A soft highlight from the top-left corner, gone by 60% across.
                        EllipticalGradient(
                            colors: [.white.opacity(0.20), .white.opacity(0)],
                            center: UnitPoint(x: 0.18, y: 0), startRadiusFraction: 0,
                            endRadiusFraction: 0.6
                        )
                        .frame(width: size.width * 1.2, height: size.height * 0.9 * 2)
                        .position(x: size.width * 0.18, y: 0)
                        // And a darkening toward the bottom-right.
                        EllipticalGradient(
                            colors: [.black.opacity(0.16), .black.opacity(0)],
                            center: .center, startRadiusFraction: 0, endRadiusFraction: 0.65
                        )
                        .frame(width: size.width * 2.4, height: size.height * 2)
                        .position(x: size.width, y: size.height)
                    }
                }
                .clipped()
            }
        }
        // Paint takes no clicks. The two gradients reach well past the sheet, and clipping
        // hides them without stopping them catching clicks: every panel drawn after
        // another lay invisibly over its neighbour's buttons.
        .allowsHitTesting(false)
    }
}

/// The grain and the coat, generated once per finish as one 512-point tile.
///
/// Both noises are centred on mid-grey so that, composited in overlay mode, they leave
/// the paint colour exact.
enum EnamelTexture {

    @MainActor private static var cache: [Finish: CGImage] = [:]

    @MainActor
    static func image(for finish: Finish) -> CGImage {
        if let cached = cache[finish] { return cached }
        let (grain, mottle, seed): (Double, Double, UInt64) =
            switch finish {
            case .greyGreen: (0.08, 0.10, 7)
            case .ivory: (0.06, 0.09, 11)
            case .graphite: (0.15, 0.12, 23)
            }
        let image = make(grain: grain, mottle: mottle, seed: seed)
        cache[finish] = image
        return image
    }

    static func make(grain: Double, mottle: Double, seed: UInt64) -> CGImage {
        let size = 512
        var random = SplitMix64(seed: seed)

        // The coat: a coarse grid of values, blended smoothly, about 170 points a cell.
        let cells = 4
        var coarse = [Double](repeating: 0, count: (cells + 1) * (cells + 1))
        for index in coarse.indices { coarse[index] = random.unit() * 2 - 1 }
        // Wrap the last row and column onto the first so the tile has no seam.
        for i in 0...cells {
            coarse[i * (cells + 1) + cells] = coarse[i * (cells + 1)]
            coarse[cells * (cells + 1) + i] = coarse[i]
        }
        func coat(_ x: Double, _ y: Double) -> Double {
            let fx = x / Double(size) * Double(cells)
            let fy = y / Double(size) * Double(cells)
            let x0 = min(cells - 1, Int(fx))
            let y0 = min(cells - 1, Int(fy))
            let tx = smooth(fx - Double(x0))
            let ty = smooth(fy - Double(y0))
            let a = coarse[y0 * (cells + 1) + x0]
            let b = coarse[y0 * (cells + 1) + x0 + 1]
            let c = coarse[(y0 + 1) * (cells + 1) + x0]
            let d = coarse[(y0 + 1) * (cells + 1) + x0 + 1]
            return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
        }

        var pixels = [UInt8](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let fine = (random.unit() * 2 - 1) * grain
                let broad = coat(Double(x), Double(y)) * mottle * 0.5
                let value = min(1, max(0, 0.5 + fine + broad))
                pixels[y * size + x] = UInt8(value * 255)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private static func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
}

/// Small, fast and the same numbers on every machine, so a screw's slot and the paint's
/// grain never change between launches.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    static func seed(_ text: String) -> UInt64 {
        text.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01B3 }
    }
}

// MARK: - Sub-panel

/// One painted steel plate screwed into the desk: a finish, a bright top-left and dark
/// bottom-right edge, four screws and a centred bakelite title plate.
struct PK4Panel<Content: View>: View {
    var title: String
    var spacing: CGFloat = 32
    var padding = EdgeInsets(top: 18, leading: 22, bottom: 18, trailing: 22)
    var tightBottom = false
    @ViewBuilder var content: Content

    private var titleRow: some View {
        HStack(spacing: 12) {
            Screw(seed: title + ".tl")
            Spacer(minLength: 0)
            Plate(text: title, style: .title)
            Spacer(minLength: 0)
            Screw(seed: title + ".tr")
        }
    }

    private var screws: some View {
        HStack {
            Screw(seed: title + ".bl")
            Spacer()
            Screw(seed: title + ".br")
        }
    }

    @Environment(\.pk4) private var palette
    @Environment(\.pk4Finish) private var finish

    var body: some View {
        let paint = palette.paint(finish)
        // SKALA-2000: in the reference the zero-length spacer before the bottom screws still
        // cost two gaps, and panel B overflowed the desk by 40 units, its lower edge cut off
        // at 1800. B's screws now sit on its bottom padding, so it ends at 1778 like D and E;
        // the other panels keep their natural heights, and with them the whole layout.
        Group {
            if tightBottom {
                VStack(spacing: 0) {
                    VStack(spacing: spacing) {
                        titleRow
                        content
                    }
                    Spacer(minLength: 0)
                    screws
                }
            } else {
                VStack(spacing: spacing) {
                    titleRow
                    content
                    Spacer(minLength: 0)
                    screws
                }
            }
        }
        .padding(padding)
        .mark("panel", title)
        .background {
            EnamelPaint(finish: finish)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(paint.edge, lineWidth: 1)
                }
                .overlay { Bevel(radius: 4, light: 0.4, dark: 0.35) }
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
        }
        .foregroundStyle(paint.ink)
    }
}

/// A one-point bright edge top and left, dark bottom and right: something raised off
/// the paint, lit from above left.
struct Bevel: View {
    var radius: CGFloat
    var light: Double
    var dark: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(light), .white.opacity(0)],
                        startPoint: .topLeading, endPoint: .center), lineWidth: 1)
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(
                    LinearGradient(
                        colors: [.black.opacity(0), .black.opacity(dark)],
                        startPoint: .center, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// A domed slotted screw in a dark countersink, its slot at an angle of its own that
/// never changes.
struct Screw: View {
    var seed: String
    var size: CGFloat = 18

    var body: some View {
        var random = SplitMix64(seed: SplitMix64.seed(seed))
        let angle = random.unit() * 170 - 85
        return Canvas { context, box in
            let k = box.width / 20
            func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
                Path(
                    ellipseIn: CGRect(
                        x: (x - r) * k, y: (y - r) * k, width: 2 * r * k, height: 2 * r * k))
            }
            context.fill(circle(10, 10.6, 9.4), with: .color(.black.opacity(0.45)))
            context.fill(circle(10, 10, 8.6), with: .color(Color(hex: 0x1D1F1C)))
            context.fill(
                circle(10, 10, 7.6),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .white, location: 0),
                        .init(color: Color(hex: 0xD6D8D1), location: 0.3),
                        .init(color: Color(hex: 0x8B8E86), location: 0.7),
                        .init(color: Color(hex: 0x4C4F48), location: 1),
                    ]), center: CGPoint(x: 7.2 * k, y: 6 * k), startRadius: 0, endRadius: 12 * k))
            var slot = context
            slot.translateBy(x: 10 * k, y: 10 * k)
            slot.rotate(by: .degrees(angle))
            slot.fill(
                Path(
                    roundedRect: CGRect(x: -7.4 * k, y: -1.1 * k, width: 14.8 * k, height: 2.4 * k),
                    cornerRadius: 0.6 * k),
                with: .color(Color(hex: 0x15160F)))
            slot.fill(
                Path(CGRect(x: -7.4 * k, y: 1.2 * k, width: 14.8 * k, height: 0.7 * k)),
                with: .color(.white.opacity(0.55)))
        }
        .frame(width: size, height: size)
        .mark("screw", seed)
        .accessibilityHidden(true)
    }
}

// MARK: - Plates and tags

/// A bakelite plate with its lettering cut in: a dark line above each letter, a faint
/// light line below. Always uppercase, centred, never more than two lines.
struct Plate: View {
    enum Style { case title, row, small, bare }
    var text: String
    var style: Style = .small
    var width: CGFloat?

    @Environment(\.pk4) private var palette

    var body: some View {
        let size: CGFloat =
            switch style {
            case .title: 20
            case .row: 14
            case .small, .bare: 13
            }
        Text(text.plate)
            .font(PK4Type.engraved(size))
            .tracking(size * 0.09)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            // A plate is cut to its lettering unless it is given a width to wrap within.
            .fixedSize(horizontal: width == nil, vertical: true)
            .foregroundStyle(palette.engraving)
            .shadow(color: .black.opacity(0.95), radius: 0, y: -1)
            .shadow(color: .white.opacity(0.14), radius: 0, y: 1)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(width: width)
            .mark("plate", "", ["text": text, "style": "\(style)"])
            .background {
                if style != .bare {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color(hex: 0x31312E), location: 0),
                                    .init(color: palette.bakelite, location: 0.55),
                                    .init(color: Color(hex: 0x0E0E0D), location: 1),
                                ], startPoint: .top, endPoint: .bottom)
                        )
                        .overlay { Bevel(radius: 2, light: 0.28, dark: 0.7) }
                        .shadow(color: .black.opacity(0.45), radius: 1.5, y: 2)
                }
            }
    }
}

/// A stamped aluminium designator tag: HL for a lamp, SB a button, PA a meter, HG a nixie
/// row, PC a counter, SA a switch, HA the buzzer, FU a fuse.
struct Tag: View {
    var text: String

    @Environment(\.pk4) private var palette

    var body: some View {
        Text(text)
            .font(PK4Type.engraved(11))
            .tracking(0.44)
            .fixedSize()
            .foregroundStyle(palette.tagInk)
            .shadow(color: .white.opacity(0.6), radius: 0, y: 1)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .mark("tag", "", ["text": text])
            .background {
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(hex: 0xECEEE8), location: 0),
                                .init(color: palette.tag, location: 0.6),
                                .init(color: Color(hex: 0xAEB1A8), location: 1),
                            ], startPoint: .top, endPoint: .bottom)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 1).strokeBorder(
                            .black.opacity(0.45), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
            }
            .accessibilityHidden(true)
    }
}

/// A riveted yellow instruction plate. The only place a sentence may appear, and it
/// always describes behaviour.
struct InstructionPlate: View {
    var text: String
    var width: CGFloat?

    @Environment(\.pk4) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Rivet()
            Text(text.plate)
                .font(PK4Type.engraved(13))
                .tracking(1.17)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(palette.tagInk)
                .frame(maxWidth: .infinity)
                .mark("instructionText", "", ["text": text])
            Rivet()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(width: width)
        .mark("instruction", "", ["text": text])
        .background {
            RoundedRectangle(cornerRadius: 2)
                .fill(palette.instruction)
                .overlay {
                    RoundedRectangle(cornerRadius: 2).fill(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .black.opacity(0.06)], startPoint: .top,
                            endPoint: .bottom))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 2).strokeBorder(palette.bezel, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: 1.5, y: 2)
        }
    }

    struct Rivet: View {
        var body: some View {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, Color(hex: 0xC9CBC3), Color(hex: 0x6F726B)],
                        center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 5)
                )
                .frame(width: 8, height: 8)
                .mark("rivet")
                .shadow(color: .black.opacity(0.6), radius: 0.5, y: 1)
        }
    }
}

/// A reserved cut-out, covered by a plate of the panel's own paint, raised one level. It
/// says RESERVED and what for.
struct BlankingPlate: View {
    var text: String
    var size: CGSize

    @Environment(\.pk4) private var palette
    @Environment(\.pk4Finish) private var finish

    var body: some View {
        let paint = palette.paint(finish)
        Text(text.plate)
            .font(PK4Type.engraved(13))
            .tracking(1.17)
            .multilineTextAlignment(.center)
            .foregroundStyle(paint.ink)
            .padding(6)
            .frame(width: size.width, height: size.height)
            .mark("blanking", "", ["text": text])
            .background {
                EnamelPaint(finish: finish, falloff: false)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3).strokeBorder(paint.edge, lineWidth: 1)
                    }
                    .overlay { Bevel(radius: 3, light: 0.4, dark: 0.35) }
                    .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
            }
    }
}

/// A control over its label plate, its designator tag under that, `space-1` apart.
struct Labelled<Control: View>: View {
    var label: String?
    var caption: String?
    var tag: String?
    var plateWidth: CGFloat?
    @ViewBuilder var control: Control

    @Environment(\.pk4) private var palette

    var body: some View {
        VStack(spacing: 6) {
            control
            if let label { Plate(text: label, width: plateWidth) }
            if let caption {
                Text(caption.plate)
                    .font(PK4Type.engraved(12))
                    .tracking(1.08)
                    .mark("caption", "", ["text": caption])
            }
            if let tag { Tag(text: tag) }
        }
    }
}
