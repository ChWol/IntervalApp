import XCTest

@MainActor
final class PersistenceSafetyTests: XCTestCase {
    private struct ExpectedFailure: LocalizedError {
        var errorDescription: String? { "disk unavailable" }
    }

    func testSuccessfulSaveReturnsTrueWithoutReporting() {
        var reports: [String] = []
        let result = PersistenceSafety.attempt(
            operation: "Saving task",
            save: {},
            report: { reports.append($0) }
        )

        XCTAssertTrue(result)
        XCTAssertTrue(reports.isEmpty)
    }

    func testFailedSaveReturnsFalseAndReportsRecoverableState() {
        var reports: [String] = []
        let result = PersistenceSafety.attempt(
            operation: "Saving task",
            save: { throw ExpectedFailure() },
            report: { reports.append($0) }
        )

        XCTAssertFalse(result)
        XCTAssertEqual(reports.count, 1)
        XCTAssertTrue(reports[0].contains("Saving task failed"))
        XCTAssertTrue(reports[0].contains("still pending locally"))
        XCTAssertTrue(reports[0].contains("disk unavailable"))
    }

    func testBackgroundTransitionSchedulesSyncAfterSuccessfulSave() {
        var events: [String] = []

        PersistenceSafety.prepareForBackground(
            save: {
                events.append("save")
                return true
            },
            scheduleSync: { events.append("sync") }
        )

        XCTAssertEqual(events, ["save", "sync"])
    }

    func testBackgroundTransitionDoesNotSyncAfterFailedSave() {
        var events: [String] = []

        PersistenceSafety.prepareForBackground(
            save: {
                events.append("save")
                return false
            },
            scheduleSync: { events.append("sync") }
        )

        XCTAssertEqual(events, ["save"])
    }

    func testStorageFullFailureIsRecoverableAndReportedWithoutDiscardingPendingWork() {
        let diskFull = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteOutOfSpaceError,
            userInfo: [NSLocalizedDescriptionKey: "The disk is full"]
        )
        var report = ""

        let saved = PersistenceSafety.attempt(
            operation: "Saving task",
            save: { throw diskFull },
            report: { report = $0 }
        )

        XCTAssertFalse(saved)
        XCTAssertTrue(report.contains("still pending locally"))
        XCTAssertTrue(report.localizedCaseInsensitiveContains("disk is full"))
    }
}
