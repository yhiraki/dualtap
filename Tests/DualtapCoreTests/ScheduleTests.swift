import XCTest
@testable import DualtapCore

final class ScheduleTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        var comp = DateComponents()
        comp.year = y; comp.month = mo; comp.day = d
        comp.hour = h; comp.minute = mi; comp.second = s
        return utc.date(from: comp)!
    }

    func testParseDurationPlainSeconds() {
        XCTAssertEqual(parseDuration("90"), 90)
        XCTAssertEqual(parseDuration("0"), 0)
    }

    func testParseDurationUnits() {
        XCTAssertEqual(parseDuration("45s"), 45)
        XCTAssertEqual(parseDuration("5m"), 300)
        XCTAssertEqual(parseDuration("1h"), 3600)
        XCTAssertEqual(parseDuration("1h30m"), 5400)
        XCTAssertEqual(parseDuration("1h30m15s"), 5415)
        XCTAssertEqual(parseDuration("90m"), 5400)
    }

    func testParseDurationInvalid() {
        XCTAssertNil(parseDuration(""))
        XCTAssertNil(parseDuration("abc"))
        XCTAssertNil(parseDuration("1x"))
        XCTAssertNil(parseDuration("1h30"))   // trailing number with no unit
        XCTAssertNil(parseDuration("-5"))
    }

    func testParseClockTimeLaterToday() {
        let now = date(2026, 7, 4, 10, 0)
        let got = parseClockTime("14:30", now: now, calendar: utc)
        XCTAssertEqual(got, date(2026, 7, 4, 14, 30))
    }

    func testParseClockTimeWithSeconds() {
        let now = date(2026, 7, 4, 10, 0)
        let got = parseClockTime("14:30:15", now: now, calendar: utc)
        XCTAssertEqual(got, date(2026, 7, 4, 14, 30, 15))
    }

    func testParseClockTimeRollsToTomorrow() {
        let now = date(2026, 7, 4, 10, 0)
        let got = parseClockTime("09:00", now: now, calendar: utc)
        XCTAssertEqual(got, date(2026, 7, 5, 9, 0))
    }

    func testParseClockTimeInvalid() {
        let now = date(2026, 7, 4, 10, 0)
        XCTAssertNil(parseClockTime("25:00", now: now, calendar: utc))
        XCTAssertNil(parseClockTime("12:60", now: now, calendar: utc))
        XCTAssertNil(parseClockTime("noon", now: now, calendar: utc))
        XCTAssertNil(parseClockTime("12", now: now, calendar: utc))
    }
}
