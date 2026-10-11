import XCTest

/// 快速记一条 and the settings defaults (demo data, today pinned to 10/9).
final class QuickAddUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CRE_DEMO"] = "1"
        app.launchEnvironment["CRE_TODAY"] = "2026-10-09"
        app.launch()
        return app
    }

    func testQuickAddURLOpensSheet() {
        let app = launch()
        XCTAssertTrue(app.buttons["pick-day"].waitForExistence(timeout: 5))
        app.open(URL(string: "tide://quickadd")!)
        let field = app.textFields["记一条"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("明天 买牛奶\n")
        XCTAssertFalse(field.waitForExistence(timeout: 1))
        app.buttons["next-day"].tap()
        XCTAssertTrue(app.otherElements["row-买牛奶"].waitForExistence(timeout: 3))
    }

    func testReminderDefaultsOff() {
        let app = launch()
        app.buttons["设置"].tap()
        let toggle = app.switches["每晚提醒"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "0")
    }
}
