import XCTest

@MainActor
final class AccountIdentityTransitionTests: XCTestCase {
    func testIdentityPolicyDistinguishesFreshSameAndDifferentAccounts() {
        XCTAssertEqual(SessionIdentityPolicy.transition(isAuthenticated: false, currentUserId: nil, incomingUserId: "A"), .freshLogin)
        XCTAssertEqual(SessionIdentityPolicy.transition(isAuthenticated: true, currentUserId: "A", incomingUserId: "A"), .sameAccount)
        XCTAssertEqual(SessionIdentityPolicy.transition(isAuthenticated: true, currentUserId: "A", incomingUserId: "B"), .rejectAccountSwitch)
    }

    func testSameAccountReauthenticationPreservesUnsyncedLocalRows() throws {
        let store = try TestStore()
        let task = store.addTask("Pending thought", updatedAt: TestTime.now)
        let manager = SupabaseSyncManager.makeForTesting(context: store.context, uid: "A", transport: IdentityTransport())

        let accepted = manager.testingApplyAuthResponse(authResponse(userId: "A"), email: "a@example.com")

        XCTAssertTrue(accepted)
        XCTAssertEqual(try store.tasks().map(\.text), ["Pending thought"])
        XCTAssertNil(task.syncedAt)
        XCTAssertTrue(manager.testingIsAuthenticated)
    }

    func testDifferentAccountResponseIsRejectedWithoutPurgingCurrentRows() throws {
        let store = try TestStore()
        store.addTask("Account A private row")
        let manager = SupabaseSyncManager.makeForTesting(context: store.context, uid: "A", transport: IdentityTransport())

        let accepted = manager.testingApplyAuthResponse(authResponse(userId: "B"), email: "b@example.com")

        XCTAssertFalse(accepted)
        XCTAssertEqual(try store.tasks().map(\.text), ["Account A private row"])
        XCTAssertTrue(manager.testingIsAuthenticated)
        XCTAssertEqual(manager.testingUserId, "A")
    }

    func testFailedPurgeSaveRollsBackStagedDeletes() throws {
        let store = try TestStore()
        store.addTask("Keep me")
        store.addHabit("Keep habit")
        let list = store.addScratchpadList("Keep list")
        store.addScratchpadItem("Keep note", listId: list.id)
        try store.save()
        let manager = SupabaseSyncManager.makeForTesting(context: store.context, uid: "A")
        manager.testingPersistenceSaveResults([false])

        XCTAssertFalse(manager.testingPurgeLocalStore())
        XCTAssertEqual(try store.tasks().count, 1)
        XCTAssertEqual(try store.habits().count, 1)
        XCTAssertEqual(try store.scratchpadLists().count, 1)
        XCTAssertEqual(try store.scratchpadItems().count, 1)
    }

    private func authResponse(userId: String) -> AuthResponse {
        AuthResponse(
            access_token: "new-access",
            refresh_token: "new-refresh",
            token_type: "bearer",
            expires_in: 3600,
            user: AuthUser(id: userId, email: "\(userId)@example.com")
        )
    }
}

@MainActor
private final class IdentityTransport: HTTPDataTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}
