import Foundation
import Testing
@testable import CreCore

private func tempURL() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cre-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("data.json")
}

@Test func emptyTextIsRejected() {
    var data = PlanData()
    #expect(data.addTodo("   ", schedule: .none, groupID: nil, tags: [], now: Date()) == nil)
    #expect(data.todos.isEmpty)
}

@Test func addedTextIsTrimmed() {
    var data = PlanData()
    let id = data.addTodo("  买香蕉 ", schedule: .none, groupID: nil, tags: [], now: Date())
    #expect(id != nil)
    #expect(data.todos.first?.text == "买香蕉")
}

@Test func deletingGroupRemovesItsTodos() {
    var data = PlanData()
    let g = data.addGroup("健身", now: Date())
    _ = data.addTodo("卧推", schedule: .none, groupID: g, tags: [], now: Date())
    _ = data.addTodo("深蹲", schedule: .none, groupID: g, tags: [], now: Date())
    _ = data.addTodo("买香蕉", schedule: .none, groupID: nil, tags: [], now: Date())
    data.deleteGroup(g)
    #expect(data.groups.isEmpty)
    #expect(data.todos.map(\.text) == ["买香蕉"])
}

@Test func setOngoingToggles() {
    var data = PlanData()
    let id = data.addTodo("人类简史", schedule: .none, groupID: nil, tags: [], now: Date())!
    data.setOngoing(id, true)
    #expect(data.todos[0].isOngoing)
}

@Test func saveThenLoad() throws {
    let url = tempURL()
    var data = PlanData()
    let g = data.addGroup("读书", now: Date(timeIntervalSince1970: 1_791_000_000))
    _ = data.addTodo("读书 1 小时", schedule: .repeating(Repeat(start: DayKey(year: 2026, month: 10, day: 5)!)),
                     groupID: g, tags: ["习惯"], now: Date(timeIntervalSince1970: 1_791_000_000))
    let store = PlanStore(fileURL: url)
    try store.save(data)
    #expect(store.load() == data)
}

@Test func corruptFileIsBackedUpNotOverwritten() throws {
    let url = tempURL()
    try "not json".write(to: url, atomically: true, encoding: .utf8)
    let loaded = PlanStore(fileURL: url).load()
    #expect(loaded == PlanData())
    let dir = url.deletingLastPathComponent()
    let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("data.broken-") }
    #expect(backups.count == 1)
    #expect(try String(contentsOf: dir.appendingPathComponent(backups[0]), encoding: .utf8) == "not json")
}

@Test func missingFileGivesEmpty() {
    #expect(PlanStore(fileURL: tempURL()).load() == PlanData())
}

@Test func oldFileWithoutNewFieldsStillLoads() throws {
    let url = tempURL()
    try #"{"todos":[]}"#.write(to: url, atomically: true, encoding: .utf8)
    #expect(PlanStore(fileURL: url).load() == PlanData())
}
