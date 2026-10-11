import XCTest

/// 规划 on demo data (CRE_DEMO=1, today pinned to 10/9).
final class PlanningUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CRE_DEMO"] = "1"
        app.launchEnvironment["CRE_TODAY"] = "2026-10-09"
        app.launch()
        app.tabBars.buttons["规划"].tap()
        return app
    }

    /// List rows below the fold don't exist until scrolled to.
    @discardableResult
    private func reveal(_ el: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<8 where !el.waitForExistence(timeout: 0.5) || !el.isHittable {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        return el
    }

    func testCollapseCard() {
        let app = launch()
        let header = reveal(app.buttons["card-读书"], in: app)
        XCTAssertTrue(header.exists)
        XCTAssertTrue(reveal(app.staticTexts["人类简史"], in: app).exists)
        header.tap()
        XCTAssertFalse(app.staticTexts["人类简史"].waitForExistence(timeout: 1))
        header.tap()
        XCTAssertTrue(app.staticTexts["人类简史"].waitForExistence(timeout: 2))
    }

    func testInlineAddStaysOpen() {
        let app = launch()
        let add = reveal(app.buttons["add-读书"], in: app)
        XCTAssertTrue(add.exists)
        add.tap()
        app.typeText("球状闪电\n")
        app.typeText("流浪地球\n")
        XCTAssertTrue(app.staticTexts["球状闪电"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["流浪地球"].exists)
    }

    func testNewGroupFlow() {
        let app = launch()
        app.buttons["新建模块组"].tap()
        let name = app.textFields["名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("晨练")
        app.buttons["创建"].tap()
        XCTAssertTrue(reveal(app.buttons["card-晨练"], in: app).exists)
    }

    func testArchiveAndRestore() {
        let app = launch()
        let menu = reveal(app.buttons["menu-读书"], in: app)
        XCTAssertTrue(menu.exists)
        menu.tap()
        app.buttons["归档"].tap()
        XCTAssertFalse(app.buttons["card-读书"].waitForExistence(timeout: 1))
        let archived = reveal(app.buttons["已归档 2"], in: app)
        XCTAssertTrue(archived.exists)
        archived.tap()
        reveal(app.buttons["restore-读书"], in: app).tap()
        app.collectionViews.firstMatch.swipeDown(velocity: .fast)
        XCTAssertTrue(reveal(app.buttons["card-读书"], in: app).exists)
    }

    func testBottomInputAddsLoose() {
        let app = launch()
        let field = app.textFields["记一条零散待办"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("买电池\n")
        XCTAssertTrue(reveal(app.staticTexts["买电池"], in: app).exists)
    }
}
