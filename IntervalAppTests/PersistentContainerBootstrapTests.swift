import SwiftData
import XCTest

@MainActor
final class PersistentContainerBootstrapTests: XCTestCase {
    private struct OpenFailure: LocalizedError {
        var errorDescription: String? { "store is corrupt" }
    }

    private func memoryContainer() throws -> ModelContainer {
        let schema = Schema([TaskItem.self, HabitItem.self, ScratchpadList.self, ScratchpadItem.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    func testHealthyStoreUsesPersistentContainerWithoutRecoveryMessage() throws {
        let expected = try memoryContainer()
        var fallbackCalled = false
        let result = PersistentContainerBootstrap.choose(
            primary: { expected },
            fallback: {
                fallbackCalled = true
                return try self.memoryContainer()
            }
        )

        XCTAssertTrue(result.container === expected)
        XCTAssertNil(result.startupError)
        XCTAssertFalse(fallbackCalled)
    }

    func testFailedStoreOpenUsesBlockedRecoveryContainerAndExplainsPreservation() throws {
        let recovery = try memoryContainer()
        let result = PersistentContainerBootstrap.choose(
            primary: { throw OpenFailure() },
            fallback: { recovery }
        )

        XCTAssertTrue(result.container === recovery)
        XCTAssertTrue(result.startupError?.contains("left untouched") == true)
        XCTAssertTrue(result.startupError?.contains("store is corrupt") == true)
    }
}
