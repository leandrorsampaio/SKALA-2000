import Foundation

/// The five `claude.*` signals the menu bar panel's skins bind to, from one batch of the
/// same readings the PK-4 console reads.
///
/// The panel has room for one session, so it reports on one: a working session if there is
/// one, the most recently started otherwise. A batch without a roster says nothing — a
/// failed `claude agents` run — and the signals then run out their lifetime and go dark.
public enum ClaudeSummary {

    public struct Line: Sendable, Equatable {
        public var id: String
        public var label: String
        public var fraction: Double?
        public var text: String?
        public var active: Bool
    }

    public static func lines(from readings: [Reading]) -> [Line] {
        guard let keys = readings.first(where: { $0.field == .roster })?.value.keys else {
            return []
        }
        var fields: [SessionKey: [Field: Value]] = [:]
        for reading in readings {
            guard case .session(let key) = reading.subject else { continue }
            fields[key, default: [:]][reading.field] = reading.value
        }
        func value(_ key: SessionKey, _ field: Field) -> Value? { fields[key]?[field] }

        let busy = keys.filter { value($0, .status)?.text == "busy" }
        var lines = [
            Line(
                id: "claude.sessions", label: "Sessions", fraction: keys.isEmpty ? 0 : 1,
                text: sessionLine(total: keys.count, busy: busy.count), active: !keys.isEmpty),
            Line(
                id: "claude.busy", label: "Working",
                text: busy.first.flatMap { value($0, .name)?.text }, active: !busy.isEmpty),
        ]

        func started(_ key: SessionKey) -> Date { value(key, .startedAt)?.time ?? .distantPast }
        let candidates = busy.isEmpty ? keys : busy
        guard let chosen = candidates.max(by: { started($0) < started($1) }) else { return lines }

        if let used = value(chosen, .contextUsed)?.count,
            let window = value(chosen, .contextWindow)?.count, window > 0
        {
            // Room left, not room used: on a panel, a needle in the green has to mean fine.
            let left = max(0, window - used)
            let fraction = Double(left) / Double(window)
            lines.append(
                Line(
                    id: "claude.context", label: "Context", fraction: fraction,
                    text: "\(compact(left)) left", active: fraction <= 0.2))
        }
        if let cost = value(chosen, .costUSD)?.amount {
            lines.append(
                Line(
                    id: "claude.cost", label: "Cost at checkpoint",
                    text: String(format: "$%.2f", cost), active: false))
        }
        let output = value(chosen, .outputTokens)?.count ?? 0
        let input = value(chosen, .inputTokens)?.count ?? 0
        if output > 0 || input > 0 {
            lines.append(
                Line(
                    id: "claude.tokens", label: "Tokens",
                    text: "\(compact(output)) out · \(compact(input)) in", active: false))
        }
        return lines
    }

    public static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...:
            let millions = Double(value) / 1_000_000
            return millions < 10
                ? String(format: "%.1fM", millions) : "\(Int(millions.rounded()))M"
        case 1_000...:
            return "\(value / 1000)K"
        default:
            return "\(value)"
        }
    }

    public static func sessionLine(total: Int, busy: Int) -> String {
        guard total > 0 else { return "None running" }
        return busy > 0 ? "\(busy) of \(total) working" : "\(total) idle"
    }
}
