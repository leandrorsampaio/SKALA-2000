import ConsoleKit
import CoreGraphics

/// A colour in sRGB from `0xRRGGBB`.
@inline(__always)
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

@inline(__always)
func white(_ alpha: CGFloat) -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha) }

@inline(__always)
func black(_ alpha: CGFloat) -> CGColor { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha) }

extension CGColor {
    /// The same colour at `alpha` times its own opacity.
    func opacity(_ alpha: CGFloat) -> CGColor { copy(alpha: self.alpha * alpha) ?? self }
}

/// The design system's colours for the two themes, from `tokens.json` by way of the
/// reference's `PK4Palette`.
///
/// Day is the room with its lights on; night is the room dimmed, where the enamel and the
/// unlit glass darken and lit glass keeps its full value, so glow dominates. Night follows
/// the Mac's Dark appearance.
public struct Palette: Sendable, Hashable {

    public let isNight: Bool

    public init(night: Bool) { isNight = night }

    private func pick(_ day: UInt32, _ night: UInt32) -> CGColor { rgb(isNight ? night : day) }

    // Paint
    var enamel: CGColor { pick(0xA9B3A2, 0x59615A) }
    var enamelPanel: CGColor { pick(0xB7BFAE, 0x667067) }
    var enamelEdge: CGColor { pick(0x5D6659, 0x2F3631) }
    var enamelRecess: CGColor { pick(0x9AA493, 0x525B53) }
    var finishIvory: CGColor { pick(0xD9D2BD, 0x8A8572) }
    var finishIvoryEdge: CGColor { pick(0x8F8974, 0x55513F) }
    var inkOnIvory: CGColor { pick(0x1B1B19, 0xF1EFE6) }
    var finishGraphite: CGColor { pick(0x34383A, 0x232628) }
    var finishGraphiteEdge: CGColor { pick(0x15181A, 0x0C0E0F) }
    var inkOnGraphite: CGColor { pick(0xE9E6DA, 0xE9E6DA) }
    var ink: CGColor { pick(0x1B1B19, 0xF1EFE6) }

    // Materials
    var bakelite: CGColor { pick(0x1B1B19, 0x111110) }
    var engraving: CGColor { pick(0xF1EFE6, 0xE6E3D6) }
    var bezel: CGColor { pick(0x2A2A27, 0x151513) }
    var aluminium: CGColor { pick(0xC9CBC3, 0x8D9088) }
    var tag: CGColor { pick(0xD5D7D0, 0x9A9D95) }
    var tagInk: CGColor { pick(0x1B1B19, 0x111110) }
    var paper: CGColor { pick(0xEFECE0, 0xCFCAB8) }
    var instruction: CGColor { pick(0xF0E2A8, 0xC9B96F) }
    var meterFace: CGColor { pick(0xEFE4BF, 0xD9CD9F) }
    var brass: CGColor { pick(0xB9A25A, 0x8A7636) }
    var stockroomRed: CGColor { pick(0xA3200F, 0xD9523F) }

    // Glow
    var nixieGlass: CGColor { pick(0x3B1406, 0x2A0E04) }
    var nixieGlow: CGColor { pick(0xFF9A3A, 0xFFA64D) }
    var nixieHalo: CGColor { rgb(0xFF6A00) }
    var drumWheel: CGColor { pick(0xF1EFE6, 0xD8D5C8) }
    var drumInk: CGColor { rgb(0x111111) }

    /// How strongly a lit lamp spills onto the paint: faint in a lit room, stronger in the
    /// dark, and never a shape you can see.
    var spillOpacity: CGFloat { isNight ? 0.42 : 0.20 }
    var spillRadius: CGFloat { isNight ? 26 : 22 }

    func glass(_ color: LampColor) -> LampGlass {
        switch color {
        case .red:
            LampGlass(
                on: rgb(0xC8321F), hot: rgb(0xE8664F), off: pick(0x8E5A50, 0x5F3A33),
                inkOff: rgb(0xF6E8E4), inkOn: rgb(0xFFF3EC), lightInk: true)
        case .green:
            LampGlass(
                on: rgb(0x25783E), hot: rgb(0x3F9A5A), off: pick(0x55705A, 0x34473A),
                inkOff: rgb(0xE6F0E7), inkOn: rgb(0xF2FFF4), lightInk: true)
        case .amber:
            LampGlass(
                on: rgb(0xF0B323), hot: rgb(0xFFD36B), off: pick(0xA08A4A, 0x9A8546),
                inkOff: rgb(0x1B1B19), inkOn: rgb(0x4A2F00), lightInk: false)
        case .white:
            LampGlass(
                on: rgb(0xFFE9A8), hot: rgb(0xFFF8DC), off: pick(0xC2B88F, 0xA39A78),
                inkOff: rgb(0x1B1B19), inkOn: rgb(0x4A3A12), lightInk: false)
        }
    }

    /// The finish's ground, border and painted ink.
    func paint(_ finish: Finish) -> (ground: CGColor, edge: CGColor, ink: CGColor) {
        switch finish {
        case .greyGreen: (enamelPanel, enamelEdge, ink)
        case .ivory: (finishIvory, finishIvoryEdge, inkOnIvory)
        case .graphite: (finishGraphite, finishGraphiteEdge, inkOnGraphite)
        }
    }

    /// The window background behind the desk: what shows at its rounded corners and around
    /// it in full screen.
    public static let surround = rgb(0x1A1C1B)
}

/// The four lamp colours. One meaning each: red, the operator must act; amber, abnormal
/// but not urgent; green, working or on; white, plain status.
public enum LampColor: String, Sendable, CaseIterable {
    case red, amber, green, white
}

/// A colour of glass and the paint on it. Lettering never flips between light and dark;
/// it only takes on the lamp's light.
struct LampGlass {
    let on: CGColor
    let hot: CGColor
    let off: CGColor
    let inkOff: CGColor
    let inkOn: CGColor
    /// Light ink on red and green glass, dark ink on amber and white.
    let lightInk: Bool
}

/// Everything that decides how the art looks, apart from its size.
public struct ArtStyle: Sendable, Hashable {
    public var night: Bool
    public var finish: Finish
    public var increasedContrast: Bool
    /// Whether lamp windows carry their HL designator under the lettering.
    public var lampCodes: Bool

    public init(
        night: Bool = false, finish: Finish = .greyGreen, increasedContrast: Bool = false,
        lampCodes: Bool = true
    ) {
        self.night = night
        self.finish = finish
        self.increasedContrast = increasedContrast
        self.lampCodes = lampCodes
    }

    var palette: Palette { Palette(night: night) }

    /// A short, stable name, for cache keys and file names.
    public var key: String {
        "\(night ? "night" : "day")-\(finish.rawValue)\(increasedContrast ? "-hc" : "")"
            + (lampCodes ? "" : "-nocodes")
    }
}
