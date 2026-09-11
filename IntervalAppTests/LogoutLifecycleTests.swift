import Foundation
import XCTest

@MainActor
final class LogoutLifecycleTests: XCTestCase {
    func testLogoutWithNoPendingChangesPurgesOnlyAfterSafeCompletion() async throws {
        let store = try TestStore()
        store.addTask("Already synced", updatedAt: TestTime.now, syncedAt: TestTime.now)
        try store.save()
        let transport = LogoutTransport([])
        let manager = SupabaseSyncManager.makeForTesting(context: store.context, transport: transport)

        await manager.signOutAsync()

        XCTAssertFalse(manager.testingIsAuthenticated)
        XCTAssertTrue(try store.tasks().isEmpty)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testLogoutUploadsUnsyncedEditBeforePurging() async throws {
        let store = try TestStore()
        store.addTask("Pending", updatedAt: TestTime.now)
        let transport = LogoutTransport([.response(201)])
        let manager = SupabaseSyncManager.makeForTesting(context: store.context, transport: transport)

        await manager.signOutAsync()

        XCTAssertFalse(manager.testingIsAuthenticated)
        XCTAssertTrue(try store.tasks().isEmpty)
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }

    func testLogoutNetworkFailurePreservesSessionAndUnsyncedEdit() async throws {
        let store = try TestStore()
        let task = store.addTask("Pending", updatedAt: TestTime.now)
        let manager = SupabaseSyncManager.makeForTesting(
            context: store.context,
            transport: LogoutTransport([.failure(.notConnectedToInternet)])
        )

        await manager.signOutAsync()

        XCTAssertTrue(manager.testingIsAuthenticated)
        XCTAssertEqual(try store.tasks().map(\.text), ["Pending"])
        XCTAssertNil(task.syncedAt)
    }

    func testLogoutDuringPushOrPullCannotPurgeLocalRows() async throws {
        for state in [(true, false), (false, true)] {
            let store = try TestStore()
            store.addTask("Do not purge")
            let manager = SupabaseSyncManager.makeForTesting(context: store.context, transport: LogoutTransport([]))
            manager.testingSetSyncActivity(pushing: state.0, pulling: state.1)

            await manager.signOutAsync()

            XCTAssertTrue(manager.testingIsAuthenticated)
            XCTAssertEqual(try store.tasks().map(\.text), ["Do not purge"])
            manager.testingSetSyncActivity(pushing: false, pulling: false)
        }
    }
}

@MainActor
private final class LogoutTransport: HTTPDataTransport {
    enum Step { case response(Int), failure(URLError.Code) }
    var steps: [Step]
    private(set) var requests: [URLRequest] = []

    init(_ steps: [Step]) { self.steps = steps }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !steps.isEmpty else { throw URLError(.badServerResponse) }
        switch steps.removeFirst() {
        case .failure(let code): throw URLError(code)
        case .response(let status):
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}
