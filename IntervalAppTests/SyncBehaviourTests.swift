import SwiftData
import XCTest

/// End-to-end sync behaviour: the app's real push filtering, payloads, DTO decoding and merge,
/// driven against an in-memory store and a fake table set.
@MainActor
final class SyncBehaviourTests: XCTestCase {
    private var server: FakeSupabase!
    private var deviceA: SyncDevice!
    private var deviceB: SyncDevice!
    private let t0 = TestTime.now
    
    override func setUp() async throws {
        try await super.setUp()
        server = FakeSupabase()
        deviceA = try SyncDevice()
        deviceB = try SyncDevice()
    }
    
    override func tearDown() async throws {
        server = nil
        deviceA = nil
        deviceB = nil
        try await super.tearDown()
    }
    
    // MARK: - Basics
    
    func testNewTaskReachesTheServerAndTheOtherDevice() throws {
        let task = deviceA.createTask("Write the report", interval: "1 Day", order: 3, at: t0)
        deviceA.push(to: server, at: t0)
        
        XCTAssertEqual(server.text(table: SyncTable.tasks, id: task.id), "Write the report")
        
        try deviceB.pull(from: server)
        let copy = try deviceB.task(id: task.id)
        XCTAssertEqual(copy?.text, "Write the report")
        XCTAssertEqual(copy?.intervalType, "1 Day")
        XCTAssertEqual(copy?.order, 3)
        XCTAssertFalse(copy?.completed ?? true)
    }
    
    func testAPulledRowIsNotImmediatelyPushedBack() throws {
        deviceA.createTask("Stable", at: t0)
        deviceA.push(to: server, at: t0)
        try deviceB.pull(from: server)
        
        XCTAssertTrue(deviceB.hasNothingToPush,
                      "A row that just arrived from the server has no unpublished changes")
    }
    
    func testPushingTwiceUploadsNothingTheSecondTime() throws {
        deviceA.createTask("Once", at: t0)
        deviceA.push(to: server, at: t0)
        let afterFirst = server.upsertCount
        
        deviceA.push(to: server, at: t0)
        XCTAssertEqual(server.upsertCount, afterFirst,
                       "Polling must not re-upload rows that have not changed")
    }

    func testPostponedHabitRoundTripsThroughPayloadAndMerge() throws {
        let habit = deviceA.store.addHabit("Read", postponedDate: t0, id: "h-postponed")
        habit.updatedAt = t0
        let payload = deviceA.manager.testingHabitPayload(habit)
        XCTAssertNotNil(payload["postponed_date"] as? String)
        deviceA.manager.testingMarkSynced(habit)

        let remote = SupabaseHabitDTO(id: habit.id, text: habit.text, frequency: habit.frequency,
                                      streak: habit.streak, last_completed_date: nil,
                                      postponed_date: SyncTimestamp.format(t0), completion_history: "[]",
                                      order: habit.order, deleted_at: nil, user_id: deviceA.manager.testingUserId,
                                      updated_at: SyncTimestamp.format(t0.addingTimeInterval(60)))
        _ = deviceA.manager.testingMerge(habits: [remote])
        XCTAssertEqual(try deviceA.habit(id: habit.id)?.postponedDate?.timeIntervalSince1970 ?? 0,
                       t0.timeIntervalSince1970, accuracy: 0.01)
    }
    
    // MARK: - The data-loss regression
    
    /// The bug that motivated per-row tracking: an idle device used to restamp and re-upload
    /// every row, so its stale copy overwrote a fresh edit made elsewhere. Both devices then
    /// showed the stale text and the real edit was gone for good.
    func testIdleDeviceCannotOverwriteAnotherDevicesEdit() throws {
        let task = deviceA.createTask("Original", at: t0)
        deviceA.push(to: server, at: t0)
        try deviceB.pull(from: server)
        
        // B makes the edit and publishes it.
        guard let onB = try deviceB.task(id: task.id) else { return XCTFail("Missing row on B") }
        deviceB.edit(onB, text: "Edited on B", at: t0.addingTimeInterval(60))
        deviceB.push(to: server, at: t0.addingTimeInterval(60))
        
        // A has not been touched since the first push, so its poll must upload nothing.
        XCTAssertTrue(deviceA.hasNothingToPush)
        deviceA.push(to: server, at: t0.addingTimeInterval(70))
        XCTAssertEqual(server.text(table: SyncTable.tasks, id: task.id), "Edited on B")
        
        try deviceA.pull(from: server)
        XCTAssertEqual(try deviceA.task(id: task.id)?.text, "Edited on B")
    }

