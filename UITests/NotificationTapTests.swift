import XCTest

/// Taps a real check-in notification from the Home Screen and checks the app
/// opens the check-in instead of crashing.
final class NotificationTapTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTappingMorningCheckInNotification() throws {
        try tapCheckInNotification(kind: "morning", title: "Morning check-in")
    }

    func testTappingEveningCheckInNotification() throws {
        try tapCheckInNotification(kind: "evening", title: "Evening check-in")
    }

    private func tapCheckInNotification(kind: String, title: String) throws {
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launchArguments = ["-hasOnboarded", "YES", "-scheduleTestCheckIn", kind]
        app.launch()

        // Allow notifications if iOS asks.
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 10) { allow.tap() }

        // Leave the app so the notification shows as a banner.
        sleep(2)
        XCUIDevice.shared.press(.home)

        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 30), "No \(title) notification appeared")
        banner.tap()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "App didn't come to the front")
        sleep(6)
        XCTAssertEqual(app.state, .runningForeground, "App is no longer running after tapping the notification")
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), "The \(title) screen didn't open")
    }
}
