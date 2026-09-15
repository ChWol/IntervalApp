import XCTest

final class OnboardingEligibilityTests: XCTestCase {
    func testOnboardingCopyCoversEverySupportedLanguage() {
        let manager = LocalizationManager.shared
        let welcomeKeys = [
            "WELCOME TO INTERVAL",
            "Import your existing tasks from TickTick, Microsoft To Do, Todoist or Apple Reminders, or start fresh.",
            "Import Tasks",
            "Start Fresh"
        ]
        for language in AppLanguage.allCases {
            if language != .english && language != .german {
                XCTAssertEqual(OnboardingTranslations.translations[language]?.count, OnboardingTranslations.keys.count, "Incomplete tour: \(language)")
            }
            for key in OnboardingTranslations.keys + welcomeKeys + ["Sign in to sync your devices", "Sign out paused"] {
                XCTAssertTrue(manager.hasTranslation(for: key, language: language), "Missing \(language) translation: \(key)")
            }
        }
    }

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
