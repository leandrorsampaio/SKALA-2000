import Foundation
import Testing

@testable import TelemetryKit

/// The status line's JSON, as Claude Code documents it, and what the desk takes from it.
struct ClaudeStatuslineTests {

    let now = Date(timeIntervalSince1970: 1_790_330_400)

    func body(_ json: String) -> Data { Data(json.utf8) }

    @Test func theTwoWindowsBecomeReadingsThatLiveUntilTheyReset() throws {
        let json = """
            {"model":{"display_name":"Opus"},"context_window":{"used_percentage":37.4},
             "rate_limits":{"five_hour":{"used_percentage":6,"resets_at":1790334600},
                            "seven_day":{"used_percentage":72.5,"resets_at":1790600400}}}
            """
        let readings = ClaudeStatusline.readings(from: body(json), at: now)
        #expect(readings.count == 4)
        let session = try #require(readings.first { $0.field == .quotaSession })
        #expect(session.subject == .machine)
        #expect(session.value == .amount(0.06))
        #expect(session.ttl == 4200)
        let week = try #require(readings.first { $0.field == .quotaWeek })
        #expect(week.value == .amount(0.725))
        let resets = try #require(readings.first { $0.field == .quotaWeekResets })
        #expect(resets.value == .time(Date(timeIntervalSince1970: 1_790_600_400)))
    }

    /// Each window may be missing on its own, and one already reset says nothing.
    @Test func aMissingOrPastWindowIsLeftOut() {
        let json = """
            {"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":1790330000},
                            "seven_day":{"used_percentage":40}}}
            """
        #expect(ClaudeStatusline.readings(from: body(json), at: now).isEmpty)
        #expect(ClaudeStatusline.readings(from: body("{}"), at: now).isEmpty)
        #expect(ClaudeStatusline.readings(from: body("not json"), at: now).isEmpty)
    }

    @Test func aPercentageOutOfRangeIsHeldToTheScale() throws {
        let json = """
            {"rate_limits":{"five_hour":{"used_percentage":130,"resets_at":1790334600}}}
            """
        let readings = ClaudeStatusline.readings(from: body(json), at: now)
        #expect(readings.first { $0.field == .quotaSession }?.value == .amount(1))
    }

    @Test func theLineSaysWhatTheJSONHas() {
        let full = """
            {"model":{"display_name":"Opus 1M"},"context_window":{"used_percentage":37.4},
             "rate_limits":{"five_hour":{"used_percentage":6,"resets_at":1},
                            "seven_day":{"used_percentage":72.5,"resets_at":1}}}
            """
        #expect(ClaudeStatusline.line(from: body(full)) == "Opus 1M · ctx 37% · 5h 6% · week 73%")
        #expect(
            ClaudeStatusline.line(from: body(#"{"model":{"display_name":"Sonnet"}}"#)) == "Sonnet")
        #expect(ClaudeStatusline.line(from: body("nope")).isEmpty)
    }
}
