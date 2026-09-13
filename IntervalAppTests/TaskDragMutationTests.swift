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

    func testReorderingWorksInEveryInterval() throws {
        for interval in ["1 Hour", "1 Day", "1 Week", "1 Month", "1 Year"] {
            let store = try TestStore()
            let first = store.addTask("First", interval: interval, order: 0)
            let second = store.addTask("Second", interval: interval, order: 1)
            let third = store.addTask("Third", interval: interval, order: 2)

            XCTAssertTrue(TaskDragMutation.commit(third, to: interval, index: 0, context: store.context, now: TestTime.now))
            XCTAssertEqual([first, second, third].sorted { $0.order < $1.order }.map(\.text), ["Third", "First", "Second"])
        }
    }

    func testEveryCrossIntervalPairPreservesTaskIdentityAndText() throws {
        let intervals = ["1 Hour", "1 Day", "1 Week", "1 Month", "1 Year"]
        for source in intervals {
            for destination in intervals where destination != source {
                let store = try TestStore()
                let task = store.addTask("Durable \(source)", interval: source, order: 0, id: "stable-id")
                store.addTask("Destination", interval: destination, order: 0)

                XCTAssertTrue(TaskDragMutation.commit(task, to: destination, index: 1, context: store.context, now: TestTime.now))
                XCTAssertEqual(task.id, "stable-id")
                XCTAssertEqual(task.text, "Durable \(source)")
                XCTAssertEqual(task.intervalType, destination)
                XCTAssertEqual(try store.tasks().count, 2)
            }
        }
    }

    func testRepeatedIdenticalDropIsIdempotent() throws {
        let store = try TestStore()
        let first = store.addTask("First", interval: "1 Day", order: 0)
        let second = store.addTask("Second", interval: "1 Day", order: 1)

        XCTAssertTrue(TaskDragMutation.commit(second, to: "1 Day", index: 0, context: store.context, now: TestTime.now))
        let timestamp = second.updatedAt
        XCTAssertFalse(TaskDragMutation.commit(second, to: "1 Day", index: 0, context: store.context, now: TestTime.offset(10)))
        XCTAssertEqual(second.updatedAt, timestamp)
        XCTAssertEqual([first, second].sorted { $0.order < $1.order }.map(\.text), ["Second", "First"])
    }

    func testCurrentStoreStateWinsWhenListChangesBetweenHoverAndDrop() throws {
        let store = try TestStore()
        let dragged = store.addTask("Dragged", interval: "1 Day", order: 0)
        store.addTask("Existing", interval: "1 Hour", order: 0)

        DragState.shared.draggedTask = dragged
        DragState.shared.targetIntervalType = "1 Hour"
        DragState.shared.targetIndex = 1
        let arrivedDuringDrag = store.addTask("From sync", interval: "1 Hour", order: 1)

        XCTAssertTrue(TaskDragMutation.commit(dragged, to: "1 Hour", index: DragState.shared.targetIndex!, context: store.context, now: TestTime.now))
        DragState.shared.reset()
        XCTAssertEqual(try store.tasks().count, 3)
        XCTAssertEqual(dragged.text, "Dragged")
        XCTAssertEqual(arrivedDuringDrag.text, "From sync")
        XCTAssertEqual(try store.tasks().filter { $0.intervalType == "1 Hour" }.count, 3)
    }

    func testStartingAnotherDragCannotMutateEitherTask() throws {
        let store = try TestStore()
        let first = store.addTask("First", interval: "1 Day", order: 0)
        let second = store.addTask("Second", interval: "1 Week", order: 0)
        try store.save()

        DragState.shared.draggedTask = first
        DragState.shared.targetIntervalType = "1 Hour"
        DragState.shared.targetIndex = 0
        DragState.shared.draggedTask = second
        DragState.shared.reset()

        XCTAssertEqual(first.intervalType, "1 Day")
        XCTAssertEqual(second.intervalType, "1 Week")
        XCTAssertFalse(store.context.hasChanges)
    }

    func testMouseReleasePreservesTaskUntilDropHandoffThenClearsIt() async throws {
        let store = try TestStore()
        let task = store.addTask("Keep me", interval: "1 Day", order: 0)
        DragState.shared.begin(task, interval: "1 Day", fontSize: 20)
        DragState.shared.targetIndex = 0

        DragState.shared.resetAfterDropWindow()
        XCTAssertEqual(DragState.shared.draggedTask?.id, task.id,
                       "SwiftUI must still see the task when performDrop follows mouse-up")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(DragState.shared.draggedTask,
                     "A cancelled drag must restore the row after the drop handoff")
        XCTAssertNil(DragState.shared.targetIndex)
    }

    func testOldDragCleanupCannotEraseNewDrag() async throws {
        let store = try TestStore()
        let first = store.addTask("First", interval: "1 Day")
        let second = store.addTask("Second", interval: "1 Week")
        DragState.shared.begin(first, interval: "1 Day", fontSize: 20)
        DragState.shared.resetAfterDropWindow()
        DragState.shared.begin(second, interval: "1 Week", fontSize: 20)

        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(DragState.shared.draggedTask?.id, second.id)
        DragState.shared.reset()
    }

    func testVisibleInsertionSlotCommitsTaskAtAdvertisedIndex() throws {
        let store = try TestStore()
        let dragged = store.addTask("Dragged", interval: "1 Day", order: 0)
        store.addTask("First", interval: "1 Hour", order: 0)
        store.addTask("Last", interval: "1 Hour", order: 1)
        DragState.shared.begin(dragged, interval: "1 Day", fontSize: 20)
        DragState.shared.targetIndex = 1

        XCTAssertTrue(TaskListInsertionDropDelegate.commitDrop(to: "1 Hour", at: 1, context: store.context))
        XCTAssertEqual(try store.tasks().filter { $0.intervalType == "1 Hour" }
            .sorted { $0.order < $1.order }.map(\.text), ["First", "Dragged", "Last"])
        XCTAssertNil(DragState.shared.draggedTask)
    }
}
