import Foundation
import XCTest

@MainActor
final class AccountDeletionSafetyTests: XCTestCase {
    func testFailedServerDeletionPreservesSessionAndEveryLocalRow() async throws {
        let store = try TestStore()
        store.addTask("Keep task")
        store.addHabit("Keep habit")
        let list = store.addScratchpadList("Keep list")
        store.addScratchpadItem("Keep note", listId: list.id)
        let transport = ScriptedAccountDeletionTransport(status: 500)
        let manager = SupabaseSyncManager.makeForTesting(context: store.context, transport: transport)

        let deleted = await manager.testingDeleteAccount()

        XCTAssertFalse(deleted)
        XCTAssertTrue(manager.testingIsAuthenticated)
        XCTAssertEqual(try store.tasks().count, 1)
        XCTAssertEqual(try store.habits().count, 1)
        XCTAssertEqual(try store.scratchpadLists().count, 1)
        XCTAssertEqual(try store.scratchpadItems().count, 1)
    }

    func testConfirmedServerDeletionPurgesLocalRowsWithoutReupload() async throws {
        let store = try TestStore()
        store.addTask("Delete task")
        store.addHabit("Delete habit")
        let list = store.addScratchpadList("Delete list")
        store.addScratchpadItem("Delete note", listId: list.id)
        let transport = ScriptedAccountDeletionTransport(status: 204)
        let manager = SupabaseSyncManager.makeForTesting(context: store.context, transport: transport)

        let deleted = await manager.testingDeleteAccount()

        XCTAssertTrue(deleted)
        XCTAssertFalse(manager.testingIsAuthenticated)
        XCTAssertTrue(try store.tasks().isEmpty)
        XCTAssertTrue(try store.habits().isEmpty)
        XCTAssertTrue(try store.scratchpadLists().isEmpty)
        XCTAssertTrue(try store.scratchpadItems().isEmpty)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.httpMethod, "POST")
        XCTAssertTrue(transport.requests.first?.url?.path.hasSuffix("/rpc/delete_interval_account") == true)
    }
}

@MainActor
private final class ScriptedAccountDeletionTransport: HTTPDataTransport {
    let status: Int
    private(set) var requests: [URLRequest] = []

    init(status: Int) { self.status = status }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return (
            Data(),
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
    }
}
