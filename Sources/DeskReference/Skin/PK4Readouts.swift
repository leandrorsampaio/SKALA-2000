import ConsoleKit
import SwiftUI

// MARK: - Nixie

/// A row of gas-discharge digits behind one shared dark-orange filter, with its label plate
/// and HG tag on the left and a painted unit on the right.
///
/// A nixie does not roll or fade: each digit is its own cathode. The old one goes dark,
/// the new one lights, and the old stays as a 35% ghost for 60 ms.
struct NixieReadout: View {
    var label: String?
    var template: String
    var value: String
    var unit: String?
    var xl = false
    var labelWidth: CGFloat?
    var code: String?
    /// Readouts stacked in a column share this, so their tubes line up.
    var unitWidth: CGFloat?
    /// A template whose width this readout's glass takes, so a column of readouts with
    /// and without a separator ends level.
    var span: String?
    var id: String = ""

    @Environment(\.pk4) private var palette

    var body: some View {
        HStack(spacing: 10) {
            if let label {
                VStack(spacing: 6) {
                    Plate(text: label, width: labelWidth)
                    if let code { Tag(text: code) }
                }
            }
            NixieTubes(template: template, value: value, xl: xl, span: span, id: id)
            if unit != nil || unitWidth != nil {
                Text((unit ?? "").plate).font(PK4Type.label(13)).tracking(0.78)
                    .mark("unit", "", ["text": unit ?? ""])
                    .frame(width: unitWidth, alignment: .leading)
            }
        }
    }
}

struct NixieTubes: View, Equatable {
    var template: String
    var value: String
    var xl: Bool
    var span: String?
    var id: String = ""

    static func == (lhs: NixieTubes, rhs: NixieTubes) -> Bool {
        lhs.template == rhs.template && lhs.value == rhs.value && lhs.xl == rhs.xl
            && lhs.span == rhs.span
    }

    /// The width of the tubes a template stands for, separators narrow.
    static func width(of template: String, xl: Bool) -> CGFloat {
        let tube = (xl ? PK4Size.tubeXL : PK4Size.tube).width
        let cells = template.map { $0.isNumber ? tube : 10 }
        return cells.reduce(0, +) + 2 * CGFloat(max(0, cells.count - 1))
    }

    @Environment(\.pk4) private var palette

    var body: some View {
        let cells = Array(template)
        let shown = Array(value.padding(toLength: cells.count, withPad: " ", startingAt: 0))
        HStack(spacing: 2) {
            ForEach(cells.indices, id: \.self) { index in
                let separator = !cells[index].isNumber
                NixieCell(character: shown[index], separator: separator, xl: xl)
                    .mark(
                        "tube", id,
                        ["index": "\(index)", "separator": "\(separator)", "xl": "\(xl)"])
            }
        }
        .frame(minWidth: span.map { Self.width(of: $0, xl: xl) }, alignment: .trailing)
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(palette.nixieGlass)
        .overlay {
            ZStack {
                // The tubes sit well back: a deep shadow across the top of the glass.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.75), location: 0),
                        .init(color: .black.opacity(0), location: 0.18),
                    ], startPoint: .top, endPoint: .bottom)
                RoundedRectangle(cornerRadius: 1).strokeBorder(.black.opacity(0.5), lineWidth: 1)
                    .blur(radius: 1)
                // One faint fixed sheen over the upper 40%.
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.16), location: 0),
                        .init(color: .white.opacity(0.04), location: 0.40),
                        .init(color: .white.opacity(0), location: 0.41),
                    ], startPoint: UnitPoint(x: 0.43, y: 0), endPoint: UnitPoint(x: 0.57, y: 1))
            }
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 1))
        .padding(4)
        .mark("nixie", id, ["template": template, "xl": "\(xl)", "span": span ?? ""])
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x4D4D48), Color(hex: 0x3B3B37), Color(hex: 0x1C1C1A),
                            Color(hex: 0x0C0C0B),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(color: .white.opacity(0.4), radius: 0, y: 1)
                .shadow(color: .black.opacity(0.5), radius: 1.5, y: 2)
        }
    }
}

