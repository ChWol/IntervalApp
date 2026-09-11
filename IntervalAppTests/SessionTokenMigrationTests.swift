import XCTest

final class SessionTokenMigrationTests: XCTestCase {
    func testSecureTokenWinsAndLegacyCanBeRemoved() {
        var attemptedStore = false
        let result = SessionTokenMigration.select(secure: "secure", legacy: "legacy") { _ in
            attemptedStore = true
            return true
        }
        XCTAssertEqual(result, SessionTokenMigrationResult(token: "secure", legacyCanBeRemoved: true))
        XCTAssertFalse(attemptedStore)
    }

    func testLegacyTokenMovesToSecureStorageBeforePreferenceCanBeRemoved() {
        var stored = ""
        let result = SessionTokenMigration.select(secure: nil, legacy: "legacy") {
            stored = $0
            return true
        }
        XCTAssertEqual(stored, "legacy")
        XCTAssertEqual(result, SessionTokenMigrationResult(token: "legacy", legacyCanBeRemoved: true))
    }

    func testFailedKeychainMigrationKeepsLegacyRecoveryCopy() {
        let result = SessionTokenMigration.select(secure: nil, legacy: "legacy") { _ in false }
        XCTAssertEqual(result, SessionTokenMigrationResult(token: "legacy", legacyCanBeRemoved: false))
    }
}
