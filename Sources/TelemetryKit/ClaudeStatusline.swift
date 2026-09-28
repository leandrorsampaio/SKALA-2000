import Foundation

/// What Claude Code hands its status line command, as far as the desk uses it: the plan's
/// two usage windows. The rest of that JSON (paths, session ids) is never kept or logged.
///
/// `rate_limits.five_hour` and `.seven_day` each carry `used_percentage`, 0 to 100, and
/// `resets_at`, Unix seconds. They are there for Pro and Max plans once a session has had
/// its first answer, and each may be missing on its own. A reading lives until its window
/// resets: past that, the number is wrong.
public enum ClaudeStatusline {

    /// The windows the desk shows, and the fields each fills.
    static let windows: [(key: String, used: Field, resets: Field)] = [
        ("five_hour", .quotaSession, .quotaSessionResets),
        ("seven_day", .quotaWeek, .quotaWeekResets),
    ]

    public static func readings(from body: Data, at now: Date) -> [Reading] {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let limits = json["rate_limits"] as? [String: Any]
        else { return [] }
        var out: [Reading] = []
        for window in windows {
            guard let fields = limits[window.key] as? [String: Any],
                let percent = (fields["used_percentage"] as? NSNumber)?.doubleValue,
                percent.isFinite,
                let epoch = (fields["resets_at"] as? NSNumber)?.doubleValue, epoch.isFinite
            else { continue }
            let reset = Date(timeIntervalSince1970: epoch)
            let ttl = reset.timeIntervalSince(now)
            guard ttl > 0 else { continue }
            out.append(
                Reading(
                    .machine, window.used, .amount(min(1, max(0, percent / 100))), at: now,
                    ttl: ttl))
            out.append(Reading(.machine, window.resets, .time(reset), at: now, ttl: ttl))
        }
        return out
    }

    /// The line Claude Code shows under its prompt: the model, the context used, and the
    /// two windows, as much of it as the JSON has.
    public static func line(from body: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return ""
        }
        func percent(_ value: Any?) -> String? {
            guard let number = (value as? NSNumber)?.doubleValue, number.isFinite else {
                return nil
            }
            return "\(Int(min(999, max(0, number)).rounded()))%"
        }
        var parts: [String] = []
        if let model = (json["model"] as? [String: Any])?["display_name"] as? String {
            parts.append(model)
        }
        if let used = percent((json["context_window"] as? [String: Any])?["used_percentage"]) {
            parts.append("ctx \(used)")
        }
        let limits = json["rate_limits"] as? [String: Any]
        for (key, name) in [("five_hour", "5h"), ("seven_day", "week")] {
            if let used = percent((limits?[key] as? [String: Any])?["used_percentage"]) {
                parts.append("\(name) \(used)")
            }
        }
        return parts.joined(separator: " · ")
    }
}
