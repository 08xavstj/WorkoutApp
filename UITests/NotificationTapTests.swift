import XCTest

/// Taps a real check-in notification and checks the app opens the check-in
/// instead of crashing, both while the app is in the background and after it
/// has been closed.
final class NotificationTapTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testEveningNotificationWhileInBackground() throws {
        try tapCheckInNotification(kind: "evening", title: "Evening check-in", closeAppFirst: false)
    }

    func testMorningNotificationWhileInBackground() throws {
        try tapCheckInNotification(kind: "morning", title: "Morning check-in", closeAppFirst: false)
    }

    func testMorningNotificationAfterClosingTheApp() throws {
        try tapCheckInNotification(kind: "morning", title: "Morning check-in", closeAppFirst: true)
    }

    func testEveningNotificationAfterClosingTheApp() throws {
        try tapCheckInNotification(kind: "evening", title: "Evening check-in", closeAppFirst: true)
    }

    private func tapCheckInNotification(kind: String, title: String, closeAppFirst: Bool) throws {
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launchArguments = ["-hasOnboarded", "YES", "-scheduleTestCheckIn", kind]
        app.launch()

        // Allow notifications if iOS asks.
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        sleep(1)
        if closeAppFirst {
            app.terminate()
        } else {
            XCUIDevice.shared.press(.home)
        }

        // The banner, or the notification in Notification Center if the banner has gone.
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", title)
        var notification = springboard.descendants(matching: .any).matching(predicate).firstMatch
        if !notification.waitForExistence(timeout: 25) || !notification.isHittable {
            let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.001))
            let middle = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6))
            top.press(forDuration: 0.1, thenDragTo: middle)
            notification = springboard.descendants(matching: .any).matching(predicate).firstMatch
            XCTAssertTrue(notification.waitForExistence(timeout: 10), "No \(title) notification found")
        }
        notification.tap()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "App didn't come to the front after tapping the notification")
        sleep(8)
        XCTAssertEqual(app.state, .runningForeground, "App is no longer running after tapping the notification")
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), "The \(title) screen didn't open")
    }
}
