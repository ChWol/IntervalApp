import XCTest

@MainActor
final class ScratchpadAccessRevocationTests: XCTestCase {
    func testRevokedSharedListAndItemsAreRemovedFromLocalCacheImmediately() throws {
        let store = try TestStore()
        let list = store.addScratchpadList("Formerly shared", id: "shared")
        list.ownerId = "owner"
        list.syncedAt = TestTime.now
        list.updatedAt = TestTime.now
        let item = store.addScratchpadItem("Private note", listId: list.id, id: "note", updatedAt: TestTime.now)
        item.syncedAt = TestTime.now
        try store.save()
        let manager = SupabaseSyncManager.makeForTesting(context: store.context, uid: "former-member")

        _ = manager.testingMergeScratchpads(lists: [], items: [])

        XCTAssertTrue(try store.scratchpadLists().isEmpty)
        XCTAssertTrue(try store.scratchpadItems().isEmpty)
    }

    func testOwnedScratchpadNeedsTwoCompleteSnapshotsBeforePruning() throws {
        let store = try TestStore()
        let list = store.addScratchpadList("Owned", id: "owned", updatedAt: TestTime.now)
        list.ownerId = "owner"
        list.syncedAt = TestTime.now
        try store.save()
        let manager = SupabaseSyncManager.makeForTesting(context: store.context, uid: "owner")

        _ = manager.testingMergeScratchpads(lists: [], items: [])
        XCTAssertEqual(try store.scratchpadLists().count, 1)

        _ = manager.testingMergeScratchpads(lists: [], items: [])
        XCTAssertTrue(try store.scratchpadLists().isEmpty)
    }
}
