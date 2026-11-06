import XCTest
import UIKit

/// A visual-QA tour of every tab, the pages and sheets behind them, a live
/// workout, dark mode and onboarding, for design review in CI
/// (`.github/workflows/screenshots.yml`). The app launches with
/// `-demoData YES` (`DemoMode`), so every screen has made-up content in the
/// Simulator, where Apple Health is empty.
///
/// Not a pass/fail check: a step whose button isn't found is recorded as a
/// "MISSING <name>" line (printed, and attached as a note at the end) and
/// the tour carries on. Shots are JPEG at quality 0.5 and 1× scale, named
/// with a running number so they print in tour order.
@MainActor
final class ScreenshotTests: XCTestCase {
    private var shotNumber = 0
    private var missing: [String] = []

    override func setUp() async throws {
        continueAfterFailure = true
    }

    func testCaptureMainScreens() throws {
        let app = launch(appearance: "light")
        tourToday(app)
        tourFitness(app)
        tourCoach(app)
        tourHealth(app)
        tourLog(app)
        tourSettings(app)
        tourWorkout(app)
        app.terminate()

        let dark = launch(appearance: "dark")
        tourDark(dark)
        dark.terminate()

        let fresh = launch(appearance: "light", onboarded: false)
        tourOnboarding(fresh)
        fresh.terminate()

        let note = XCTAttachment(string: missing.isEmpty ? "Nothing missing." : missing.joined(separator: "\n"))
        note.name = "zz-missing"
        note.lifetime = .keepAlways
        add(note)
    }

    // MARK: - Tours

    private func tourToday(_ app: XCUIApplication) {
        openTab(app, "Today")
        capture(app, "today", pages: 5)
        openTab(app, "Today")
        for ring in ["strain", "recovery", "sleep"] {
            if tap(app, ["ring-\(ring)"], name: "Today \(ring) ring") {
                capture(app, "today-\(ring)-sheet", pages: 2)
                dismissSheet(app)
            }
        }
        for tile in ["rhr", "respiration", "sleepAverage"] {
            if tap(app, ["tile-\(tile)"], name: "Today \(tile) tile") {
                capture(app, "today-tile-\(tile)", pages: 1)
                dismissSheet(app)
            }
        }
        openTab(app, "Today")
        if tap(app, ["How calories are calculated"], name: "Calorie details") {
            capture(app, "today-calorie-details", pages: 1)
            dismissSheet(app)
        }
        openTab(app, "Today")
        // The vitamins line under the macros pushes the micronutrients page.
        if tap(app, ["Shows what to fix in your diet", "Vitamins"], name: "Today vitamins line") {
            capture(app, "today-micronutrients", pages: 2)
            back(app)
        }
        openSheet(app, link: "workoutapp://checkin/morning", name: "morning check-in")
        capture(app, "checkin-morning", pages: 2)
        dismissSheet(app)
        openSheet(app, link: "workoutapp://review", name: "weekly review")
        capture(app, "weekly-review", pages: 2)
        dismissSheet(app)
    }

    private func tourFitness(_ app: XCUIApplication) {
        openTab(app, "Fitness")
        capture(app, "fitness", pages: 4)
        openTab(app, "Fitness")
        if tap(app, ["Edit plan", "Plan your week"], name: "Fitness edit plan") {
            capture(app, "weekly-plan-editor", pages: 2)
            dismissSheet(app)
        }
        let pages: [(key: String, name: String)] = [
            ("metric-Heart-rate zones", "zones"),
            ("metric-Cardio fitness (VO₂ max)", "cardio-fitness"),
            ("metric-Strength", "strength"),
            ("metric-Muscles", "muscles"),
            ("metric-Lift goals (2)", "lift-goals"),
        ]
        for page in pages {
            openTab(app, "Fitness")
            if tap(app, [page.key, String(page.key.dropFirst("metric-".count))], name: "Fitness \(page.name)") {
                capture(app, "fitness-\(page.name)", pages: 2)
                back(app)
            }
        }
        openTab(app, "Fitness")
        if tap(app, ["Saved workouts"], name: "Fitness saved workouts") {
            capture(app, "saved-workouts", pages: 1)
            // A row's own tap starts the workout, so the editor is opened from "New workout".
            if tap(app, ["New workout"], name: "Saved workouts new workout") {
                capture(app, "workout-editor", pages: 1)
                dismissSheet(app)
            }
            back(app)
        }
        openTab(app, "Fitness")
        if tap(app, ["Workout history", "History"], name: "Fitness history") {
            capture(app, "history", pages: 1)
            if tapFirstCell(app, name: "History first session") {
                capture(app, "workout-detail", pages: 2)
                if tap(app, ["Progress"], name: "Workout detail progress") {
                    capture(app, "lift-progress", pages: 2)
                    back(app)
                }
                back(app)
            }
            back(app)
        }
    }

