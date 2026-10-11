import Foundation
import Testing
@testable import CreCore

private func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cre-w-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

// W1
@Test func migrationCopiesOnce() throws {
    let legacy = tempDir().appendingPathComponent("data.json")
    let shared = tempDir().appendingPathComponent("data.json")
    try "{\"todos\":[]}".write(to: legacy, atomically: true, encoding: .utf8)
    #expect(migrateLegacyData(from: legacy, to: shared))
    #expect(FileManager.default.fileExists(atPath: shared.path))
    #expect(!FileManager.default.fileExists(atPath: legacy.path))
    #expect(FileManager.default.fileExists(atPath: legacy.deletingLastPathComponent().appendingPathComponent("data.migrated.json").path))
    #expect(!migrateLegacyData(from: legacy, to: shared))
}

@Test func migrationNeverOverwrites() throws {
    let legacy = tempDir().appendingPathComponent("data.json")
    let shared = tempDir().appendingPathComponent("data.json")
    try "legacy".write(to: legacy, atomically: true, encoding: .utf8)
    try "shared".write(to: shared, atomically: true, encoding: .utf8)
    #expect(!migrateLegacyData(from: legacy, to: shared))
    #expect(try String(contentsOf: shared, encoding: .utf8) == "shared")
    #expect(try String(contentsOf: legacy, encoding: .utf8) == "legacy")
}

@Test func migrationWithoutLegacyDoesNothing() {
    let shared = tempDir().appendingPathComponent("data.json")
    #expect(!migrateLegacyData(from: tempDir().appendingPathComponent("data.json"), to: shared))
    #expect(!FileManager.default.fileExists(atPath: shared.path))
}

// W2
@Test func widgetPrefersHighPriority() {
    var data = PlanData()
    for (i, p) in [Priority?.none, .p2, .p0, nil, .p1].enumerated() {
        let id = make("事\(i)", .day(today), into: &data)
        data.update(id) { $0.priority = p }
    }
    let w = widgetContent(today: today, data: data, limit: 3)
    #expect(w.open.map(\.text) == ["事2", "事4", "事1"])
    #expect(w.progress == Progress(done: 0, total: 5))
}

@Test func widgetCountsFoldedAndDone() {
    var data = PlanData()
    _ = make("远期", .deadline(d(10, 30)), into: &data)
    let done = make("已做", .day(today), into: &data)
    data.toggle(todoID: done, on: today, now: Date())
    let w = widgetContent(today: today, data: data, limit: 6)
    #expect(w.folded == 1)
    #expect(w.done.map(\.text) == ["已做"])
    #expect(w.open.isEmpty)
}

// W3
@Test func externalChangeIsDetected() throws {
    let url = tempDir().appendingPathComponent("data.json")
    let app = PlanStore(fileURL: url)
    var data = PlanData()
    _ = data.addTodo("A", schedule: .none, groupID: nil, tags: [], now: Date())
    try app.save(data)
    #expect(app.loadIfChanged() == nil)
    // Another process (the widget) writes the file.
    Thread.sleep(forTimeInterval: 0.02)
    var other = PlanStore(fileURL: url).load()
    _ = other.addTodo("B", schedule: .none, groupID: nil, tags: [], now: Date())
    try PlanStore(fileURL: url).save(other)
    #expect(app.loadIfChanged()?.todos.map(\.text) == ["A", "B"])
    #expect(app.loadIfChanged() == nil)
}

@Test func ownSaveIsNotExternal() throws {
    let url = tempDir().appendingPathComponent("data.json")
    let app = PlanStore(fileURL: url)
    _ = app.load()
    try app.save(PlanData())
    try app.save(PlanData())
    #expect(app.loadIfChanged() == nil)
}

// W4
@Test func timelineRefreshesAtMidnight() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 22, minute: 30))!
    let next = nextRefresh(after: now, calendar: cal)
    #expect(cal.dateComponents([.year, .month, .day, .hour, .minute], from: next) ==
            DateComponents(year: 2026, month: 10, day: 5, hour: 0, minute: 0))
}