    func testForegroundingStaleDeviceCannotUndoNewerCompletion() throws {
        let task = deviceA.createTask("Pay invoice", at: t0)
        deviceA.push(to: server, at: t0)
        try deviceB.pull(from: server)

        // The phone retains an older unpublished edit while the Mac completes the task.
        guard let stalePhoneCopy = try deviceB.task(id: task.id) else {
            return XCTFail("Missing phone copy")
        }
        deviceB.edit(stalePhoneCopy, text: "Pay invoice today", at: t0.addingTimeInterval(10))
        task.completed = true
        task.completedAt = t0.addingTimeInterval(60)
        task.updatedAt = t0.addingTimeInterval(60)
        deviceA.push(to: server, at: t0.addingTimeInterval(60))

        // A foreground cycle must reconcile before uploading the phone cache.
        try deviceB.sync(with: server, at: t0.addingTimeInterval(70))

        let resolvedPhoneCopy = try deviceB.task(id: task.id)
        XCTAssertTrue(resolvedPhoneCopy?.completed ?? false)
        XCTAssertEqual(resolvedPhoneCopy?.completedAt, t0.addingTimeInterval(60))
        XCTAssertEqual(resolvedPhoneCopy?.text, "Pay invoice")
        XCTAssertEqual(server.value(table: SyncTable.tasks, id: task.id, key: "completed") as? Bool, true)
        XCTAssertTrue(deviceB.hasNothingToPush)
    }
    
    /// The other half of that bug: a pull arriving mid-typing used to revert the text.
    func testRemoteSnapshotDoesNotRevertAnUnpublishedEdit() throws {
        let task = deviceA.createTask("Original", at: t0)
        deviceA.push(to: server, at: t0)
        
        // Still typing, nothing pushed yet, and a poll lands.
        deviceA.edit(task, text: "Original, extended", at: t0.addingTimeInterval(0.2))
        let needsFollowup = try deviceA.pull(from: server)
        
        XCTAssertEqual(task.text, "Original, extended")
        XCTAssertTrue(needsFollowup, "The unpublished edit has to be scheduled for pushing")
        XCTAssertFalse(deviceA.hasNothingToPush)
    }
    
    func testLaterEditWinsRegardlessOfPushOrder() throws {
        let task = deviceA.createTask("Original", at: t0)
        deviceA.push(to: server, at: t0)
        try deviceB.pull(from: server)
        
        guard let onA = try deviceA.task(id: task.id), let onB = try deviceB.task(id: task.id) else {
            return XCTFail("Missing row")
        }
        // A edits later in real time, but publishes first.
        deviceA.edit(onA, text: "A wins", at: t0.addingTimeInterval(120))
        deviceB.edit(onB, text: "B loses", at: t0.addingTimeInterval(60))
        deviceA.push(to: server, at: t0.addingTimeInterval(130))
        deviceB.push(to: server, at: t0.addingTimeInterval(140))
        
        // B's older row reached the server last. A still holds the newer version, so its next
        // cycles have to put it back and B has to pick it up.
        try deviceB.sync(with: server, at: t0.addingTimeInterval(150))
        try deviceA.sync(with: server, at: t0.addingTimeInterval(160))
        try deviceB.sync(with: server, at: t0.addingTimeInterval(170))
        
        XCTAssertEqual(server.text(table: SyncTable.tasks, id: task.id), "A wins")
        XCTAssertEqual(try deviceA.task(id: task.id)?.text, "A wins")
        XCTAssertEqual(try deviceB.task(id: task.id)?.text, "A wins")
        XCTAssertTrue(deviceA.hasNothingToPush)
        XCTAssertTrue(deviceB.hasNothingToPush)
    }
    