    private func tourCoach(_ app: XCUIApplication) {
        openTab(app, "Coach")
        capture(app, "coach", pages: 1)
        if tap(app, ["Why is my recovery where it is?"], name: "Coach suggested question", scroll: false) {
            sleep(4)
            capture(app, "coach-answer", pages: 2)
        }
        if tap(app, ["More"], name: "Coach more menu", scroll: false),
           tap(app, ["Coach status"], name: "Coach status", scroll: false) {
            capture(app, "coach-status", pages: 1)
            dismissSheet(app)
        }
    }

    private func tourHealth(_ app: XCUIApplication) {
        openTab(app, "Health")
        sleep(2)
        capture(app, "health", pages: 4)
        let pages: [(keys: [String], name: String)] = [
            (["metric-Weight trend", "Weight trend"], "weight"),
            (["metric-Resting heart rate", "Resting heart rate"], "resting-hr"),
            (["metric-VO₂ max", "VO₂ max"], "vo2max"),
            (["metric-Body age", "Body age"], "body-age"),
            (["metric-Vitamins & minerals", "row-Vitamins & minerals"], "vitamins-minerals"),
            (["row-Heart", "Heart"], "category-heart"),
            (["row-Sleep", "Sleep"], "category-sleep"),
            (["row-Activity", "Activity"], "category-activity"),
            (["row-Body", "Body"], "category-body"),
            (["row-Breathing & temperature", "Breathing & temperature"], "category-breathing"),
            (["row-Lab results", "Lab results"], "labs"),
            (["row-Blood pressure"], "blood-pressure"),
            (["row-Body measurements", "Body measurements"], "body-measurements"),
            (["row-Progress photos", "Progress photos"], "progress-photos"),
            (["row-Medications", "Medications"], "medications"),
            (["row-Supplements", "Supplements"], "supplements"),
            (["row-What affects you", "What affects you"], "patterns"),
            (["row-Alcohol and your sleep", "Alcohol and your sleep"], "alcohol-sleep"),
            (["metric-Mood", "Mood"], "mood"),
        ]
        for page in pages {
            openTab(app, "Health")
            if tap(app, page.keys, name: "Health \(page.name)") {
                capture(app, "health-\(page.name)", pages: 1)
                back(app)
            }
        }
    }

    private func tourLog(_ app: XCUIApplication) {
        openTab(app, "Log")
        capture(app, "log", pages: 2)
        let pushes: [(key: String, name: String)] = [("Drinks", "drinks"), ("Medications & supplements", "medications")]
        for page in pushes {
            openTab(app, "Log")
            if tap(app, [page.key], name: "Log \(page.name)") {
                capture(app, "log-\(page.name)", pages: 2)
                back(app)
            }
        }
        let sheets: [(key: String, name: String)] = [
            ("Overnight HRV", "hrv-entry"), ("Blood pressure", "blood-pressure"), ("Waist & grip", "measurements"),
            ("Progress photo", "progress-photo"), ("Lab results", "labs"),
        ]
        for sheet in sheets {
            openTab(app, "Log")
            if tap(app, [sheet.key], name: "Log \(sheet.name)") {
                capture(app, "log-\(sheet.name)", pages: 1)
                dismissSheet(app)
            }
        }
        openSheet(app, link: "workoutapp://checkin/evening", name: "evening check-in")
        capture(app, "checkin-evening", pages: 2)
        dismissSheet(app)
    }

    private func tourSettings(_ app: XCUIApplication) {
        openTab(app, "Today")
        guard tap(app, ["Settings"], name: "Settings button", scroll: false) else { return }
        capture(app, "settings", pages: 4)
        let pages: [(keys: [String], name: String)] = [
            (["Goals"], "goals"),
            (["Gym equipment"], "gym"),
            (["City"], "city"),
            (["Medication reminders"], "medication-reminders"),
            (["Using a Garmin"], "garmin-help"),
            (["Using Cronometer"], "cronometer-help"),
        ]
        for page in pages {
            if tap(app, page.keys, name: "Settings \(page.name)") {
                capture(app, "settings-\(page.name)", pages: page.name == "goals" ? 2 : 1)
                if page.name == "goals", tap(app, ["Bench Press"], name: "Goals lift goal") {
                    capture(app, "settings-lift-goal-editor", pages: 1)
                    back(app)
                }
                back(app)
            }
        }
        if tap(app, ["What's RPE?", "RPE guide", "How RPE works"], name: "Settings RPE guide") {
            capture(app, "settings-rpe-guide", pages: 1)
            dismissSheet(app)
        }
        dismissSheet(app)
    }

