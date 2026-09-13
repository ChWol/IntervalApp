import SwiftData
import XCTest

@MainActor
final class DataIntegrityRepairTests: XCTestCase {
    func testRepairsInvalidIdentityIntervalAndRelationshipsWithoutDeletingText() throws {
        let store = try TestStore()
        let habit = HabitItem(text: "Meditate", frequency: "Daily", order: 0)
        habit.id = ""
        let list = ScratchpadList(title: "Thoughts", order: 0)
        list.id = "   "
        let task = TaskItem(text: "Keep this thought", intervalType: "Unknown", habitId: "")
        task.id = ""
        let item = ScratchpadItem(listId: "", text: "Keep this note", order: 0)
        item.id = ""
        store.context.insert(habit)
        store.context.insert(list)
        store.context.insert(task)
        store.context.insert(item)

        XCTAssertTrue(DataIntegrityRepair.repair(store.context))
        XCTAssertFalse(task.id.isEmpty)
        XCTAssertEqual(task.intervalType, "1 Day")
        XCTAssertEqual(task.habitId, habit.id)
        XCTAssertFalse(item.id.isEmpty)
        XCTAssertEqual(item.listId, list.id)
        XCTAssertEqual(task.text, "Keep this thought")
        XCTAssertEqual(item.text, "Keep this note")
        XCTAssertNil(task.syncedAt)
    }

    func testRepairIsIdempotentForValidData() throws {
        let store = try TestStore()
        let task = TaskItem(text: "Stable", intervalType: "1 Week", order: -4)
        store.context.insert(task)
        let originalId = task.id
        let originalText = task.text

        XCTAssertFalse(DataIntegrityRepair.repair(store.context))
        XCTAssertEqual(task.id, originalId)
        XCTAssertEqual(task.text, originalText)
        XCTAssertEqual(task.order, -4, "Unusual order values are recoverable and must not cause content deletion")
    }

    func testUnknownRemoteIntervalFallsBackToVisibleDayBucket() {
        XCTAssertEqual(DataIntegrityRepair.safeInterval("broken"), "1 Day")
        XCTAssertEqual(DataIntegrityRepair.safeInterval(nil), "1 Day")
        XCTAssertEqual(DataIntegrityRepair.safeInterval("1 Month"), "1 Month")
    }

    func testRepairSoftDeletesOnlyIdenticalHabitDropBurstCopies() throws {
        let store = try TestStore()
        let first = store.addTask("Stretch", interval: "1 Hour", order: 0, habitId: "habit")
        let duplicate = store.addTask("Stretch", interval: "1 Hour", order: 1, habitId: "habit")
        let edited = store.addTask("Stretch gently", interval: "1 Hour", order: 2, habitId: "habit")
        let unrelated = store.addTask("Stretch", interval: "1 Hour", order: 3, habitId: "other")
        first.createdAt = TestTime.now
        duplicate.createdAt = TestTime.offset(1)
        edited.createdAt = TestTime.offset(2)
        try store.save()
        let unrelatedStamp = unrelated.updatedAt

        XCTAssertTrue(DataIntegrityRepair.repair(store.context))
        XCTAssertNil(first.deletedAt)
        XCTAssertNotNil(duplicate.deletedAt)
        XCTAssertEqual(duplicate.text, "Stretch")
        XCTAssertNil(edited.deletedAt)
        XCTAssertNil(unrelated.deletedAt)
        XCTAssertEqual(unrelated.updatedAt, unrelatedStamp)
        XCTAssertFalse(DataIntegrityRepair.repair(store.context))
    }
}
