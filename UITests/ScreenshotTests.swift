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

        for (index, tab) in ["Fitness", "Coach", "Health", "Log"].enumerated() {
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

    /// The screen at the top, then after each swipe up until the content stops
    /// moving (at most 6 swipes). `app.debugDescription` can't tell: it changes
    /// on every read (element addresses, the clock), so every screen used to
    /// take 7 pages, most of them duplicates.
    private func capture(_ app: XCUIApplication, _ name: String) {
        attach(app, "\(name)-0")
        var previous = scrollPosition(app)
        for page in 1...6 {
            app.swipeUp(velocity: .slow)
            sleep(1)
            let current = scrollPosition(app)
            if current == previous { break }
            previous = current
            attach(app, "\(name)-\(page)")
        }
        // Back to the top for the next screen.
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }
    }

    /// Where the page's content sits: the label and position of the first text
    /// in the frontmost full-height scroll view or list. The same after a swipe
    /// means the page is at its end.
    private func scrollPosition(_ app: XCUIApplication) -> String {
        let container: XCUIElement = mainScrollContainer(app) ?? app
        let text = container.staticTexts.firstMatch
        guard text.exists else { return "" }
        let frame = text.frame
        return "\(text.label)|\(Int(frame.minX.rounded())),\(Int(frame.minY.rounded()))"
    }

    /// The page's own scroller: taller than half the window and covering its
    /// centre (so horizontal chip rows don't count). The last one in the tree
    /// is the frontmost, e.g. a sheet's list over the tab behind it.
    private func mainScrollContainer(_ app: XCUIApplication) -> XCUIElement? {
        let types: [XCUIElement.ElementType] = [.scrollView, .collectionView, .table]
        let predicate = NSPredicate(format: "elementType IN %@", types.map { NSNumber(value: $0.rawValue) } as NSArray)
        let window = app.windows.firstMatch.frame
        let centre = CGPoint(x: window.midX, y: window.midY)
        let candidates = app.descendants(matching: .any).matching(predicate).allElementsBoundByIndex
        return candidates.last { element in
            let frame = element.frame
            return frame.height > window.height / 2 && frame.contains(centre)
        }
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