    /// The builder from Today's start button, its pain page, then a live
    /// workout with three sets ticked off.
    private func tourWorkout(_ app: XCUIApplication) {
        openTab(app, "Today")
        var opened = tap(app, ["Start Upper", "Start workout"], name: "Today start button")
        if !opened {
            openTab(app, "Log")
            opened = tap(app, ["Start workout"], name: "Log start workout")
        }
        guard opened else { return }
        capture(app, "workout-builder", pages: 2)
        if tap(app, ["Working around pain", "Something hurts?"], name: "Builder pain row") {
            capture(app, "pain-log", pages: 1)
            back(app)
        }
        guard tap(app, ["Start workout"], name: "Builder start", type: .button, scroll: false) else { return }
        sleep(3)
        dismissSystemAlerts()
        capture(app, "active-workout", pages: 1)
        for set in 1...3 {
            if tap(app, ["Mark "], name: "Tick set \(set)") {
                sleep(1)
                // A rest timer may cover the list; the next set is still found by label.
            }
        }
        sleep(1)
        capture(app, "active-workout-sets", pages: 2)
        if tap(app, ["Workout options"], name: "Workout options", scroll: false) {
            capture(app, "active-workout-menu", pages: 1)
            if !tap(app, ["Minimize"], name: "Minimize workout", scroll: false) { dismissSheet(app) }
        }
        sleep(2)
        openTab(app, "Today")
        capture(app, "today-with-workout", pages: 1)
    }

    private func tourDark(_ app: XCUIApplication) {
        for tab in ["Today", "Fitness", "Coach", "Health", "Log"] {
            openTab(app, tab)
            sleep(1)
            capture(app, "dark-\(tab.lowercased())", pages: 1)
        }
        openTab(app, "Today")
        if tap(app, ["ring-recovery"], name: "Dark recovery ring") {
            capture(app, "dark-recovery-sheet", pages: 1)
            dismissSheet(app)
        }
        if tap(app, ["Settings"], name: "Dark settings", scroll: false) {
            capture(app, "dark-settings", pages: 1)
            dismissSheet(app)
        }
    }

    private func tourOnboarding(_ app: XCUIApplication) {
        sleep(1)
        capture(app, "onboarding-welcome", pages: 1)
        if tap(app, ["Not now"], name: "Onboarding not now") {
            capture(app, "onboarding-setup", pages: 1)
        }
    }

    // MARK: - Launch and navigation

