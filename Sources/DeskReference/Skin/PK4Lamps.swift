import ConsoleKit
import SwiftUI

/// The shared flash clock: 2 Hz, rise 80 ms, hold to 250, decay 200, dark 50. Every
/// flashing window reads the same wall clock, so they are all in phase.
enum Flash {
    static func period(reduceMotion: Bool) -> TimeInterval { reduceMotion ? 1.0 : 0.5 }

    /// 0…1 at a moment.
    static func level(at date: Date, reduceMotion: Bool) -> Double {
        let period = period(reduceMotion: reduceMotion)
        let phase =
            date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        switch phase {
        case ..<0.16: return phase / 0.16
        case ..<0.5: return 1
        case ..<0.9: return 1 - (phase - 0.5) / 0.4
        default: return 0
        }
    }

    /// The paint takes the lamp's light for the first 60% of a flash.
    static func inkLit(at date: Date, reduceMotion: Bool) -> Bool {
        let period = period(reduceMotion: reduceMotion)
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            < 0.6
    }
}

/// How lit a lamp is, with the filament's timing: up in 90 ms, down in 220 ms, because a
/// filament cools slower than it heats. A flashing lamp follows the shared clock.
struct Filament<Content: View>: View {
    var state: LampState
    @ViewBuilder var content: (_ level: Double, _ inkLit: Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if state == .flash {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                content(
                    Flash.level(at: timeline.date, reduceMotion: reduceMotion),
                    Flash.inkLit(at: timeline.date, reduceMotion: reduceMotion))
            }
        } else {
            let lit = state == .on || state == .test
            content(lit ? 1 : 0, lit)
                .animation(lit ? .easeIn(duration: 0.09) : .easeOut(duration: 0.22), value: lit)
        }
    }
}

/// A rectangular back-lit glass window with painted lettering: the basic indicator of the
/// console, and never a control. One size everywhere, 96 × 46 with its bezel.
struct LampWindow: View, Equatable {
    var label: String
    var color: LampColor
    var state: LampState
    var code: String?
    var id: String = ""

    @Environment(\.pk4) private var palette
    @Environment(\.pk4LampCodes) private var showCodes
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let glass = palette.glass(color)
        let lines = label.split(separator: "\n").count
        let size: CGFloat = lines > 1 || label.count > 9 ? 12 : 13

        Filament(state: state) { level, inkLit in
            ZStack {
                // The spill a lit bulb throws on the paint: wide, faint, edge-less.
                RoundedRectangle(cornerRadius: 4)
                    .fill(glass.on.opacity(palette.spillOpacity))
                    .padding(-5)
                    .blur(radius: palette.spillRadius / 2)
                    .opacity(level)

                // Bezel: dark metal, bevelled, lit from the top left.
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

                ZStack {
                    // Unlit glass. With Increase Contrast it sits one step darker.
                    Rectangle().fill(glass.off)
                    if contrast == .increased { Rectangle().fill(.black.opacity(0.18)) }

                    // The lit layer: two bulbs, so one burnt filament never hides a signal.
                    ZStack {
                        glass.on
                        LinearGradient(
                            colors: [.white.opacity(0.10), .black.opacity(0.10)], startPoint: .top,
                            endPoint: .bottom)
                        HotSpots(hot: glass.hot)
                    }
                    .opacity(level)

                    Lettering(
                        label: label, size: size, code: showCodes ? code : nil,
                        ink: lettering(glass, lit: inkLit && level > 0.05),
                        halo: glass.lightInk && inkLit && level > 0.05)

                    GlassFace()
                }
                .clipShape(RoundedRectangle(cornerRadius: 1))
                .overlay {
                    // The bezel's inner edge catches the lamp.
                    RoundedRectangle(cornerRadius: 1)
                        .strokeBorder(glass.hot.opacity(0.42 * level), lineWidth: 1.5)
                }
                .padding(4)
            }
        }
        .frame(width: PK4Size.windowWidth, height: PK4Size.windowHeight)
        .mark("lamp", id, ["label": label, "color": "\(color)", "code": code ?? ""])
    }

    private func lettering(_ glass: LampGlass, lit: Bool) -> Color {
        if contrast == .increased && !lit {
            return glass.lightInk ? glass.inkOff : palette.bakelite
        }
        return lit ? glass.inkOn : glass.inkOff
    }

    static func == (lhs: LampWindow, rhs: LampWindow) -> Bool {
        lhs.label == rhs.label && lhs.color == rhs.color && lhs.state == rhs.state
            && lhs.code == rhs.code
    }
}

/// The two soft bulb spots at 23% and 77% across, falling off to nothing by the centre.
private struct HotSpots: View {
    var hot: Color

    var body: some View {
        GeometryReader { box in
            let w = box.size.width
            let h = box.size.height
            ForEach([0.24, 0.76], id: \.self) { x in
                EllipticalGradient(
                    stops: [
                        .init(color: hot, location: 0),
                        .init(color: hot.opacity(0.6), location: 0.45),
                        .init(color: hot.opacity(0), location: 1),
                    ], center: .center
                )
                .frame(width: w * 0.68, height: h * 2.2)
                .position(x: w * x, y: h / 2)
            }
        }
        // Light, not a surface: it reaches past the window and must not catch clicks.
        .allowsHitTesting(false)
    }
}

