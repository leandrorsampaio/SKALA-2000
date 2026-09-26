import Foundation

/// Fixed-width readings for nixie rows: leading zeros, no separators, all nines on overflow.
///
/// A readout has a fixed number of tubes and never grows a wider window, so every function
/// here returns exactly as many characters as it was asked for.
public enum NixieFormat {

    /// Every tube unlit, separators included: a dark readout shows no digit and no dot.
    public static func dark(_ template: String) -> String {
        String(repeating: " ", count: template.count)
    }

    /// Every tube lit at zero, separators kept. What an empty slot reads.
    public static func zero(_ template: String) -> String {
        String(template.map { $0.isNumber ? "0" : $0 })
    }

    /// Every cathode of every tube at once, as a lamp test and the power-up strike show them.
    public static func allEights(_ template: String) -> String {
        String(template.map { $0.isNumber ? "8" : $0 })
    }

    public static func digits(_ value: Int, width: Int) -> String {
        guard width > 0 else { return "" }
        let clamped = max(0, value)
        let text = String(clamped)
        guard text.count <= width else { return String(repeating: "9", count: width) }
        return String(repeating: "0", count: width - text.count) + text
    }

    /// Divided by a thousand and floored, for the ×1000 rows.
    public static func thousands(_ value: Int, width: Int) -> String {
        digits(max(0, value) / 1000, width: width)
    }

    /// `mm:ss`, with as many minute tubes as asked for, capped at all nines and `:59`.
    public static func minutesSeconds(_ seconds: TimeInterval, leading: Int = 2) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds)) : 0
        return clock(total / 60, total % 60, leading: leading)
    }

    /// `hh:mm`, with as many hour tubes as asked for, capped at all nines and `:59`.
    public static func hoursMinutes(_ seconds: TimeInterval, leading: Int = 2) -> String {
        let minutes = seconds.isFinite ? max(0, Int(seconds / 60)) : 0
        return clock(minutes / 60, minutes % 60, leading: leading)
    }

    private static func clock(_ major: Int, _ minor: Int, leading: Int) -> String {
        let limit = Int(pow(10, Double(leading)))
        guard major < limit else { return String(repeating: "9", count: leading) + ":59" }
        return digits(major, width: leading) + ":" + digits(minor, width: 2)
    }

    /// `0000.00` dollars.
    public static func cost(_ dollars: Double) -> String {
        guard dollars.isFinite else { return "0000.00" }
        // Rounded to the cent, not floored: 0.29 is 28.999… in binary.
        let cents = max(0, Int((dollars * 100).rounded()))
        guard cents < 1_000_000 else { return "9999.99" }
        return digits(cents / 100, width: 4) + "." + digits(cents % 100, width: 2)
    }
}
