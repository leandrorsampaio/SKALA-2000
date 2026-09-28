import AppKit
import ConsoleKit
import CoreText
import SwiftUI

/// The PK-4 design system's tokens, from `tokens.json`: colours for the two themes, the
/// three paint finishes, type, spacing and sizes.
///
/// Day is the room with its lights on; night is the room dimmed, where the enamel and the
/// unlit glass darken and lit glass keeps its full value, so glow dominates. Night follows
/// the Mac's Dark appearance.
public struct PK4Palette: Sendable {

    public let isNight: Bool

    public init(night: Bool) { isNight = night }

    private func pick(_ day: UInt32, _ night: UInt32) -> Color {
        Color(hex: isNight ? night : day)
    }

    // Paint
    public var enamel: Color { pick(0xA9B3A2, 0x59615A) }
    public var enamelPanel: Color { pick(0xB7BFAE, 0x667067) }
    public var enamelEdge: Color { pick(0x5D6659, 0x2F3631) }
    public var enamelRecess: Color { pick(0x9AA493, 0x525B53) }
    public var finishIvory: Color { pick(0xD9D2BD, 0x8A8572) }
    public var finishIvoryEdge: Color { pick(0x8F8974, 0x55513F) }
    public var inkOnIvory: Color { pick(0x1B1B19, 0xF1EFE6) }
    public var finishGraphite: Color { pick(0x34383A, 0x232628) }
    public var finishGraphiteEdge: Color { pick(0x15181A, 0x0C0E0F) }
    public var inkOnGraphite: Color { pick(0xE9E6DA, 0xE9E6DA) }
    public var ink: Color { pick(0x1B1B19, 0xF1EFE6) }

    // Materials
    public var bakelite: Color { pick(0x1B1B19, 0x111110) }
    public var engraving: Color { pick(0xF1EFE6, 0xE6E3D6) }
    public var bezel: Color { pick(0x2A2A27, 0x151513) }
    public var aluminium: Color { pick(0xC9CBC3, 0x8D9088) }
    public var tag: Color { pick(0xD5D7D0, 0x9A9D95) }
    public var tagInk: Color { pick(0x1B1B19, 0x111110) }
    public var paper: Color { pick(0xEFECE0, 0xCFCAB8) }
    public var instruction: Color { pick(0xF0E2A8, 0xC9B96F) }
    public var meterFace: Color { pick(0xEFE4BF, 0xD9CD9F) }
    public var brass: Color { pick(0xB9A25A, 0x8A7636) }
    public var stockroomRed: Color { pick(0xA3200F, 0xD9523F) }

    // Glow
    public var nixieGlass: Color { pick(0x3B1406, 0x2A0E04) }
    public var nixieGlow: Color { pick(0xFF9A3A, 0xFFA64D) }
    public var nixieHalo: Color { Color(hex: 0xFF6A00) }
    public var drumWheel: Color { pick(0xF1EFE6, 0xD8D5C8) }
    public var drumInk: Color { Color(hex: 0x111111) }

    /// How strongly a lit lamp spills onto the paint: faint in a lit room, stronger in the
    /// dark, and never a shape you can see.
    public var spillOpacity: Double { isNight ? 0.42 : 0.20 }
    public var spillRadius: CGFloat { isNight ? 26 : 22 }

    public func glass(_ color: LampColor) -> LampGlass {
        switch color {
        case .red:
            LampGlass(
                on: Color(hex: 0xC8321F), hot: Color(hex: 0xE8664F),
                spill: Color(hex: 0xF4B3A7),
                off: pick(0x8E5A50, 0x5F3A33),
                inkOff: Color(hex: 0xF6E8E4), inkOn: Color(hex: 0xFFF3EC), lightInk: true)
        case .green:
            LampGlass(
                on: Color(hex: 0x25783E), hot: Color(hex: 0x3F9A5A),
                spill: Color(hex: 0x9FCDAD),
                off: pick(0x55705A, 0x34473A),
                inkOff: Color(hex: 0xE6F0E7), inkOn: Color(hex: 0xF2FFF4), lightInk: true)
        case .amber:
            LampGlass(
                on: Color(hex: 0xF0B323), hot: Color(hex: 0xFFD36B),
                spill: Color(hex: 0xFFE9B5),
                off: pick(0xA08A4A, 0x9A8546),
                inkOff: Color(hex: 0x1B1B19), inkOn: Color(hex: 0x4A2F00), lightInk: false)
        case .white:
            LampGlass(
                on: Color(hex: 0xFFE9A8), hot: Color(hex: 0xFFF8DC),
                spill: Color(hex: 0xFFFCEE),
                off: pick(0xC2B88F, 0xA39A78),
                inkOff: Color(hex: 0x1B1B19), inkOn: Color(hex: 0x4A3A12), lightInk: false)
        }
    }

