import XCTest

final class OnboardingEligibilityTests: XCTestCase {
    func testNewlyRegisteredEmptyAccountStartsAfterInitialPull() {
        XCTAssertFalse(OnboardingEligibility.shouldWelcome(
            initialPullComplete: false,
            pendingEmail: "new@example.com",
            signedInEmail: "new@example.com",
            accountIsEmpty: true,
            alreadyCompleted: false
        ))
        XCTAssertTrue(OnboardingEligibility.shouldWelcome(
            initialPullComplete: true,
            pendingEmail: "new@example.com",
            signedInEmail: " New@Example.com ",
            accountIsEmpty: true,
            alreadyCompleted: false
        ))
    }

    func testExistingOrDifferentAccountNeverReceivesWelcome() {
        XCTAssertFalse(OnboardingEligibility.shouldWelcome(
            initialPullComplete: true,
            pendingEmail: "new@example.com",
            signedInEmail: "other@example.com",
            accountIsEmpty: true,
            alreadyCompleted: false
        ))
        XCTAssertFalse(OnboardingEligibility.shouldWelcome(
            initialPullComplete: true,
            pendingEmail: "new@example.com",
            signedInEmail: "new@example.com",
            accountIsEmpty: false,
            alreadyCompleted: false
        ))
        XCTAssertFalse(OnboardingEligibility.shouldWelcome(
            initialPullComplete: true,
            pendingEmail: "new@example.com",
            signedInEmail: "new@example.com",
            accountIsEmpty: true,
            alreadyCompleted: true
        ))
    }
}