private struct NixieCell: View {
    var character: Character
    var separator: Bool
    var xl: Bool

    @State private var ghost: Character?
    @Environment(\.pk4) private var palette

    var body: some View {
        let size = xl ? PK4Size.tubeXL : PK4Size.tube
        let digit: CGFloat = xl ? 60 : 34
        ZStack {
            if let ghost, ghost != " " { glyph(ghost, digit).opacity(0.35) }
            if character != " " { glyph(character, digit) }
        }
        .frame(width: separator ? 10 : size.width, height: size.height)
        .onChange(of: character) { old, _ in
            ghost = old
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { ghost = nil }
        }
    }

    private func glyph(_ character: Character, _ size: CGFloat) -> some View {
        Text(String(character))
            .font(PK4Type.nixie(size))
            .foregroundStyle(palette.nixieGlow)
            .shadow(color: palette.nixieHalo, radius: 4.5)
            .shadow(color: palette.nixieHalo.opacity(0.5), radius: 9)
            .fixedSize()
    }
}

// MARK: - Drum counter

/// An electromechanical counter: white digit wheels behind a black window, for totals
/// that survive a restart. The wheels roll forward only — a wheel passing 9 goes on to 0
/// in the same direction — units first, each higher wheel 45 ms later so a carry ripples
/// leftward. On launch they show their stored value with no animation.
struct DrumCounter: View {
    var label: String
    var value: Int
    var digits = 6
    var unit: String?
    var code: String?
    var id: String = ""

    @Environment(\.pk4) private var palette

    var body: some View {
        VStack(spacing: 6) {
            DrumWheels(value: value, digits: digits, id: id)
            Plate(text: label)
            if let unit {
                Text(unit.plate).font(PK4Type.label(13)).tracking(0.78)
                    .mark("unit", "", ["text": unit])
            }
            if let code { Tag(text: code) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(unit.map { "\(value) \(Self.spoken($0))" } ?? "\(value)")
    }

    /// The units as they are said, not as they are stamped.
    static func spoken(_ unit: String) -> String {
        switch unit {
        case "$": "dollars"
        case "h": "hours"
        case "×1000 tok": "thousand tokens"
        default: unit
        }
    }
}

private struct DrumWheels: View {
    var value: Int
    var digits: Int
    var id: String = ""

    @Environment(\.pk4) private var palette

    var body: some View {
        let text = String(String(repeating: "0", count: digits) + String(max(0, value))).suffix(
            digits)
        let figures = text.compactMap { $0.wholeNumberValue }
        HStack(spacing: 0) {
            ForEach(0..<digits, id: \.self) { index in
                Wheel(digit: figures[index], delay: Double(digits - 1 - index) * 0.045)
                    .overlay(alignment: .leading) { Rectangle().fill(.black).frame(width: 1) }
                    .mark("wheel", id, ["index": "\(index)"])
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(hex: 0x111111))
        .overlay {
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.75), location: 0),
                        .init(color: .black.opacity(0), location: 0.2),
                    ], startPoint: .top, endPoint: .bottom)
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.16), location: 0),
                        .init(color: .white.opacity(0.04), location: 0.40),
                        .init(color: .white.opacity(0), location: 0.41),
                    ], startPoint: UnitPoint(x: 0.43, y: 0), endPoint: UnitPoint(x: 0.57, y: 1))
            }
            .allowsHitTesting(false)
        }
        .padding(4)
        .mark("drum", id, ["digits": "\(digits)"])
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x4D4D48), Color(hex: 0x1C1C1A), Color(hex: 0x0C0C0B)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(color: .white.opacity(0.4), radius: 0, y: 1)
                .shadow(color: .black.opacity(0.5), radius: 1.5, y: 2)
        }
    }
}

private struct Wheel: View {
    var digit: Int
    var delay: Double

