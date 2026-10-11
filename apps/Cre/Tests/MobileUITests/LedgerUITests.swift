import XCTest

/// 记账 on demo data (today pinned to 10/9; demo has 午饭 ¥35 and 地铁 ¥6 today).
final class LedgerUITests: XCTestCase {
    private func launch(_ extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CRE_DEMO"] = "1"
        app.launchEnvironment["CRE_TODAY"] = "2026-10-09"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        app.tabBars.buttons["记账"].tap()
        return app
    }

    func testTypeLineAddsEntry() {
        let app = launch()
        let field = app.textFields["午饭 35"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("奶茶 18\n")
        XCTAssertTrue(app.buttons["entry-奶茶"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["entry-奶茶"].label.contains("-¥18"), app.buttons["entry-奶茶"].label)
    }

    func testEditEntry() {
        let app = launch()
        let row = app.buttons["entry-午饭"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let amount = app.textFields["金额"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "40")
        app.buttons["保存"].tap()
        let moved = NSPredicate(format: "label CONTAINS '-¥40'")
        XCTAssertTrue(app.buttons.matching(identifier: "entry-午饭").element(matching: moved).waitForExistence(timeout: 3))
    }

    func testSwipeDeleteEntry() {
        let app = launch()
        let row = app.buttons["entry-地铁"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["删除"].tap()
        XCTAssertFalse(app.buttons["entry-地铁"].waitForExistence(timeout: 2))
    }

    func testStatsTab() {
        let app = launch()
        app.buttons["统计"].tap()
        XCTAssertTrue(app.staticTexts["share-餐饮"].waitForExistence(timeout: 3))
    }

    func testOpeningBalance() {
        let app = launch()
        app.buttons["更多"].tap()
        app.buttons["起始余额"].tap()
        let amount = app.textFields["金额"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("1000")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["balance"].waitForExistence(timeout: 3))
    }

    func testScreenshotWithoutAmountNeedsInput() {
        let app = launch(["CRE_DEMO_SCREENSHOT": "noAmount"])
        let save = app.buttons["保存"]
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        XCTAssertFalse(save.isEnabled)
        let amount = app.textFields["金额"]
        amount.tap()
        amount.typeText("20")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS '-¥20'")).firstMatch.waitForExistence(timeout: 3))
    }

    func testDailyChartInStats() {
        let app = launch()
        app.buttons["统计"].tap()
        let chart = app.otherElements["daily-chart"]
        for _ in 0..<5 where !chart.waitForExistence(timeout: 0.5) { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(chart.exists)
    }
}
