import XCTest

/// The conflict rules. Every case here maps to a way data was previously lost or reverted.
final class MergePolicyTests: XCTestCase {
    private let now = TestTime.now
    
    // MARK: - Dirty tracking
    
    func testRowNeverSyncedNeedsPush() {
        XCTAssertTrue(MergePolicy.needsPush(updatedAt: now, syncedAt: nil))
    }
    
    func testRowEditedAfterItsLastPushNeedsPush() {
        XCTAssertTrue(MergePolicy.needsPush(updatedAt: now, syncedAt: now.addingTimeInterval(-1)))
    }
    
    func testRowInStepWithServerIsNotPushed() {
        XCTAssertFalse(MergePolicy.needsPush(updatedAt: now, syncedAt: now))
    }
    
    /// A published row must stay clean, otherwise every poll re-uploads the whole table and
    /// idle devices start overwriting each other.
    func testSyncedAheadOfEditIsNotPushed() {
        XCTAssertFalse(MergePolicy.needsPush(updatedAt: now, syncedAt: now.addingTimeInterval(5)))
    }
    
    // MARK: - Last write wins
    
    func testNewerRemoteWins() {
        let remote = now.addingTimeInterval(10)
        XCTAssertEqual(
            MergePolicy.resolve(remoteUpdatedAt: remote, localUpdatedAt: now, localSyncedAt: now),
            .adoptRemote(remote)
        )
    }
    
    func testNewerLocalEditSurvivesAndIsQueued() {
        XCTAssertEqual(
            MergePolicy.resolve(remoteUpdatedAt: now.addingTimeInterval(-10),
                                localUpdatedAt: now,
                                localSyncedAt: nil),
            .republishLocal
        )
    }
    
    /// The exact shape of the "text reverts while typing" bug: a keystroke a fraction of a
    /// second newer than the server copy has to win.
    func testKeystrokeNewerBySubSecondSurvives() {
        let serverStamp = now
        let keystroke = now.addingTimeInterval(0.2)
        XCTAssertEqual(
            MergePolicy.resolve(remoteUpdatedAt: serverStamp, localUpdatedAt: keystroke, localSyncedAt: nil),
            .republishLocal
        )
    }
    
    /// The server takes whatever arrives last, even an older row, so a device holding the
    /// newer version must publish it again instead of quietly keeping it to itself. Without
    /// this the two devices disagree forever.
    func testServerHoldingAnOlderRowIsCorrectedEvenWhenLocalIsClean() {
        let localEdit = now
        XCTAssertEqual(
            MergePolicy.resolve(remoteUpdatedAt: now.addingTimeInterval(-30),
                                localUpdatedAt: localEdit,
                                localSyncedAt: localEdit),
            .republishLocal
        )
    }
    
    func testEqualTimestampsLeaveTheLocalRowAlone() {
        XCTAssertEqual(
            MergePolicy.resolve(remoteUpdatedAt: now, localUpdatedAt: now, localSyncedAt: now),
            .keepLocal
        )
    }
    
    /// A row whose server timestamp cannot be read is unusable for conflict resolution, so
    /// the local copy is republished rather than silently adopted or ignored forever.
    func testUnreadableRemoteTimestampTriggersRepublish() {
        XCTAssertEqual(
            MergePolicy.resolve(remoteUpdatedAt: nil, localUpdatedAt: now, localSyncedAt: now),
            .republishLocal
        )
    }
    
    // MARK: - Convergence
    
    /// Applying the same snapshot twice must not change anything the second time; otherwise
    /// two devices can ping-pong updates forever.
    func testResolveIsStableWhenRepeated() {
        let remote = now.addingTimeInterval(10)
        guard case .adoptRemote(let stamp) = MergePolicy.resolve(remoteUpdatedAt: remote,
                                                                localUpdatedAt: now,
                                                                localSyncedAt: now) else {
            return XCTFail("Expected the remote row to be adopted")
        }
        XCTAssertEqual(
            MergePolicy.resolve(remoteUpdatedAt: remote, localUpdatedAt: stamp, localSyncedAt: stamp),
            .keepLocal
        )
    }
}
