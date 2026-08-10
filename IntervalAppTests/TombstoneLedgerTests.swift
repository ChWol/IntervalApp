import XCTest

/// Deletes are the easiest thing to lose: the row is gone locally, so nothing is left to
/// retry with unless it was written down first.
final class TombstoneLedgerTests: XCTestCase {
    private let now = TestTime.now
    
    func testRecordedIdIsRecognisedAndPending() {
        var ledger = TombstoneLedger()
        ledger.add(table: SyncTable.tasks, ids: ["a", "b"], now: now)
        
        XCTAssertTrue(ledger.contains(table: SyncTable.tasks, id: "a"))
        XCTAssertFalse(ledger.contains(table: SyncTable.tasks, id: "c"))
        XCTAssertEqual(ledger.unconfirmedIds(table: SyncTable.tasks), ["a", "b"])
    }
    
    func testTablesAreKeptApart() {
        var ledger = TombstoneLedger()
        ledger.add(table: SyncTable.tasks, ids: ["shared-id"], now: now)
        
        XCTAssertFalse(ledger.contains(table: SyncTable.habits, id: "shared-id"))
        XCTAssertTrue(ledger.unconfirmedIds(table: SyncTable.habits).isEmpty)
    }
    
    func testAddingTwiceKeepsTheOriginalRecord() {
        var ledger = TombstoneLedger()
        ledger.add(table: SyncTable.tasks, ids: ["a"], now: now)
        ledger.confirm(table: SyncTable.tasks, ids: ["a"], now: now)
        ledger.add(table: SyncTable.tasks, ids: ["a"], now: now.addingTimeInterval(60))
        
        XCTAssertEqual(ledger.count(table: SyncTable.tasks), 1)
        XCTAssertTrue(ledger.unconfirmedIds(table: SyncTable.tasks).isEmpty,
                      "A re-reported delete must not queue a second server round trip")
    }
    
    func testConfirmedIdStopsBeingRetriedButStillBlocksTheRow() {
        var ledger = TombstoneLedger()
        ledger.add(table: SyncTable.tasks, ids: ["a"], now: now)
        ledger.confirm(table: SyncTable.tasks, ids: ["a"], now: now)
        
        XCTAssertTrue(ledger.unconfirmedIds(table: SyncTable.tasks).isEmpty)
        XCTAssertTrue(ledger.contains(table: SyncTable.tasks, id: "a"),
                      "An in-flight pull could still be carrying this row")
    }
    
    func testUnconfirmedDeleteIsRetriedForever() {
        var ledger = TombstoneLedger()
        ledger.add(table: SyncTable.tasks, ids: ["offline"], now: now)
        ledger.pruneConfirmed(now: now.addingTimeInterval(TestTime.days(30)))
        
        XCTAssertEqual(ledger.unconfirmedIds(table: SyncTable.tasks), ["offline"],
                       "A delete that never reached the server must survive any amount of time offline")
    }
    
    func testConfirmedRecordIsDroppedOnceItCannotBeContradicted() {
        var ledger = TombstoneLedger()
        ledger.add(table: SyncTable.tasks, ids: ["a"], now: now)
        ledger.confirm(table: SyncTable.tasks, ids: ["a"], now: now)
        
        ledger.pruneConfirmed(now: now.addingTimeInterval(TombstoneLedger.confirmedRetention - 60))
        XCTAssertTrue(ledger.contains(table: SyncTable.tasks, id: "a"), "Still inside the retention window")
        
        ledger.pruneConfirmed(now: now.addingTimeInterval(TombstoneLedger.confirmedRetention + 60))
        XCTAssertFalse(ledger.contains(table: SyncTable.tasks, id: "a"))
        XCTAssertTrue(ledger.isEmpty)
    }
    
    /// Durability across restarts is the whole point, so the encoded form has to round trip.
    func testSurvivesEncodingRoundTrip() {
        var ledger = TombstoneLedger()
        ledger.add(table: SyncTable.tasks, ids: ["a", "b"], now: now)
        ledger.add(table: SyncTable.habits, ids: ["h"], now: now)
        ledger.confirm(table: SyncTable.tasks, ids: ["b"], now: now)
        
        let restored = TombstoneLedger.decode(from: ledger.encoded())
        
        XCTAssertEqual(restored, ledger)
        XCTAssertEqual(restored.unconfirmedIds(table: SyncTable.tasks), ["a"])
        XCTAssertEqual(restored.unconfirmedIds(table: SyncTable.habits), ["h"])
        XCTAssertTrue(restored.contains(table: SyncTable.tasks, id: "b"))
    }
    
    func testDecodingRubbishYieldsAnEmptyLedgerRatherThanCrashing() {
        XCTAssertTrue(TombstoneLedger.decode(from: nil).isEmpty)
        XCTAssertTrue(TombstoneLedger.decode(from: Data("not json".utf8)).isEmpty)
    }
    
    func testRemoveAllClearsEveryTable() {
        var ledger = TombstoneLedger()
        ledger.add(table: SyncTable.tasks, ids: ["a"], now: now)
        ledger.add(table: SyncTable.habits, ids: ["h"], now: now)
        ledger.removeAll()
        
        XCTAssertTrue(ledger.isEmpty)
        XCTAssertFalse(ledger.contains(table: SyncTable.tasks, id: "a"))
    }
}