    func testDevicesConvergeAfterEditingDifferentRows() throws {
        deviceA.createTask("From A", order: 0, at: t0)
        deviceA.push(to: server, at: t0)
        try deviceB.sync(with: server, at: t0)
        
        deviceB.createTask("From B", order: 1, at: t0.addingTimeInterval(30))
        try deviceB.sync(with: server, at: t0.addingTimeInterval(30))
        try deviceA.sync(with: server, at: t0.addingTimeInterval(40))
        
        XCTAssertEqual(try deviceA.taskTexts(), ["From A", "From B"])
        XCTAssertEqual(try deviceB.taskTexts(), ["From A", "From B"])
        XCTAssertTrue(deviceA.hasNothingToPush)
        XCTAssertTrue(deviceB.hasNothingToPush)
    }

    func testConflictingReordersConvergeToTheLatestCompleteOrdering() throws {
        for (index, id) in ["a", "b", "c"].enumerated() {
            deviceA.createTask(id.uppercased(), order: index, at: t0, id: id)
        }
        try deviceA.sync(with: server, at: t0)
        try deviceB.sync(with: server, at: t0)

        for task in try deviceA.tasks() {
            task.order = ["c": 0, "b": 1, "a": 2][task.id]!
            task.updatedAt = t0.addingTimeInterval(60)
        }
        for task in try deviceB.tasks() {
            task.order = ["b": 0, "a": 1, "c": 2][task.id]!
            task.updatedAt = t0.addingTimeInterval(120)
        }

        deviceA.push(to: server, at: t0.addingTimeInterval(70))
        deviceB.push(to: server, at: t0.addingTimeInterval(130))
        try deviceA.sync(with: server, at: t0.addingTimeInterval(140))
        try deviceB.sync(with: server, at: t0.addingTimeInterval(150))

        let orderA = try deviceA.tasks().sorted { $0.order < $1.order }.map(\.id)
        let orderB = try deviceB.tasks().sorted { $0.order < $1.order }.map(\.id)
        XCTAssertEqual(orderA, ["b", "a", "c"])
        XCTAssertEqual(orderB, orderA)
        XCTAssertEqual(server.ids(table: SyncTable.tasks), ["a", "b", "c"])
    }

    func testOfflineLifecycleConvergesAfterReconnectionWithoutRecordLoss() throws {
        let created = deviceA.createTask("Created offline", order: 0, at: t0, id: "created")
        let edited = deviceA.createTask("Before edit", order: 1, at: t0, id: "edited")
        let completed = deviceA.createTask("Completed offline", order: 2, at: t0, id: "completed")
        let restored = deviceA.createTask("Restored offline", order: 3, at: t0, id: "restored")
        let deleted = deviceA.createTask("Deleted offline", order: 4, at: t0, id: "deleted")

        deviceA.edit(edited, text: "Edited offline", at: t0.addingTimeInterval(10))
        completed.completed = true
        completed.completedAt = t0.addingTimeInterval(20)
        completed.updatedAt = t0.addingTimeInterval(20)
        restored.deletedAt = t0.addingTimeInterval(30)
        restored.updatedAt = t0.addingTimeInterval(30)
        restored.deletedAt = nil
        restored.updatedAt = t0.addingTimeInterval(40)
        created.order = 4
        created.updatedAt = t0.addingTimeInterval(50)
        edited.order = 0
        edited.updatedAt = t0.addingTimeInterval(50)
        deviceA.hardDelete(deleted)

        XCTAssertEqual(try deviceA.tasks().count, 4)
        XCTAssertFalse(deviceA.hasNothingToPush)

        try deviceA.sync(with: server, at: t0.addingTimeInterval(60))
        try deviceB.sync(with: server, at: t0.addingTimeInterval(70))

        XCTAssertEqual(try deviceB.taskTexts(), ["Completed offline", "Created offline", "Edited offline", "Restored offline"])
        XCTAssertEqual(try deviceB.task(id: "edited")?.order, 0)
        XCTAssertEqual(try deviceB.task(id: "created")?.order, 4)
        XCTAssertTrue(try deviceB.task(id: "completed")?.completed ?? false)
        XCTAssertNil(try deviceB.task(id: "restored")?.deletedAt)
        XCTAssertNil(try deviceB.task(id: "deleted"))
        XCTAssertTrue(deviceA.hasNothingToPush)
        XCTAssertTrue(deviceB.hasNothingToPush)
    }
    
    // MARK: - Deletes
    
