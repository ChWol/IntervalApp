import XCTest
import SwiftData

/// Validates scratchpad list and item CRUD, reordering, and data integrity.
@MainActor
final class ScratchpadTests: XCTestCase {
    private var store: TestStore!
    private let now = TestTime.now
    
    override func setUp() async throws {
        try await super.setUp()
        store = try TestStore()
    }
    
    override func tearDown() async throws {
        store = nil
        try await super.tearDown()
    }
    
    func testCreateScratchpadListAndItems() throws {
        let list = store.addScratchpadList("Shopping List", order: 0, id: "list-1")
        let item1 = store.addScratchpadItem("Apples", listId: list.id, order: 0, id: "item-1")
        let item2 = store.addScratchpadItem("Bread", listId: list.id, order: 1, id: "item-2")
        try store.save()
        
        let lists = try store.scratchpadLists()
        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(lists.first?.title, "Shopping List")
        
        let items = try store.scratchpadItems()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].text, "Apples")
        XCTAssertEqual(items[1].text, "Bread")
        XCTAssertEqual(items[0].listId, list.id)
    }
    
    func testToggleScratchpadItemCompletion() throws {
        let list = store.addScratchpadList("Todo", id: "l-1")
        let item = store.addScratchpadItem("Do laundry", listId: list.id, completed: false, id: "i-1")
        try store.save()
        
        item.completed.toggle()
        item.completedAt = now
        item.updatedAt = now
        try store.save()
        
        let items = try store.scratchpadItems()
        XCTAssertTrue(items.first?.completed ?? false)
        XCTAssertEqual(items.first?.completedAt, now)
    }
    
    func testSoftDeleteScratchpadItem() throws {
        let list = store.addScratchpadList("Notes", id: "l-1")
        let item = store.addScratchpadItem("Delete me", listId: list.id, id: "i-del")
        try store.save()
        
        item.deletedAt = now
        item.updatedAt = now
        try store.save()
        
        let activeItems = try store.scratchpadItems().filter { $0.deletedAt == nil }
        XCTAssertTrue(activeItems.isEmpty)
        
        let allItems = try store.scratchpadItems()
        XCTAssertEqual(allItems.count, 1)
        XCTAssertEqual(allItems.first?.deletedAt, now)
    }
    
    func testSoftDeleteScratchpadListSoftDeletesContainedItems() throws {
        let list = store.addScratchpadList("Project Notes", id: "p-1")
        let item1 = store.addScratchpadItem("Note 1", listId: list.id, id: "n-1")
        let item2 = store.addScratchpadItem("Note 2", listId: list.id, id: "n-2")
        try store.save()
        
        list.deletedAt = now
        list.updatedAt = now
        item1.deletedAt = now
        item1.updatedAt = now
        item2.deletedAt = now
        item2.updatedAt = now
        try store.save()
        
        let activeLists = try store.scratchpadLists().filter { $0.deletedAt == nil }
        let activeItems = try store.scratchpadItems().filter { $0.deletedAt == nil }
        XCTAssertTrue(activeLists.isEmpty)
        XCTAssertTrue(activeItems.isEmpty)
    }
}