private struct Lettering: View {
    var label: String
    var size: CGFloat
    var code: String?
    var ink: Color
    var halo: Bool

    var body: some View {
        let twoLines = label.contains("\n")
        VStack(spacing: twoLines ? -1 : 1) {
            Text(label.plate)
                .font(PK4Type.label(size))
                .tracking(size * 0.06)
                // Barlow's own leading is 1.2; painted lettering sits at 1.0.
                .lineSpacing(-size * 0.25)
                .multilineTextAlignment(.center)
                .fixedSize()
                .mark("lampLabel", "", ["text": label, "size": "\(size)"])
            if let code {
                Text(code).font(PK4Type.label(twoLines ? 9 : 10)).tracking(0.4).fixedSize()
                    .mark("lampCode", "", ["text": code, "size": "\(twoLines ? 9 : 10)"])
            }
        }
        .foregroundStyle(ink)
        .shadow(color: .white.opacity(halo ? 0.55 : 0), radius: 2.5)
    }
}

/// The fixed glass on top of everything: the shadow the bezel throws onto it, a dark inner
/// line, and one diagonal sheen. It never changes with state, which is what makes the
/// window glass instead of a coloured rectangle.
struct GlassFace: View {
    var sheen = 0.30

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(sheen), location: 0),
                    .init(color: .white.opacity(0.08), location: 0.44),
                    .init(color: .white.opacity(0), location: 0.45),
                    .init(color: .black.opacity(0.14), location: 1),
                ], startPoint: UnitPoint(x: 0.43, y: 0), endPoint: UnitPoint(x: 0.57, y: 1))
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .black.opacity(0), location: 0.14),
                ], startPoint: .top, endPoint: .bottom)
            Rectangle().strokeBorder(.black.opacity(0.4), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// A 44-point round signal lamp: a chrome collar, domed glass, and its caption engraved
/// underneath. Always in an ON (green) and OFF (white) pair above a round button; both
/// dark means no answer from the machine.
struct LampLens: View, Equatable {
    var color: LampColor
    var state: LampState
    var id: String = ""

    static func == (lhs: LampLens, rhs: LampLens) -> Bool {
        lhs.color == rhs.color && lhs.state == rhs.state
    }

    @Environment(\.pk4) private var palette

    var body: some View {
        let glass = palette.glass(color)
        Filament(state: state) { level, _ in
            ZStack {
                // Chrome collar.
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Color(hex: 0xF6F7F2), Color(hex: 0x8E9189), Color(hex: 0xECEDE7),
                                Color(hex: 0x6C6F68), Color(hex: 0xDCDDD6), Color(hex: 0x868981),
                                Color(hex: 0xF6F7F2),
                            ], center: .center, angle: .degrees(215 - 90))
                    )
                    .overlay { Circle().strokeBorder(palette.bezel, lineWidth: 1.5) }
                    .shadow(color: .black.opacity(0.55), radius: 1.5, y: 2)
                    .overlay {
                        // The glow a lit lens spills on the paint.
                        Circle().fill(glass.on.opacity(palette.spillOpacity))
                            .padding(-5).blur(radius: palette.spillRadius / 2).opacity(level)
                            .allowsHitTesting(false)
                    }

                ZStack {
                    // Dark glass: clearly dead when unlit.
                    Circle().fill(glass.off)
                    Circle().fill(
                        RadialGradient(
                            stops: [
                                .init(color: .black.opacity(0.28), location: 0),
                                .init(color: .black.opacity(0.45), location: 0.45),
                                .init(color: .black.opacity(0.8), location: 1),
                            ], center: .center, startRadius: 0, endRadius: 16))

                    // Lit layer: one bulb, white-hot at the centre.
                    ZStack {
                        Circle().fill(glass.on)
                        Circle().fill(
                            RadialGradient(
                                stops: [
                                    .init(color: .white, location: 0),
                                    .init(color: .white, location: 0.09),
                                    .init(color: .white.opacity(0.6), location: 0.2),
                                    .init(color: .white.opacity(0), location: 0.52),
                                ], center: UnitPoint(x: 0.5, y: 0.54), startRadius: 0, endRadius: 16
                            ))
                        Circle().fill(
                            RadialGradient(
                                colors: [.clear, .black.opacity(0.4)], center: .center,
                                startRadius: 9,
                                endRadius: 16))
                    }
                    .opacity(level)

                    // The dome: fixed highlights and one moulded step.
                    Ellipse().fill(
                        RadialGradient(
                            colors: [.white.opacity(0.7), .clear], center: .center, startRadius: 0,
                            endRadius: 8)
                    )
                    .frame(width: 14, height: 9).offset(x: -3.5, y: -6)
                    Ellipse().fill(.white.opacity(0.14)).frame(width: 9, height: 4).blur(radius: 1)
                        .offset(x: 3.5, y: 10)
                    Circle().strokeBorder(.white.opacity(0.10), lineWidth: 0.8).padding(6)
                }
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(Color(hex: 0x0D0D0C), lineWidth: 1.5) }
                .padding(6)
            }
        }
        .frame(width: PK4Size.lens, height: PK4Size.lens)
        .mark("lens", id, ["color": "\(color)"])
    }
}
