import SwiftData
import XCTest

@MainActor
final class TaskDragMutationTests: XCTestCase {
    func testCancelledProposalDoesNotMutateOrPersistAnything() throws {
        let store = try TestStore()
        let dragged = store.addTask("Drag me", interval: "1 Day", order: 1, id: "dragged")
        let untouched = store.addTask("Stay", interval: "1 Hour", order: 0, id: "stay")
        try store.save()

        DragState.shared.draggedTask = dragged
        DragState.shared.targetIntervalType = "1 Hour"
        DragState.shared.targetIndex = 0
        DragState.shared.reset() // equivalent to mouse/finger release outside a drop target

        XCTAssertEqual(dragged.intervalType, "1 Day")
        XCTAssertEqual(dragged.order, 1)
        XCTAssertEqual(untouched.text, "Stay")
        XCTAssertFalse(store.context.hasChanges)
    }

    func testCommittedCrossIntervalDropPreservesRowsAndNormalizesBothLists() throws {
        let store = try TestStore()
        let sourceFirst = store.addTask("Source first", interval: "1 Day", order: 0, id: "source-first")
        let dragged = store.addTask("Drag me", interval: "1 Day", order: 1, id: "dragged")
        let targetFirst = store.addTask("Target first", interval: "1 Hour", order: 4, id: "target-first")
        let targetLast = store.addTask("Target last", interval: "1 Hour", order: 9, id: "target-last")
        let unrelated = store.addTask("Unrelated", interval: "1 Week", order: 7, id: "unrelated")
        try store.save()
        let unrelatedTimestamp = unrelated.updatedAt

        XCTAssertTrue(TaskDragMutation.commit(dragged, to: "1 Hour", index: 1, context: store.context, now: TestTime.now))
        try store.save()

        let tasks = try store.tasks()
        XCTAssertEqual(tasks.count, 5)
        XCTAssertEqual(tasks.filter { $0.intervalType == "1 Hour" }.sorted { $0.order < $1.order }.map(\.id),
                       [targetFirst.id, dragged.id, targetLast.id])
        XCTAssertEqual(sourceFirst.order, 0)
        XCTAssertEqual(unrelated.order, 7)
        XCTAssertEqual(unrelated.updatedAt, unrelatedTimestamp)
        XCTAssertEqual(dragged.text, "Drag me")
    }

    func testDropClampsFirstAndLastPositionsAndRejectsInvalidInterval() throws {
        let store = try TestStore()
        let a = store.addTask("A", interval: "1 Month", order: 0)
        let b = store.addTask("B", interval: "1 Month", order: 1)
        let c = store.addTask("C", interval: "1 Month", order: 2)

        XCTAssertTrue(TaskDragMutation.commit(c, to: "1 Month", index: -100, context: store.context, now: TestTime.now))
        XCTAssertEqual([a, b, c].sorted { $0.order < $1.order }.map(\.text), ["C", "A", "B"])
        XCTAssertTrue(TaskDragMutation.commit(c, to: "1 Month", index: 100, context: store.context, now: TestTime.offset(1)))
        XCTAssertEqual([a, b, c].sorted { $0.order < $1.order }.map(\.text), ["A", "B", "C"])
        XCTAssertFalse(TaskDragMutation.commit(c, to: "Never", index: 0, context: store.context))
        XCTAssertEqual(c.intervalType, "1 Month")
    }
}
