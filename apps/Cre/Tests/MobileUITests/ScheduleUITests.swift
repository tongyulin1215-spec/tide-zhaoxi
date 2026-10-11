import XCTest

/// 日程 on demo data (today pinned to Friday 10/9; demo has 健身 every Mon/Wed/Fri 19:00–20:30).
final class ScheduleUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CRE_DEMO"] = "1"
        app.launchEnvironment["CRE_TODAY"] = "2026-10-09"
        app.launch()
        app.tabBars.buttons["日程"].tap()
        return app
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    /// Scrolls the timeline until `el` is on screen.
    @discardableResult
    private func reveal(_ el: XCUIElement, in app: XCUIApplication, up: Bool = true) -> XCUIElement {
        for _ in 0..<8 where !el.waitForExistence(timeout: 0.5) || !el.isHittable {
            let s = app.scrollViews["timeline"]
            up ? s.swipeUp(velocity: .slow) : s.swipeDown(velocity: .slow)
        }
        sleep(1)  // let the scroll settle, or the next press only stops it
        return el
    }

    func testTapSlotCreates() {
        let app = launch()
        reveal(app.otherElements["hour-14"], in: app).tap()
        let name = app.textFields["名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText("开会")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.otherElements["block-开会"].waitForExistence(timeout: 3))
    }

    func testDragRepeatingAsksScope() {
        let app = launch()
        let block = reveal(app.otherElements["block-健身"], in: app)
        XCTAssertTrue(block.exists)
        block.press(forDuration: 1.0)  // pick it up
        sleep(1)
        let start = block.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 90)))
        let one = app.buttons["只改这一次"]
        XCTAssertTrue(one.waitForExistence(timeout: 3))
        one.tap()
        let moved = NSPredicate(format: "NOT (label CONTAINS '19:00–20:30')")
        XCTAssertTrue(app.otherElements.matching(identifier: "block-健身").element(matching: moved).waitForExistence(timeout: 3))
        app.otherElements["week-strip"].swipeLeft()
        let next = reveal(app.otherElements["block-健身"], in: app)
        XCTAssertTrue(next.label.contains("19:00"), next.label)
    }

    func testTrayTapThenSlot() {
        let app = launch()
        app.buttons["待办"].tap()
        let card = app.buttons["tray-买香蕉"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.tap()
        reveal(app.otherElements["hour-16"], in: app).tap()
        XCTAssertTrue(app.otherElements["block-买香蕉"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["tray-买香蕉"].label.contains("16:"), app.buttons["tray-买香蕉"].label)
    }

    func testRotationKeepsDay() {
        let app = launch()
        let sunday = app.buttons["day-11"]
        XCTAssertTrue(sunday.waitForExistence(timeout: 3))
        sunday.tap()
        XCTAssertTrue(app.buttons["day-11"].isSelected)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.scrollViews["week-grid"].waitForExistence(timeout: 3))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["day-11"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["day-11"].isSelected)
    }

    func testScrollingOverABlockLeavesItAlone() {
        let app = launch()
        let block = reveal(app.otherElements["block-健身"], in: app)
        XCTAssertTrue(block.label.contains("19:00–20:30"), block.label)
        // A scroll that starts on the block's bottom edge, as a thumb often does.
        let edge = block.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97))
        edge.press(forDuration: 0.05, thenDragTo: edge.withOffset(CGVector(dx: 0, dy: -160)))
        sleep(1)
        XCTAssertFalse(app.buttons["只改这一次"].exists)
        XCTAssertTrue(app.otherElements["block-健身"].label.contains("19:00–20:30"), app.otherElements["block-健身"].label)
    }

    func testSwipeStartingOnABlockScrolls() {
        let app = launch()
        let block = reveal(app.otherElements["block-健身"], in: app)
        let hour = app.otherElements["hour-12"]
        let before = hour.frame.minY
        let mid = block.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        mid.press(forDuration: 0.05, thenDragTo: mid.withOffset(CGVector(dx: 0, dy: 200)))
        sleep(1)
        XCTAssertGreaterThan(hour.frame.minY, before + 100, "the timeline should scroll")
        XCTAssertTrue(app.otherElements["block-健身"].label.contains("19:00–20:30"))
    }

    func testGripChangesTheEnd() {
        let app = launch()
        let block = reveal(app.otherElements["block-健身"], in: app)
        block.press(forDuration: 1.0)
        sleep(1)
        let grip = app.otherElements["grip-end-健身"]
        XCTAssertTrue(grip.waitForExistence(timeout: 2))
        let g = grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        g.press(forDuration: 0.1, thenDragTo: g.withOffset(CGVector(dx: 0, dy: 60)))
        XCTAssertTrue(app.buttons["只改这一次"].waitForExistence(timeout: 3))
    }
}
