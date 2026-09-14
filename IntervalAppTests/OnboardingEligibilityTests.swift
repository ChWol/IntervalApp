import XCTest

final class OnboardingEligibilityTests: XCTestCase {
    func testGermanTourHasTranslatedTitlesMessagesAndNavigation() {
        let manager = LocalizationManager.shared
        let original = manager.currentLanguage
        defer { manager.currentLanguage = original }
        manager.currentLanguage = .german

        for step in OnboardingStep.all {
            XCTAssertNotEqual(step.title.localized, step.title, "Missing German title: \(step.title)")
            XCTAssertNotEqual(step.message.localized, step.message, "Missing German message: \(step.title)")
        }
        for label in ["Back", "Next", "Finish", "Skip tour", "Replay the tour"] {
            XCTAssertNotEqual(label.localized, label)
        }
    }

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