    /// The finish's ground, border and painted ink.
    public func paint(_ finish: Finish) -> (ground: Color, edge: Color, ink: Color) {
        switch finish {
        case .greyGreen: (enamelPanel, enamelEdge, ink)
        case .ivory: (finishIvory, finishIvoryEdge, inkOnIvory)
        case .graphite: (finishGraphite, finishGraphiteEdge, inkOnGraphite)
        }
    }
}

/// The four lamp colours. One meaning each: red, the operator must act; amber, abnormal
/// but not urgent; green, working or on; white, plain status.
public enum LampColor: Sendable {
    case red, amber, green, white
}

/// A colour of glass and the paint on it. Lettering never flips between light and dark;
/// it only takes on the lamp's light.
public struct LampGlass: Sendable {
    public let on: Color
    public let hot: Color
    /// The light a lit lamp throws on the paint: its hot colour halfway to white, so the
    /// paint under it only ever gets lighter.
    public let spill: Color
    public let off: Color
    public let inkOff: Color
    public let inkOn: Color
    /// Light ink on red and green glass, dark ink on amber and white.
    public let lightInk: Bool
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}

// MARK: - Environment

struct PaletteKey: EnvironmentKey {
    static let defaultValue = PK4Palette(night: false)
}

struct FinishKey: EnvironmentKey {
    static let defaultValue = Finish.greyGreen
}

struct LampCodesKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var pk4: PK4Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }

    var pk4Finish: Finish {
        get { self[FinishKey.self] }
        set { self[FinishKey.self] = newValue }
    }

    /// Whether lamp windows carry their HL designator under the lettering.
    var pk4LampCodes: Bool {
        get { self[LampCodesKey.self] }
        set { self[LampCodesKey.self] = newValue }
    }
}

// MARK: - Type

/// The five faces, bundled and registered for this app only. Digits are never set in a
/// system font: if Nixie One is missing, the face below it is a fallback, not a choice.
public enum PK4Type {

    /// Registers the bundled faces. Safe to call more than once.
    @MainActor
    public static func register(from folder: URL? = nil) {
        guard !registered else { return }
        let folder = folder ?? Self.defaultFolder
        guard let folder,
            let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil)
        else { return }
        let fonts = files.filter { $0.pathExtension == "ttf" }
        CTFontManagerRegisterFontURLs(fonts as CFArray, .process, true, nil)
        registered = true
    }

    @MainActor private static var registered = false

    /// Inside the app bundle, or the repository when run from `swift test`.
    static var defaultFolder: URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Fonts/PK4"),
            FileManager.default.fileExists(atPath: bundled.path)
        {
            return bundled
        }
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Fonts/PK4")
        return FileManager.default.fileExists(atPath: repository.path) ? repository : nil
    }

    /// Painted on glass, caps, scales and enamel.
    static func label(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "BarlowCondensed-Bold" : "BarlowCondensed-SemiBold", fixedSize: size)
    }

    /// Cut into bakelite or stamped on a tag.
    static func engraved(_ size: CGFloat) -> Font {
        .custom("Dosis-SemiBold", fixedSize: size)
    }

    static func nixie(_ size: CGFloat) -> Font {
        .custom("NixieOne-Regular", fixedSize: size)
    }

    static func marker(_ size: CGFloat) -> Font {
        .custom("PermanentMarker-Regular", fixedSize: size)
    }

    static func pencil(_ size: CGFloat) -> Font {
        .custom("Caveat-Regular", fixedSize: size)
    }

    /// The paper card in the header is typed.
    static func typewriter(_ size: CGFloat) -> Font {
        .custom("Courier New", fixedSize: size)
    }
}

/// Spacing, radii and sizes, in the desk's own units.
enum PK4Size {
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 14
    static let space4: CGFloat = 16
    static let space5: CGFloat = 18
    static let space6: CGFloat = 24

    static let windowWidth: CGFloat = 96
    static let windowHeight: CGFloat = 46
    static let button: CGFloat = 64
    static let lens: CGFloat = 44
    static let tube = CGSize(width: 28, height: 48)
    static let tubeXL = CGSize(width: 54, height: 84)
    static let wheel = CGSize(width: 22, height: 32)

    /// The whole desk is one drawing this wide, scaled to the window.
    static let deskWidth: CGFloat = 2500
    static let deskHeight: CGFloat = 1800
}

extension String {
    /// All lettering on the desk is uppercase.
    var plate: String { uppercased() }
}