    /// Grows forever: a wheel only ever rolls forward.
    @State private var position: Double = -1
    @Environment(\.pk4) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WheelFace(position: max(0, position), ink: palette.drumInk)
            .frame(width: PK4Size.wheel.width, height: PK4Size.wheel.height)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0x6F6D64), location: 0),
                        .init(color: palette.drumWheel, location: 0.3),
                        .init(color: .white, location: 0.5),
                        .init(color: palette.drumWheel, location: 0.7),
                        .init(color: Color(hex: 0x5F5D55), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
            )
            .clipped()
            // The digits above and below the window are hidden, not gone: only the window
            // is the wheel.
            .contentShape(Rectangle())
            .onAppear { position = Double(digit) }
            .onChange(of: digit) { _, new in
                let current = Int(position.rounded()) % 10
                let step = (new - current + 10) % 10
                guard step > 0 else { return }
                let target = position.rounded() + Double(step)
                if reduceMotion {
                    position = target
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.7).delay(delay)) {
                        position = target
                    }
                }
            }
    }
}

/// The digits on a wheel at a fractional position: the next digit comes up from below.
private struct WheelFace: View, Animatable {
    var position: Double
    var ink: Color

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        let base = position.rounded(.down)
        let fraction = position - base
        ZStack {
            ForEach(-1...1, id: \.self) { offset in
                let digit = ((Int(base) + offset) % 10 + 10) % 10
                Text(String(digit))
                    .font(PK4Type.label(24))
                    .foregroundStyle(ink)
                    .offset(y: (Double(offset) - fraction) * PK4Size.wheel.height)
            }
        }
    }
}

// MARK: - Meters

/// A 220 × 140 moving-coil panel meter on a yellowed dial: a 120° arc, 0 / 50 / 100, a
/// black needle and an optional red sector. The needle has mass — it travels in about
/// 700 ms, overshoots once and settles — and with power off, or nothing to measure, it
/// lies on zero.
struct MovingCoilMeter: View {
    var label: String
    var value: Double
    var red: ClosedRange<Double>?
    var unit = "%"
    var powered: Bool
    var code: String?
    var id: String = ""

    @Environment(\.pk4) private var palette

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                MeterDial(red: red, unit: unit)
                MeterNeedle(value: value, powered: powered)
                Circle().fill(Color(hex: 0x111111)).frame(width: 14, height: 14)
                    .position(x: 110, y: 118)
                MeterGlass(width: 220, height: 140, radius: 6)
            }
            .frame(width: 220, height: 140)
            .mark(
                "dial", id,
                ["red": red.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "", "unit": unit])
            Plate(text: label, style: .bare)
            if let code { Tag(text: code) }
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 8, trailing: 12))
        .mark("meter", id)
        .background { MeterHousing() }
    }
}

struct MeterHousing: View {
    @Environment(\.pk4) private var palette

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0x3A3A36), location: 0),
                        .init(color: palette.bakelite, location: 0.4),
                        .init(color: Color(hex: 0x0B0B0A), location: 1),
                    ], startPoint: UnitPoint(x: 0.35, y: 0), endPoint: UnitPoint(x: 0.65, y: 1))
            )
            .overlay { Bevel(radius: 6, light: 0.3, dark: 0.8) }
            .shadow(color: .black.opacity(0.5), radius: 2.5, y: 3)
    }
}

private struct MeterDial: View, Equatable {
    var red: ClosedRange<Double>?
    var unit: String

    static func == (lhs: MeterDial, rhs: MeterDial) -> Bool {
        lhs.red == rhs.red && lhs.unit == rhs.unit
    }

    @Environment(\.pk4) private var palette

