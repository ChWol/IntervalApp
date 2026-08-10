import XCTest

/// Timestamps decide every conflict, so an unparsed one is a silent data-loss bug: the row
/// reads as `distantPast` and always loses. These cover the shapes Postgres and PostgREST
/// actually return.
final class SyncTimestampTests: XCTestCase {
    /// 2026-06-15 12:00:00 UTC
    private let reference = Date(timeIntervalSince1970: 1_781_524_800)
    
    func testParsesISO8601WithFractionalSeconds() {
        XCTAssertEqual(SyncTimestamp.parse("2026-06-15T12:00:00.000Z"), reference)
        XCTAssertEqual(SyncTimestamp.parse("2026-06-15T12:00:00.123456Z")?.timeIntervalSince1970 ?? 0,
                       reference.timeIntervalSince1970,
                       accuracy: 0.5)
    }
    
    func testParsesISO8601WithoutFractionalSeconds() {
        XCTAssertEqual(SyncTimestamp.parse("2026-06-15T12:00:00Z"), reference)
    }
    
    func testParsesExplicitOffsets() {
        XCTAssertEqual(SyncTimestamp.parse("2026-06-15T14:00:00+02:00"), reference)
        XCTAssertEqual(SyncTimestamp.parse("2026-06-15T12:00:00+00:00"), reference)
    }
    
    /// Postgres renders `timestamptz` with a space and a `+00` offset.
    func testParsesPostgresSpaceSeparatedForm() {
        XCTAssertEqual(SyncTimestamp.parse("2026-06-15 12:00:00+00:00"), reference)
        XCTAssertEqual(SyncTimestamp.parse("2026-06-15 12:00:00.000000+00:00"), reference)
    }
    
    /// A plain `timestamp` column has no zone at all; Postgres treats it as UTC.
    func testParsesTimestampWithoutTimezoneAsUTC() {
        XCTAssertEqual(SyncTimestamp.parse("2026-06-15T12:00:00"), reference)
        XCTAssertEqual(SyncTimestamp.parse("2026-06-15 12:00:00"), reference)
        XCTAssertEqual(SyncTimestamp.parse("2026-06-15T12:00:00.000000"), reference)
    }
    
    func testToleratesSurroundingWhitespace() {
        XCTAssertEqual(SyncTimestamp.parse("  2026-06-15T12:00:00Z  "), reference)
    }
    
    func testRejectsUnusableValues() {
        XCTAssertNil(SyncTimestamp.parse(nil))
        XCTAssertNil(SyncTimestamp.parse(""))
        XCTAssertNil(SyncTimestamp.parse("   "))
        XCTAssertNil(SyncTimestamp.parse("not a date"))
        XCTAssertNil(SyncTimestamp.parse("15/06/2026"))
    }
    
    /// What we write must be what we can read back, or every row we push looks changed.
    func testRoundTripsWhatItWrites() {
        let dates = [
            reference,
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 1_781_524_800.5),
            Date(timeIntervalSince1970: 2_000_000_000.999)
        ]
        for date in dates {
            let text = SyncTimestamp.format(date)
            guard let parsed = SyncTimestamp.parse(text) else {
                return XCTFail("Could not parse \(text), produced from \(date)")
            }
            XCTAssertEqual(parsed.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001,
                           "Round trip drifted for \(text)")
        }
    }
    
    func testFormatsInUTC() {
        XCTAssertTrue(SyncTimestamp.format(reference).hasPrefix("2026-06-15T12:00:00"),
                      "Expected UTC output, got \(SyncTimestamp.format(reference))")
    }
}
