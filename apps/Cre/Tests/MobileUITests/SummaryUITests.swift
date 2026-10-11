import XCTest

/// 总结 on demo data (today pinned to 10/9; demo has the template 本周总结).
final class SummaryUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CRE_DEMO"] = "1"
        app.launchEnvironment["CRE_TODAY"] = "2026-10-09"
        app.launch()
        return app
    }

    func testDailyNoteAutosaves() {
        let app = launch()
        app.tabBars.buttons["总结"].tap()
        let today = app.buttons["day-2026-10-09"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.tap()
        let note = app.textViews["随笔"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.tap()
        note.typeText("状态不错")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["day-2026-10-09"].tap()
        XCTAssertTrue(app.textViews["随笔"].waitForExistence(timeout: 3))
        XCTAssertTrue((app.textViews["随笔"].value as? String ?? "").contains("状态不错"))
    }

    func testTemplateGeneratesReport() {
        let app = launch()
        app.tabBars.buttons["总结"].tap()
        app.buttons["新建"].tap()
        app.buttons["new-summary"].tap()
        let name = app.textFields["名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("周报\n")
        let toggle = app.switches["保存为模板"]
        for _ in 0..<4 where !toggle.isHittable { app.collectionViews.firstMatch.swipeUp(velocity: .slow) }
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["生成"].tap()
        XCTAssertTrue(app.staticTexts["周报"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let template = app.buttons["template-周报"]
        for _ in 0..<6 where !template.waitForExistence(timeout: 0.5) { app.collectionViews.firstMatch.swipeUp(velocity: .slow) }
        XCTAssertTrue(template.exists)
    }

    func testReflectionFromPlanningShowsInSummary() {
        let app = launch()
        app.tabBars.buttons["规划"].tap()
        let item = app.staticTexts["人类简史"]
        for _ in 0..<8 where !item.waitForExistence(timeout: 0.5) || !item.isHittable {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        item.press(forDuration: 1.0)
        app.buttons["写感想"].tap()
        let text = app.textViews["reflection-text"].exists ? app.textViews["reflection-text"] : app.textFields["reflection-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 3))
        text.tap()
        text.typeText("很好看")
        app.buttons["保存"].tap()
        app.tabBars.buttons["总结"].tap()
        XCTAssertTrue(app.buttons["reflection-人类简史"].waitForExistence(timeout: 3))
    }

    func testHomeLongPressMenu() {
        let app = launch()
        let row = app.otherElements["row-交周报"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["移到"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["删除"].exists)
    }

    func testSwipeDeleteSummaryAsks() {
        let app = launch()
        app.tabBars.buttons["总结"].tap()
        let row = app.buttons["day-2026-10-09"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.swipeLeft()
        app.buttons["删除"].tap()
        XCTAssertTrue(app.staticTexts["随笔会保留。"].waitForExistence(timeout: 2))
    }
}