    func testPermanentDeletePropagatesToTheOtherDevice() throws {
        let task = deviceA.createTask("Temporary", at: t0)
        deviceA.push(to: server, at: t0)
        try deviceB.pull(from: server)
        
        deviceA.hardDelete(task)
        deviceA.push(to: server, at: t0.addingTimeInterval(10))
        XCTAssertTrue(server.ids(table: SyncTable.tasks).isEmpty)
        
        // Absent once: kept, because one short snapshot is not proof of a delete.
        try deviceB.pull(from: server)
        XCTAssertEqual(try deviceB.tasks().count, 1)
        
        // Absent twice: really gone.
        try deviceB.pull(from: server)
        XCTAssertTrue(try deviceB.tasks().isEmpty)
    }
    
    func testTombstoneStopsAStaleSnapshotFromResurrectingARow() throws {
        let task = deviceA.createTask("Delete me", at: t0)
        deviceA.push(to: server, at: t0)
        
        // A snapshot taken before the delete is still in flight.
        let staleSnapshot = try server.taskSnapshot()
        deviceA.hardDelete(task)
        deviceA.push(to: server, at: t0.addingTimeInterval(5))
        
        deviceA.manager.testingMerge(tasks: staleSnapshot)
        
        XCTAssertTrue(try deviceA.tasks().isEmpty, "The row was destroyed; it must not come back")
    }
    
    func testUnpublishedLocalRowIsNeverPrunedAsMissing() throws {
        deviceA.createTask("Never pushed", at: t0)
        
        try deviceA.pull(from: server)
        try deviceA.pull(from: server)
        try deviceA.pull(from: server)
        
        XCTAssertEqual(try deviceA.taskTexts(), ["Never pushed"],
                       "A row the server has never seen cannot be missing from it")
    }
    
    func testRecycleBinIsSharedRatherThanWiped() throws {
        let task = deviceA.createTask("Binned", at: t0)
        deviceA.push(to: server, at: t0)
        deviceA.softDelete(task, at: t0.addingTimeInterval(10))
        deviceA.push(to: server, at: t0.addingTimeInterval(10))
        
        try deviceB.pull(from: server)
        
        let copy = try deviceB.task(id: task.id)
        XCTAssertNotNil(copy?.deletedAt, "A soft delete belongs in the other device's bin")
        XCTAssertEqual(server.ids(table: SyncTable.tasks), [task.id],
                       "A device that has never seen the row must not delete it from the server")
    }
    
    /// A fresh install pulling a bin full of soft-deleted rows must keep them.
    func testFreshInstallKeepsSoftDeletedRowsItHasNeverSeen() throws {
        let task = deviceA.createTask("Binned elsewhere", at: t0)
        deviceA.softDelete(task, at: t0)
        deviceA.push(to: server, at: t0)
        
        try deviceB.pull(from: server)
        
        XCTAssertEqual(try deviceB.tasks().count, 1)
        XCTAssertNotNil(try deviceB.task(id: task.id)?.deletedAt)
    }
    
    // MARK: - Hostile snapshots
    
    func testAnotherAccountsRowsAreIgnored() throws {
        server.injectRaw(table: SyncTable.tasks, id: "someone-else", row: [
            "id": "someone-else",
            "text": "Not mine",
            "completed": false,
            "interval_type": "1 Day",
            "order": 0,
            "user_id": "another-user",
            "updated_at": SyncTimestamp.format(t0)
        ])
        
        try deviceA.pull(from: server)
        XCTAssertTrue(try deviceA.tasks().isEmpty)
    }
    
    func testBlankRemoteRowIsNotImportedAndIsCleanedUp() throws {
        server.injectRaw(table: SyncTable.tasks, id: "blank", row: [
            "id": "blank",
            "text": "   ",
            "completed": false,
            "interval_type": "1 Day",
            "order": 0,
            "user_id": deviceA.manager.testingUserId as Any,
            "updated_at": SyncTimestamp.format(t0)
        ])
        
        try deviceA.pull(from: server)
        
        XCTAssertTrue(try deviceA.tasks().isEmpty)
        XCTAssertTrue(deviceA.manager.testingLedger.contains(table: SyncTable.tasks, id: "blank"),
                      "An empty row is not data and should be cleared from the server")
    }
    
