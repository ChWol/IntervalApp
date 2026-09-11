import Foundation
import SwiftData
import XCTest

@MainActor
final class PersistenceRecoveryTests: XCTestCase {
    private func makeContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema([
            TaskItem.self,
            HabitItem.self,
            ScratchpadList.self,
            ScratchpadItem.self
        ])
        let configuration = ModelConfiguration("Recovery", schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func temporaryStoreURL() throws -> (directory: URL, store: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IntervalPersistenceTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("Interval.store"))
    }

    func testEveryRecordTypeSurvivesStoreReopenWithSafetyFieldsIntact() throws {
        let location = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let now = TestTime.now

        do {
            let container = try makeContainer(at: location.store)
            let context = ModelContext(container)

            let habit = HabitItem(text: "Meditate", frequency: "Daily", order: 3)
            habit.id = "habit"
            habit.streak = 8
            habit.lastCompletedDate = now
            habit.updatedAt = now
            context.insert(habit)

            let task = TaskItem(text: "Important thought", intervalType: "1 Month", order: 7, habitId: habit.id)
            task.id = "task"
            task.completed = true
            task.completedAt = now
            task.deletedAt = now.addingTimeInterval(60)
            task.updatedAt = now.addingTimeInterval(60)
            context.insert(task)

            let list = ScratchpadList(title: "Ideas", order: 2, ownerId: "owner", ownerEmail: "owner@example.com")
            list.id = "list"
            list.updatedAt = now
            context.insert(list)

            let item = ScratchpadItem(listId: list.id, text: "A durable note", order: 4)
            item.id = "item"
            item.completed = true
            item.completedAt = now
            item.deletedAt = now.addingTimeInterval(120)
            item.updatedAt = now.addingTimeInterval(120)
            context.insert(item)

            XCTAssertTrue(PersistenceSafety.save(context, operation: "Writing recovery fixture"))
        }

        do {
            let reopened = try makeContainer(at: location.store)
            let context = ModelContext(reopened)

            let task = try XCTUnwrap(context.fetch(FetchDescriptor<TaskItem>()).first)
            XCTAssertEqual(task.id, "task")
            XCTAssertEqual(task.text, "Important thought")
            XCTAssertEqual(task.intervalType, "1 Month")
            XCTAssertEqual(task.order, 7)
            XCTAssertEqual(task.habitId, "habit")
            XCTAssertTrue(task.completed)
            XCTAssertEqual(task.completedAt, now)
            XCTAssertEqual(task.deletedAt, now.addingTimeInterval(60))

            let habit = try XCTUnwrap(context.fetch(FetchDescriptor<HabitItem>()).first)
            XCTAssertEqual(habit.id, "habit")
            XCTAssertEqual(habit.text, "Meditate")
            XCTAssertEqual(habit.streak, 8)
            XCTAssertEqual(habit.lastCompletedDate, now)

            let list = try XCTUnwrap(context.fetch(FetchDescriptor<ScratchpadList>()).first)
            XCTAssertEqual(list.id, "list")
            XCTAssertEqual(list.title, "Ideas")
            XCTAssertEqual(list.ownerId, "owner")
            XCTAssertEqual(list.ownerEmail, "owner@example.com")

            let item = try XCTUnwrap(context.fetch(FetchDescriptor<ScratchpadItem>()).first)
            XCTAssertEqual(item.id, "item")
            XCTAssertEqual(item.listId, "list")
            XCTAssertEqual(item.text, "A durable note")
            XCTAssertTrue(item.completed)
            XCTAssertEqual(item.completedAt, now)
            XCTAssertEqual(item.deletedAt, now.addingTimeInterval(120))
        }
    }

    func testSoftDeleteAndRestoreEachSurviveAStoreReopen() throws {
        let location = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: location.directory) }

        do {
            let container = try makeContainer(at: location.store)
            let context = ModelContext(container)
            let task = TaskItem(text: "Recover me", intervalType: "1 Week", order: 5)
            task.id = "recoverable"
            context.insert(task)
            TaskHousekeeping.moveToBin(task, in: context, now: TestTime.now)
        }

        do {
            let container = try makeContainer(at: location.store)
            let context = ModelContext(container)
            let task = try XCTUnwrap(context.fetch(FetchDescriptor<TaskItem>()).first)
            XCTAssertEqual(task.text, "Recover me")
            XCTAssertEqual(task.deletedAt, TestTime.now)
            TaskHousekeeping.restore(task, in: context, now: TestTime.offset(60))
        }

        do {
            let container = try makeContainer(at: location.store)
            let context = ModelContext(container)
            let task = try XCTUnwrap(context.fetch(FetchDescriptor<TaskItem>()).first)
            XCTAssertEqual(task.text, "Recover me")
            XCTAssertEqual(task.intervalType, "1 Week")
            XCTAssertEqual(task.order, 5)
            XCTAssertNil(task.deletedAt)
            XCTAssertFalse(task.completed)
        }
    }
}
