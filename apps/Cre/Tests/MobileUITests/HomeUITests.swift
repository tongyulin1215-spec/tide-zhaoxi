import XCTest

/// Drives the phone home screen on demo data (CRE_DEMO=1).
final class HomeUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CRE_DEMO"] = "1"
        app.launchEnvironment["CRE_TODAY"] = "2026-10-09"
        app.launchArguments += extra
        app.launch()
        return app
    }

    func testTickMovesRowToDone() {
        let app = launch()
        let tick = app.buttons["tick-交周报"]
        XCTAssertTrue(tick.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["未完成 6"].exists)
        tick.tap()
        XCTAssertTrue(app.staticTexts["已完成 3"].waitForExistence(timeout: 3))
    }

    func testSwipeDelete() {
        let app = launch()
        let row = app.otherElements["row-买香蕉"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["删除"].tap()
        XCTAssertFalse(app.otherElements["row-买香蕉"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["pick-day"].label.contains("10月9日"))  // a row swipe never changes the day
    }

    func testSwipeOnTitleChangesDay() {
        let app = launch()
        let title = app.buttons["pick-day"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.contains("10月9日"))
        title.swipeLeft()
        XCTAssertTrue(app.buttons["pick-day"].label.contains("10月10日"))
        XCTAssertFalse(app.staticTexts["2026年10月"].exists)  // swiping never opens the calendar
        app.buttons["pick-day"].swipeRight()
        app.buttons["pick-day"].swipeRight()
        XCTAssertTrue(app.buttons["pick-day"].label.contains("10月8日"), app.buttons["pick-day"].label)
    }

    func testTypedLineWithStartDayAppearsThatDay() {
        let app = launch()
        let field = app.textFields["记录想法或安排"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("从10.12开始，每天背单词半小时\n")
        XCTAssertFalse(app.otherElements["row-背单词半小时"].waitForExistence(timeout: 2))  // not before its start
        for _ in 0..<3 { app.buttons["next-day"].tap() }                                                   // demo today 10/9 → 10/12
        XCTAssertTrue(app.otherElements["row-背单词半小时"].waitForExistence(timeout: 3))
    }

    func testTapRowOpensEditSheet() {
        let app = launch()
        let row = app.otherElements["row-交周报"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["编辑"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["名称"].exists)
    }

    func testEnglishLocaleKeepsChineseDates() {
        let app = launch(["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '月'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testCalendarButtonNeedsText() {
        let app = launch()
        let cal = app.buttons["选时间"]
        XCTAssertTrue(cal.waitForExistence(timeout: 5))
        XCTAssertFalse(cal.isEnabled)
        let field = app.textFields["记录想法或安排"]
        field.tap()
        field.typeText("买电池")
        XCTAssertTrue(cal.isEnabled)
    }

    func testRepeatRowArrowExpandsTapEdits() {
        let app = launch()
        let arrow = app.buttons["expand-健身"]
        XCTAssertTrue(arrow.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["弯举 4×10"].exists)
        arrow.tap()
        XCTAssertTrue(app.staticTexts["弯举 4×10"].waitForExistence(timeout: 3))
        app.staticTexts["健身"].tap()
        XCTAssertTrue(app.navigationBars["编辑"].waitForExistence(timeout: 3))
    }

    func testJapaneseCalendarKeepsChineseDates() {
        let app = launch(["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP@calendar=japanese"])
        XCTAssertTrue(app.buttons["pick-day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pick-day"].label.contains("10月9日"), app.buttons["pick-day"].label)
    }

    func testSummaryButtonOpensToday() {
        let app = launch()
        let button = app.buttons["summarize-today"]
        for _ in 0..<4 where !button.waitForExistence(timeout: 0.5) || !button.isHittable { app.swipeUp() }
        button.tap()
        XCTAssertTrue(app.textViews["随笔"].waitForExistence(timeout: 3))
    }

    func testTodayLinkReturnsToToday() {
        let app = launch()
        XCTAssertTrue(app.buttons["next-day"].waitForExistence(timeout: 5))
        app.buttons["next-day"].tap()
        app.tabBars.buttons["记账"].tap()
        app.open(URL(string: "tide://today")!)
        XCTAssertTrue(app.buttons["pick-day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pick-day"].label.contains("10月9日"), app.buttons["pick-day"].label)
    }
}
