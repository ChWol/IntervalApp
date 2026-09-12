import Foundation
import XCTest

/// Keeps the app/widget hand-off deliberately boring: snapshots must be stable,
/// ordered data that the extension can decode without importing SwiftData.
final class WidgetSnapshotTests: XCTestCase {
    func testSnapshotRoundTripsTasksInOrder() throws {
        let snapshot = WidgetSnapshot(
            tasks: [
                WidgetTaskSnapshot(id: "first", title: "Write tests", order: 0),
                WidgetTaskSnapshot(id: "second", title: "Ship it", order: 1)
            ],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.tasks.map(\.id), ["first", "second"])
    }

    func testEmptySnapshotIsRepresentedWithoutPlaceholderTasks() {
        let snapshot = WidgetSnapshot(tasks: [], generatedAt: .distantPast)

        XCTAssertTrue(snapshot.tasks.isEmpty)
        XCTAssertEqual(snapshot.generatedAt, .distantPast)
    }
}