    func testRowWithNothingButAnIdDoesNotBreakTheSnapshot() throws {
        deviceA.createTask("Real row", at: t0)
        deviceA.push(to: server, at: t0)
        server.injectRaw(table: SyncTable.tasks, id: "sparse", row: ["id": "sparse"])
        
        try deviceB.pull(from: server)
        
        XCTAssertEqual(try deviceB.taskTexts(), ["Real row"],
                       "One unusable row must not cost us the rest of the table")
    }
    
    func testUnreadableTimestampCausesRepublishRatherThanLoss() throws {
        let task = deviceA.createTask("Keep me", at: t0)
        deviceA.push(to: server, at: t0)
        XCTAssertTrue(deviceA.hasNothingToPush)
        
        server.injectRaw(table: SyncTable.tasks, id: task.id, row: [
            "id": task.id,
            "text": "Keep me",
            "completed": false,
            "interval_type": "1 Day",
            "order": 0,
            "user_id": deviceA.manager.testingUserId as Any,
            "updated_at": "who knows"
        ])
        
        let needsFollowup = try deviceA.pull(from: server)
        
        XCTAssertTrue(needsFollowup)
        XCTAssertFalse(deviceA.hasNothingToPush, "The row must be republished with a readable timestamp")
        XCTAssertEqual(try deviceA.task(id: task.id)?.text, "Keep me")
    }
    
    func testDuplicateLocalIdsCollapseToTheNewestRow() throws {
        _ = deviceA.createTask("Older copy", at: t0, id: "duplicate")
        _ = deviceA.createTask("Newer copy", at: t0.addingTimeInterval(60), id: "duplicate")
        
        let pushable = deviceA.manager.testingPushableTasks()
        
        XCTAssertEqual(pushable.count, 1)
        XCTAssertEqual(pushable.first?.text, "Newer copy")
        XCTAssertEqual(try deviceA.tasks().count, 1)
    }

    func testDuplicateServerRowsConvergeToNewestVersionRegardlessOfOrder() throws {
        func row(_ text: String, at date: Date) -> SupabaseTaskDTO {
            SupabaseTaskDTO(id: "duplicate", text: text, completed: false,
                            created_at: SyncTimestamp.format(t0), interval_type: "1 Day", order: 0,
                            deleted_at: nil, completed_at: nil, habit_id: nil,
                            user_id: deviceA.manager.testingUserId,
                            updated_at: SyncTimestamp.format(date))
        }
        let older = row("Older server copy", at: t0)
        let newer = row("Newest server copy", at: t0.addingTimeInterval(60))

        deviceA.manager.testingMerge(tasks: [newer, older])
        XCTAssertEqual(try deviceA.task(id: "duplicate")?.text, "Newest server copy")

        let otherDevice = try SyncDevice()
        otherDevice.manager.testingMerge(tasks: [older, newer])
        XCTAssertEqual(try otherDevice.task(id: "duplicate")?.text, "Newest server copy")
        XCTAssertEqual(try otherDevice.tasks().count, 1)
    }

    func testSaveFailureDuringRemoteMergeLeavesChangesPendingForRetry() throws {
        let row = SupabaseTaskDTO(
            id: "remote", text: "Remote data", completed: false,
            created_at: SyncTimestamp.format(t0), interval_type: "1 Day", order: 0,
            deleted_at: nil, completed_at: nil, habit_id: nil,
            user_id: deviceA.manager.testingUserId, updated_at: SyncTimestamp.format(t0)
        )
        deviceA.manager.testingFailPersistenceSaves()

        XCTAssertFalse(deviceA.manager.testingMerge(tasks: [row]))
        XCTAssertEqual(try deviceA.task(id: "remote")?.text, "Remote data")
        XCTAssertTrue(deviceA.store.context.hasChanges)
        XCTAssertNotNil(deviceA.manager.lastError)
    }
    
    func testBlankLocalRowIsHeldBackFromTheServer() throws {
        deviceA.createTask("", at: t0)
        deviceA.push(to: server, at: t0)
        
        XCTAssertTrue(server.ids(table: SyncTable.tasks).isEmpty,
                      "An empty row is a placeholder for typing, not data")
        XCTAssertEqual(try deviceA.tasks().count, 1, "…but it must stay on screen")
    }
    
    // MARK: - Clock skew
    
