import Foundation
import SwiftData
import XCTest

@MainActor
private final class ScriptedTransport: HTTPDataTransport {
    enum Step {
        case response(Int, Data)
        case failure(URLError.Code)
    }

    var steps: [Step]
    private(set) var requests: [URLRequest] = []

    init(_ steps: [Step]) { self.steps = steps }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !steps.isEmpty else { throw URLError(.badServerResponse) }
        switch steps.removeFirst() {
        case .failure(let code):
            throw URLError(code)
        case .response(let status, let data):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
    }
}

@MainActor
final class SyncTransportFailureTests: XCTestCase {
    private let ok = ScriptedTransport.Step.response(201, Data())

    func testNetworkLossAndHTTPFailuresLeaveTaskDirtyForRetry() async throws {
        let failures: [(String, [ScriptedTransport.Step])] = [
            ("offline", [.failure(.notConnectedToInternet)]),
            ("timeout", [.failure(.timedOut)]),
            ("401", [.response(401, Data()), .response(400, Data("{}".utf8))]),
            ("403", [.response(403, Data())]),
            ("408", [.response(408, Data())]),
            ("409", [.response(409, Data())]),
            ("429", [.response(429, Data())]),
            ("500", [.response(500, Data())])
        ]

        for (label, steps) in failures {
            let store = try TestStore()
            let task = store.addTask("Never lose me", updatedAt: TestTime.now)
            let manager = SupabaseSyncManager.makeForTesting(context: store.context, transport: ScriptedTransport(steps))

            let pushed = await manager.testingPush()
            XCTAssertFalse(pushed, label)
            XCTAssertNil(task.syncedAt, label)
            XCTAssertEqual(task.text, "Never lose me", label)
            XCTAssertEqual(try store.tasks().count, 1, label)
        }
    }

    func testPartialBatchSuccessMarksOnlyAcceptedRowsAndRetriesTheRest() async throws {
        let store = try TestStore()
        let tasks = (0..<201).map { store.addTask("Task \($0)", order: $0, updatedAt: TestTime.now) }
        let transport = ScriptedTransport([ok, .response(500, Data()), ok])
        let manager = SupabaseSyncManager.makeForTesting(context: store.context, transport: transport)

        let firstPush = await manager.testingPush()
        XCTAssertFalse(firstPush)
        XCTAssertEqual(tasks.filter { $0.syncedAt != nil }.count, 200)
        XCTAssertEqual(tasks.filter { $0.syncedAt == nil }.count, 1)

        let retryPush = await manager.testingPush()
        XCTAssertTrue(retryPush)
        XCTAssertEqual(tasks.filter { $0.syncedAt != nil }.count, 201)
        XCTAssertEqual(try store.tasks().count, 201)
    }

    func testAmbiguousFailureAfterServerAcceptanceSafelyRetriesSameId() async throws {
        let store = try TestStore()
        let task = store.addTask("Idempotent", id: "stable", updatedAt: TestTime.now)
        let transport = ScriptedTransport([.failure(.networkConnectionLost), ok])
        let manager = SupabaseSyncManager.makeForTesting(context: store.context, transport: transport)

        let ambiguousPush = await manager.testingPush()
        XCTAssertFalse(ambiguousPush)
        XCTAssertNil(task.syncedAt)
        let successfulRetry = await manager.testingPush()
        XCTAssertTrue(successfulRetry)
        XCTAssertEqual(task.syncedAt, task.updatedAt)
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "POST" }.count, 2)
    }

    func testPaginationReadsMoreThanOneThousandRowsWithoutTruncation() async throws {
        func page(_ range: Range<Int>) throws -> Data {
            let rows: [[String: Any]] = range.map {
                ["id": "task-\($0)", "text": "Task \($0)", "user_id": "test-user", "updated_at": SyncTimestamp.format(TestTime.now)]
            }
            return try JSONSerialization.data(withJSONObject: rows)
        }
        let transport = ScriptedTransport([
            .response(200, try page(0..<500)),
            .response(200, try page(500..<1000)),
            .response(200, try page(1000..<1001))
        ])
        let store = try TestStore()
        let manager = SupabaseSyncManager.makeForTesting(context: store.context, transport: transport)

        let rows = await manager.testingFetchTasks()
        XCTAssertEqual(rows?.count, 1001)
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertTrue(transport.requests[1].url?.query?.contains("offset=500") == true)
        XCTAssertTrue(transport.requests[2].url?.query?.contains("offset=1000") == true)
    }

    func testMalformedResponseAbortsSnapshotInsteadOfReturningEmptyData() async throws {
        let store = try TestStore()
        let transport = ScriptedTransport([.response(200, Data("not-json".utf8))])
        let manager = SupabaseSyncManager.makeForTesting(context: store.context, transport: transport)

        let rows = await manager.testingFetchTasks()
        XCTAssertNil(rows)
    }
}
