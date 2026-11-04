import XCTest

/// Captures every main screen, scrolled top to bottom, for design review in CI
/// (`.github/workflows/screenshots.yml`). Not a pass/fail check: it only fails
/// if a tab can't be opened.
@MainActor
final class ScreenshotTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = true
    }

    func testCaptureMainScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-hasOnboarded", "YES", "-skipHealthPrompt", "YES"]
        app.launch()
        sleep(3)

        capture(app, "1-home")
        openSettings(app)

        for (index, tab) in ["Fitness", "Coach", "Biology", "Add"].enumerated() {
            let button = app.tabBars.buttons[tab]
            guard button.waitForExistence(timeout: 5) else {
                XCTFail("No \(tab) tab")
                continue
            }
            button.tap()
            sleep(2)
            capture(app, "\(index + 2)-\(tab.lowercased())")
        }
    }

    /// The screen at the top, then after each swipe up until nothing changes (at most 6).
    private func capture(_ app: XCUIApplication, _ name: String) {
        attach(app, "\(name)-0")
        var previous = app.debugDescription
        for page in 1...6 {
            app.swipeUp(velocity: .slow)
            sleep(1)
            let current = app.debugDescription
            if current == previous { break }
            previous = current
            attach(app, "\(name)-\(page)")
        }
        // Back to the top for the next screen.
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }
    }

    private func openSettings(_ app: XCUIApplication) {
        let settings = app.buttons["Settings"]
        guard settings.waitForExistence(timeout: 3) else { return }
        settings.tap()
        sleep(2)
        capture(app, "1b-settings")
        // Close the sheet.
        app.swipeDown(velocity: .fast)
        let done = app.buttons["Done"]
        if done.exists { done.tap() }
        sleep(1)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