    private func launch(appearance: String, onboarded: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-demoData", "YES",
            "-hasOnboarded", onboarded ? "YES" : "NO",
            "-skipHealthPrompt", "YES",
            "-appearance", appearance,
        ]
        app.launch()
        sleep(4)
        dismissSystemAlerts()
        // Scores, sleep and the 28 days of strain take a moment on first launch.
        sleep(3)
        dismissSystemAlerts()
        return app
    }

    /// Taps "Allow" (or OK) on any system alert, e.g. the notification permission.
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.exists else { return }
            let buttons = ["Allow", "OK", "Allow While Using App", "Continue"]
            guard let button = buttons.map({ alert.buttons[$0] }).first(where: { $0.exists }) else { return }
            button.tap()
            sleep(1)
        }
    }

    /// Back to a tab's root: closes sheets and covers, then taps the tab
    /// (twice pops its navigation stack and scrolls to the top).
    private func openTab(_ app: XCUIApplication, _ tab: String) {
        dismissSystemAlerts()
        let button = app.tabBars.buttons[tab]
        for _ in 0..<4 where !button.exists {
            dismissSheet(app)
        }
        guard button.waitForExistence(timeout: 3) else {
            note("MISSING tab \(tab)")
            return
        }
        button.tap()
        sleep(1)
        if button.isSelected {
            button.tap()
            usleep(600_000)
            button.tap()
        }
        sleep(1)
    }

    private func openSheet(_ app: XCUIApplication, link: String, name: String) {
        guard let url = URL(string: link) else { return }
        app.open(url)
        sleep(3)
        dismissSystemAlerts()
        if app.tabBars.buttons["Today"].exists && !app.navigationBars.buttons["Cancel"].exists
            && !app.navigationBars.buttons["Done"].exists && !app.navigationBars.buttons["Later"].exists {
            note("MISSING \(name) (\(link))")
        }
    }

    /// Finds the first of `keys` (accessibility identifier, exact label, then
    /// label prefix), scrolling down and then up to look for it, and taps it.
    @discardableResult
    private func tap(_ app: XCUIApplication, _ keys: [String], name: String,
                     type: XCUIElement.ElementType = .any, scroll: Bool = true) -> Bool {
        dismissSystemAlerts()
        let swipes: [Bool] = scroll ? Array(repeating: true, count: 6) + Array(repeating: false, count: 8) : []
        for step in 0...swipes.count {
            for key in keys {
                if let element = find(app, key, type: type, wait: step == 0 ? 2 : 0.3), element.isHittable {
                    element.tap()
                    sleep(2)
                    return true
                }
            }
            guard step < swipes.count else { break }
            if swipes[step] {
                app.swipeUp(velocity: .default)
            } else {
                app.swipeDown(velocity: .default)
            }
            usleep(400_000)
        }
        note("MISSING \(name) [\(keys.joined(separator: " | "))]")
        return false
    }

    private func find(_ app: XCUIApplication, _ key: String, type: XCUIElement.ElementType, wait: TimeInterval) -> XCUIElement? {
        let query = app.descendants(matching: type)
        let exact = query.matching(NSPredicate(format: "identifier == %@ OR label == %@", key, key)).firstMatch
        if exact.waitForExistence(timeout: wait), exact.isHittable { return exact }
        let prefix = query.matching(NSPredicate(format: "label BEGINSWITH %@", key)).firstMatch
        if prefix.exists, prefix.isHittable { return prefix }
        return nil
    }

    private func tapFirstCell(_ app: XCUIApplication, name: String) -> Bool {
        let cell = app.cells.firstMatch
        guard cell.waitForExistence(timeout: 3), cell.isHittable else {
            note("MISSING \(name)")
            return false
        }
        cell.tap()
        sleep(2)
        return true
    }

    /// Pops a pushed page with the navigation bar's back button.
    private func back(_ app: XCUIApplication) {
        let bar = app.navigationBars.firstMatch
        let backButton = bar.buttons["BackButton"].exists ? bar.buttons["BackButton"] : bar.buttons.element(boundBy: 0)
        if backButton.exists && backButton.isHittable {
            backButton.tap()
        } else {
            // Edge swipe, like a person going back.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        }
        sleep(1)
    }

    /// Closes the frontmost sheet or menu: its Done / Close / Cancel / Later
    /// button, else a drag down from the top of the sheet.
    private func dismissSheet(_ app: XCUIApplication) {
        for label in ["Done", "Close", "Cancel", "Later"] {
            let button = app.navigationBars.buttons[label]
            if button.exists && button.isHittable {
                button.tap()
                sleep(1)
                return
            }
        }
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        sleep(1)
    }

    private func note(_ line: String) {
        print(line)
        missing.append(line)
    }

    // MARK: - Capture

    /// The screen, then a page after each swipe up until the content stops
    /// moving (at most `pages` shots). `app.debugDescription` can't tell: it
    /// changes on every read (element addresses, the clock).
    private func capture(_ app: XCUIApplication, _ name: String, pages: Int) {
        dismissSystemAlerts()
        attach("\(name)-0")
        guard pages > 1 else { return }
        var previous = scrollPosition(app)
        for page in 1..<pages {
            app.swipeUp(velocity: .slow)
            sleep(1)
            let current = scrollPosition(app)
            if current == previous { break }
            previous = current
            attach("\(name)-\(page)")
        }
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

    /// A 1× JPEG at quality 0.5, so the printed log stays readable.
    private func attach(_ name: String) {
        shotNumber += 1
        let screenshot = XCUIScreen.main.screenshot()
        let image = screenshot.image
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        let attachment: XCTAttachment
        if let data = small.jpegData(compressionQuality: 0.5) {
            attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.jpeg")
        } else {
            attachment = XCTAttachment(screenshot: screenshot)
        }
        let number = String(shotNumber)
        attachment.name = String(repeating: "0", count: max(0, 3 - number.count)) + number + "-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