    var body: some View {
        let face = palette.meterFace
        let ink = palette.tagInk
        Canvas { context, _ in
            let centre = CGPoint(x: 110, y: 118)
            let radius: CGFloat = 88
            func point(_ fraction: Double, _ r: CGFloat) -> CGPoint {
                let angle = CGFloat((210 + 120 * fraction) * .pi / 180)
                return CGPoint(x: centre.x + r * cos(angle), y: centre.y + r * sin(angle))
            }
            func arc(_ from: Double, _ to: Double, _ r: CGFloat) -> Path {
                var path = Path()
                path.addArc(
                    center: centre, radius: r, startAngle: .degrees(210 + 120 * from),
                    endAngle: .degrees(210 + 120 * to), clockwise: false)
                return path
            }

            let plate = Path(
                roundedRect: CGRect(x: 1, y: 1, width: 218, height: 138), cornerRadius: 6)
            context.fill(plate, with: .color(face))
            context.stroke(plate, with: .color(palette.bezel), lineWidth: 2)
            context.stroke(arc(0, 1, radius), with: .color(ink), lineWidth: 2)
            if let red {
                context.stroke(
                    arc(red.lowerBound, red.upperBound, radius - 7),
                    with: .color(Color(hex: 0xC8321F)),
                    lineWidth: 9)
            }
            for tick in 0...10 {
                let major = tick % 5 == 0
                var path = Path()
                path.move(to: point(Double(tick) / 10, radius))
                path.addLine(to: point(Double(tick) / 10, radius - (major ? 14 : 8)))
                context.stroke(path, with: .color(ink), lineWidth: major ? 2 : 1)
            }
            for (index, text) in ["0", "50", "100"].enumerated() {
                let at = point(Double(index) / 2, radius - 28)
                context.draw(
                    Text(text).font(PK4Type.label(15)).foregroundStyle(ink), at: at, anchor: .center
                )
            }
            context.draw(
                Text(unit.plate).font(PK4Type.label(15)).foregroundStyle(ink),
                at: CGPoint(x: 110, y: 94), anchor: .center)
        }
        .frame(width: 220, height: 140)
    }
}

private struct MeterNeedle: View {
    var value: Double
    var powered: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Never outside the scale: resting a few degrees below zero read as a zero that was
        // wrong, not as a stop pin.
        let angle = -60 + 120 * min(1, max(0, value))
        Rectangle()
            .fill(Color(hex: 0x111111))
            .frame(width: 2.5, height: 84)
            .offset(y: -42)
            .rotationEffect(.degrees(angle), anchor: .center)
            .position(x: 110, y: 118)
            .animation(
                reduceMotion
                    ? nil
                    // With power gone the needle simply falls to its stop.
                    : powered
                        ? .spring(response: 0.55, dampingFraction: 0.55) : .easeIn(duration: 0.9),
                value: angle)
    }
}

/// The glass over a dial: the housing's shadow across the top, one soft diagonal band of
/// room light, a dark rim.
struct MeterGlass: View {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .black.opacity(0.12), location: 0.12),
                    .init(color: .black.opacity(0), location: 0.3),
                ], startPoint: .top, endPoint: .bottom)
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(0.2), location: 0.18),
                    .init(color: .white.opacity(0.08), location: 0.34),
                    .init(color: .white.opacity(0), location: 0.5),
                ], startPoint: .topLeading, endPoint: UnitPoint(x: 1, y: 0.35)
            )
            .blur(radius: max(3, width * 0.03))
            RoundedRectangle(cornerRadius: radius).strokeBorder(.black.opacity(0.6), lineWidth: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}

/// A narrow 70 × 220 profile meter, for battery charge: a straight scale, a red pointer
/// riding beside it and a red sector from 0 to 20.
/// The vertical edgewise meter turned on its side, for the plan's usage windows: a straight
/// scale from 0 at the left to 100 at the right, red from 80, and a red pointer that rises
/// from below and slides along it.
struct HorizontalEdgewiseMeter: View {
    var label: String
    var value: Double
    var code: String?
    var id: String = ""

    /// The face, and where on it the scale starts and ends.
    static let size = CGSize(width: 240, height: 44)
    static let left: CGFloat = 16
    static let right: CGFloat = 224

