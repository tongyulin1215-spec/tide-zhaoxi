import Foundation
import Testing
@testable import CreCore

@Test func priorityParsed() {
    let r = parseInput("p0 交报告 ddl 10月12日", today: today)
    #expect(r.text == "交报告")
    #expect(r.schedule == .deadline(d(10, 12)))
    #expect(r.priority == .p0)
}

@Test func priorityAnywhereAndAnyCase() {
    #expect(parseInput("交报告 P2", today: today).priority == .p2)
    #expect(parseInput("交报告 P2", today: today).text == "交报告")
}

@Test func p0InsideWordIgnored() {
    let r = parseInput("top0 计划", today: today)
    #expect(r.priority == nil)
    #expect(r.text == "top0 计划")
}

private func prioritized(_ data: inout PlanData, _ text: String, _ s: Schedule, _ p: Priority?, created: DayKey = d(10, 1)) {
    let id = make(text, s, created: created, into: &data)
    data.update(id) { $0.priority = p }
}

@Test func sortByPriorityPutsNoneLast() {
    var data = PlanData()
    prioritized(&data, "无", .day(today), nil)
    prioritized(&data, "P2", .day(today), .p2)
    prioritized(&data, "P0 重复", .repeating(Repeat(start: d(10, 1))), .p0)
    prioritized(&data, "P1 截止", .deadline(d(10, 6)), .p1)
    #expect(texts(agenda(for: today, today: today, data: data, sort: .priority)) == ["P0 重复", "P1 截止", "P2", "无"])
}

@Test func sortByCategoryGroupsKinds() {
    var data = PlanData()
    prioritized(&data, "某天 P2", .day(today), .p2)
    prioritized(&data, "重复 P0", .repeating(Repeat(start: d(10, 1))), .p0)
    prioritized(&data, "截止", .deadline(d(10, 6)), nil)
    prioritized(&data, "某天 P0", .day(today), .p0, created: d(10, 2))
    #expect(texts(agenda(for: today, today: today, data: data, sort: .category)) == ["截止", "某天 P0", "某天 P2", "重复 P0"])
}

@Test func entryCarriesPriority() {
    var data = PlanData()
    prioritized(&data, "交表", .day(today), .p1)
    #expect(agenda(for: today, today: today, data: data).entries[0].priority == .p1)
}

@Test func oldFileWithoutPriorityLoads() throws {
    let json = #"{"id":"6E6790BC-4504-4244-A262-0EC5211FACD4","text":"x","tags":[],"schedule":{"kind":"none"},"isOngoing":false,"createdAt":"2026-10-01T04:00:00Z"}"#
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    let t = try dec.decode(Todo.self, from: Data(json.utf8))
    #expect(t.priority == nil)
}