    func testDeviceWithABadClockDoesNotWinEveryConflict() throws {
        // B's clock is an hour ahead of the server; the offset corrects for it.
        let skewed = try SyncDevice(clockOffset: -3600)
        
        let task = deviceA.createTask("Original", at: t0)
        deviceA.push(to: server, at: t0)
        try skewed.pull(from: server)
        
        // A real, later edit on A.
        guard let onA = try deviceA.task(id: task.id) else { return XCTFail("Missing row") }
        deviceA.edit(onA, text: "Edited later on A", at: t0.addingTimeInterval(60))
        deviceA.push(to: server, at: t0.addingTimeInterval(60))
        
        try skewed.pull(from: server)
        
        XCTAssertEqual(try skewed.task(id: task.id)?.text, "Edited later on A",
                       "An hour-ahead clock must not make the older local row look newer")
    }
    
    // MARK: - Habit links
    
    func testHabitLinkTravelsWithTheTask() throws {
        let habit = deviceA.createHabit("Meditate", at: t0)
        let task = deviceA.createTask("Meditate", interval: HabitTaskLink.hourInterval, at: t0)
        task.habitId = habit.id
        deviceA.push(to: server, at: t0)
        
        try deviceB.pull(from: server)
        
        XCTAssertEqual(try deviceB.task(id: task.id)?.habitId, habit.id)
    }
    
    /// A database created before the habit link column reports no habit_id at all. The link is
    /// device-local in that case and must not be erased by a pull.
    func testDatabaseWithoutTheHabitColumnKeepsLocalLinks() throws {
        let habit = deviceA.createHabit("Stretch", at: t0)
        let task = deviceA.createTask("Stretch", interval: HabitTaskLink.hourInterval, at: t0)
        task.habitId = habit.id
        deviceA.push(to: server, at: t0)
        
        server.removeColumn(table: SyncTable.tasks, key: "habit_id")
        // The row is also touched elsewhere, so the remote copy is the newer one.
        server.injectRaw(table: SyncTable.tasks, id: task.id, row: [
            "id": task.id,
            "text": "Stretch",
            "completed": false,
            "interval_type": HabitTaskLink.hourInterval,
            "order": 0,
            "user_id": deviceA.manager.testingUserId as Any,
            "updated_at": SyncTimestamp.format(t0.addingTimeInterval(60))
        ])
        
        try deviceA.pull(from: server)
        
        XCTAssertEqual(try deviceA.task(id: task.id)?.habitId, habit.id)
    }

    func testGeneratedHourHabitTaskRecoversLinkAfterLoginWithoutHabitColumn() throws {
        let habit = deviceA.createHabit("Stretch", at: t0, id: "habit-stretch")
        let generated = try XCTUnwrap(HabitTaskLink.makeHourTasks(
            for: [habit], existingHourTasks: [], startingOrder: 0, now: t0
        ).first)
        deviceA.store.context.insert(generated)
        deviceA.push(to: server, at: t0)
        server.removeColumn(table: SyncTable.tasks, key: "habit_id")

        try deviceB.pull(from: server)
        let restored = try XCTUnwrap(deviceB.task(id: generated.id))
        XCTAssertEqual(restored.habitId, habit.id)
        let repeated = HabitTaskLink.makeHourTasks(for: [habit], existingHourTasks: [restored], startingOrder: 1, now: t0)
        XCTAssertTrue(repeated.isEmpty)
    }
    
    func testMissingHabitColumnIsRecognisedFromTheServerError() {
        XCTAssertTrue(SupabaseSyncManager.mentionsMissingHabitIdColumn(
            #"{"code":"PGRST204","message":"Could not find the 'habit_id' column of 'tasks' in the schema cache"}"#
        ))
        XCTAssertTrue(SupabaseSyncManager.mentionsMissingHabitIdColumn(
            #"{"code":"42703","message":"column \"habit_id\" of relation \"tasks\" does not exist"}"#
        ))
        XCTAssertFalse(SupabaseSyncManager.mentionsMissingHabitIdColumn(
            #"{"code":"23505","message":"duplicate key value violates unique constraint"}"#
        ))
        XCTAssertFalse(SupabaseSyncManager.mentionsMissingHabitIdColumn(""))
    }