    @Environment(\.pk4) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = Self.size
        let left = Self.left
        let span = Self.right - Self.left
        let fraction = min(1, max(0, value))
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    let ink = palette.tagInk
                    let plate = Path(
                        roundedRect: CGRect(
                            x: 1, y: 1, width: size.width - 2, height: size.height - 2),
                        cornerRadius: 3)
                    context.fill(plate, with: .color(palette.meterFace))
                    context.stroke(plate, with: .color(palette.bezel), lineWidth: 2)
                    context.fill(
                        Path(CGRect(x: left + span * 0.8, y: 6, width: span * 0.2, height: 5)),
                        with: .color(Color(hex: 0xC8321F)))
                    for tick in 0...10 {
                        let x = left + span * CGFloat(tick) / 10
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 12))
                        path.addLine(to: CGPoint(x: x, y: 12 + (tick % 5 == 0 ? 15 : 8)))
                        context.stroke(path, with: .color(ink), lineWidth: tick % 5 == 0 ? 2 : 1)
                        if tick % 5 == 0 {
                            context.draw(
                                Text(String(tick * 10)).font(PK4Type.label(13)).foregroundStyle(
                                    ink),
                                at: CGPoint(x: x, y: 35), anchor: .center)
                        }
                    }
                }
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 12))
                    path.addLine(to: CGPoint(x: -5, y: 30))
                    path.addLine(to: CGPoint(x: 5, y: 30))
                    path.closeSubpath()
                }
                .fill(Color(hex: 0xC8321F))
                .overlay {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 12))
                        path.addLine(to: CGPoint(x: -5, y: 30))
                        path.addLine(to: CGPoint(x: 5, y: 30))
                        path.closeSubpath()
                    }
                    .stroke(Color(hex: 0x111111), lineWidth: 1)
                }
                .offset(x: left + span * fraction)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.65),
                    value: fraction)
                MeterGlass(width: size.width, height: size.height, radius: 3)
            }
            .frame(width: size.width, height: size.height)
            .mark("hEdgeDial", id)
            Plate(text: label, style: .bare)
            if let code { Tag(text: code) }
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .mark("hEdgewise", id)
        .background { MeterHousing() }
    }
}

struct EdgewiseMeter: View {
    var label: String
    var value: Double
    var code: String?
    var id: String = ""

    @Environment(\.pk4) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let top: CGFloat = 16
        let bottom: CGFloat = 204
        let fraction = min(1, max(0, value))
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    let ink = palette.tagInk
                    let plate = Path(
                        roundedRect: CGRect(x: 1, y: 1, width: 68, height: 218), cornerRadius: 3)
                    context.fill(plate, with: .color(palette.meterFace))
                    context.stroke(plate, with: .color(palette.bezel), lineWidth: 2)
                    let span = bottom - top
                    context.fill(
                        Path(CGRect(x: 6, y: bottom - span * 0.2, width: 6, height: span * 0.2)),
                        with: .color(Color(hex: 0xC8321F)))
                    for tick in 0...10 {
                        let y = bottom - span * CGFloat(tick) / 10
                        var path = Path()
                        path.move(to: CGPoint(x: 14, y: y))
                        path.addLine(to: CGPoint(x: 14 + (tick % 5 == 0 ? 18 : 10), y: y))
                        context.stroke(path, with: .color(ink), lineWidth: tick % 5 == 0 ? 2 : 1)
                        if tick % 5 == 0 {
                            context.draw(
                                Text(String(tick * 10)).font(PK4Type.label(15)).foregroundStyle(
                                    ink),
                                at: CGPoint(x: 62, y: y), anchor: .trailing)
                        }
                    }
                }
                Path { path in
                    path.move(to: CGPoint(x: 12, y: 0))
                    path.addLine(to: CGPoint(x: 40, y: -5))
                    path.addLine(to: CGPoint(x: 40, y: 5))
                    path.closeSubpath()
                }
                .fill(Color(hex: 0xC8321F))
                .overlay {
                    Path { path in
                        path.move(to: CGPoint(x: 12, y: 0))
                        path.addLine(to: CGPoint(x: 40, y: -5))
                        path.addLine(to: CGPoint(x: 40, y: 5))
                        path.closeSubpath()
                    }
                    .stroke(Color(hex: 0x111111), lineWidth: 1)
                }
                .offset(y: bottom - (bottom - top) * fraction)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.65),
                    value: fraction)
                MeterGlass(width: 70, height: 220, radius: 3)
            }
            .frame(width: 70, height: 220)
            .mark("edgeDial", id)
            Plate(text: label, style: .bare)
            if let code { Tag(text: code) }
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 8, trailing: 12))
        .mark("edgewise", id)
        .background { MeterHousing() }
    }
}
