import Foundation
import Testing

@testable import ConsoleKit

@Suite struct FormatTests {

    @Test func digitsHaveLeadingZerosAndOverflowToNines() {
        #expect(NixieFormat.digits(380_000, width: 8) == "00380000")
        #expect(NixieFormat.digits(0, width: 2) == "00")
        #expect(NixieFormat.digits(100, width: 2) == "99")
        #expect(NixieFormat.digits(123_456_789, width: 8) == "99999999")
        #expect(NixieFormat.digits(-5, width: 3) == "000")
        #expect(NixieFormat.digits(7, width: 1) == "7")
    }

    @Test func thousandsAreFloored() {
        #expect(NixieFormat.thousands(261_000_999, width: 8) == "00261000")
        #expect(NixieFormat.thousands(999, width: 8) == "00000000")
        #expect(NixieFormat.thousands(100_000_000_000, width: 8) == "99999999")
    }

    @Test func durationsCapAt9959() {
        #expect(NixieFormat.minutesSeconds(125) == "02:05")
        #expect(NixieFormat.minutesSeconds(749.9) == "12:29")
        #expect(NixieFormat.minutesSeconds(100 * 60) == "99:59")
        #expect(NixieFormat.minutesSeconds(-3) == "00:00")
        #expect(NixieFormat.hoursMinutes(3 * 3600 + 41 * 60 + 59) == "03:41")
        #expect(NixieFormat.hoursMinutes(100 * 3600) == "99:59")
        #expect(NixieFormat.hoursMinutes(.infinity) == "00:00")
        // The desk's column of six tubes.
        #expect(NixieFormat.minutesSeconds(125, leading: 4) == "0002:05")
        #expect(NixieFormat.hoursMinutes(100 * 3600, leading: 4) == "0100:00")
        #expect(NixieFormat.hoursMinutes(10_000 * 3600, leading: 4) == "9999:59")
    }

    @Test func costIsRoundedToTheCentAndOverflowsToNines() {
        #expect(NixieFormat.cost(42.17) == "0042.17")
        #expect(NixieFormat.cost(0.29) == "0000.29")
        #expect(NixieFormat.cost(9.4) == "0009.40")
        #expect(NixieFormat.cost(9999.994) == "9999.99")
        #expect(NixieFormat.cost(10_000) == "9999.99")
        #expect(NixieFormat.cost(-1) == "0000.00")
    }

    @Test func darkAndZeroKeepTheTemplatesLength() {
        #expect(NixieFormat.dark("0000.00") == "       ")
        #expect(NixieFormat.zero("00:00") == "00:00")
        for (id, template) in PK4.nixies {
            #expect(NixieFormat.dark(template).count == template.count, "\(id)")
        }
    }
}
