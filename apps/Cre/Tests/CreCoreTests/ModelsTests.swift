import Foundation
import Testing
@testable import CreCore

private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    return try dec.decode(T.self, from: e.encode(value))
}

@Test func scheduleRoundTrips() throws {
    let all: [Schedule] = [
        .none,
        .day(d(10, 8)),
        .deadline(d(10, 20)),
        .span(start: d(10, 5), end: d(10, 11)),
        .repeating(Repeat(weekdays: [2, 4, 6], start: d(10, 5))),
    ]
    for s in all { #expect(try roundTrip(s) == s) }
}

@Test func repeatWithFixedPlanRoundTrips() throws {
    let chest = PlanDay(name: "练胸", weekday: 2, items: [
        PlanItem(text: "卧推 4×8"), PlanItem(text: "上斜哑铃推举 3×10"), PlanItem(text: "飞鸟 3×12"),
    ])
    let back = PlanDay(name: "练背", weekday: 3, items: [PlanItem(text: "引体向上 4×6")])
    var r = Repeat(weekdays: [2, 3, 4, 5, 6, 7], start: d(10, 5), plan: DayPlan(mode: .fixedWeekday, days: [chest, back]))
    r.completions[d(10, 5)] = Date(timeIntervalSince1970: 1_791_000_000)
    r.itemCompletions[d(10, 5)] = [chest.items[0].id]
    #expect(try roundTrip(r) == r)
}