    func testMissingHabitHistoryColumnIsRecognisedFromTheServerError() {
        XCTAssertTrue(SupabaseSyncManager.mentionsMissingCompletionHistoryColumn(
            #"{"code":"PGRST204","message":"Could not find the 'completion_history' column of 'habits' in the schema cache"}"#
        ))
        XCTAssertTrue(SupabaseSyncManager.mentionsMissingCompletionHistoryColumn(
            #"{"code":"42703","message":"column \"completion_history\" of relation \"habits\" does not exist"}"#
        ))
        XCTAssertFalse(SupabaseSyncManager.mentionsMissingCompletionHistoryColumn(
            #"{"code":"23505","message":"duplicate key value violates unique constraint"}"#
        ))
    }
    
    // MARK: - Habits table
    
    func testHabitStreakAndCompletionSync() throws {
        let habit = deviceA.createHabit("Read", at: t0)
        habit.streak = 4
        habit.lastCompletedDate = t0
        deviceA.push(to: server, at: t0)
        
        try deviceB.pull(from: server)
        
        let copy = try deviceB.habit(id: habit.id)
        XCTAssertEqual(copy?.streak, 4)
        XCTAssertEqual(copy?.text, "Read")
        XCTAssertEqual(copy?.lastCompletedDate?.timeIntervalSince1970 ?? 0,
                       t0.timeIntervalSince1970,
                       accuracy: 0.01,
                       "The completion date decides the streak, so it has to survive the round trip")
    }

    func testHabitCompletionHistoryTravelsWithTheHabit() throws {
        let habit = deviceA.createHabit("Read", at: t0)
        habit.setCompletionDates([t0.addingTimeInterval(-86_400), t0])
        deviceA.push(to: server, at: t0)

        try deviceB.pull(from: server)

        let copy = try deviceB.habit(id: habit.id)
        XCTAssertEqual(copy?.completionDates.count, 2)
    }
    
    // MARK: - Payload shape
    
    /// PostgREST rejects a batch whose objects do not share the same keys (PGRST102), which
    /// would silently stop the whole table from syncing.
    func testEveryTaskPayloadCarriesTheSameKeys() throws {
        let plain = deviceA.createTask("Plain", at: t0)
        let rich = deviceA.createTask("Rich", at: t0)
        rich.completed = true
        rich.completedAt = t0
        rich.deletedAt = t0
        rich.habitId = "some-habit"
        
        let keys = Set(deviceA.manager.testingTaskPayload(plain).keys)
        XCTAssertEqual(keys, Set(deviceA.manager.testingTaskPayload(rich).keys))
        XCTAssertTrue(keys.isSuperset(of: ["id", "text", "completed", "created_at", "interval_type",
                                           "interval_entered_at", "order", "deleted_at", "completed_at", "user_id", "updated_at"]))
    }

    func testIntervalEntryTimestampRoundTripsThroughTaskSync() throws {
        let enteredAt = t0.addingTimeInterval(30)
        let local = deviceA.createTask("Moved task", at: t0)
        local.intervalEnteredAt = enteredAt
        XCTAssertEqual(
            SyncTimestamp.parse(deviceA.manager.testingTaskPayload(local)["interval_entered_at"] as? String),
            enteredAt
        )

        let remote = SupabaseTaskDTO(
            id: "remote-moved", text: "Remote moved task", completed: false,
            created_at: SyncTimestamp.format(t0), interval_type: "1 Hour",
            interval_entered_at: SyncTimestamp.format(enteredAt), order: 0,
            deleted_at: nil, completed_at: nil, habit_id: nil,
            user_id: deviceA.manager.testingUserId, updated_at: SyncTimestamp.format(enteredAt)
        )
        deviceA.manager.testingMerge(tasks: [remote])
        XCTAssertEqual(try deviceA.task(id: remote.id)?.intervalEnteredAt, enteredAt)
    }
    
    func testPayloadSendsTimestampsInServerTime() throws {
        let skewed = try SyncDevice(clockOffset: 120)
        let task = skewed.createTask("Skewed", at: t0)
        
        let payload = skewed.manager.testingTaskPayload(task)
        let sent = SyncTimestamp.parse(payload["updated_at"] as? String)
        
        XCTAssertEqual(sent?.timeIntervalSince1970 ?? 0,
                       t0.addingTimeInterval(120).timeIntervalSince1970,
                       accuracy: 0.01)
    }
}
