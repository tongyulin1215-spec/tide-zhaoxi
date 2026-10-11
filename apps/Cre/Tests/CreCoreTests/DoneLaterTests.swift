import Foundation
import Testing
@testable import CreCore

@Test func deadlineDoneLaterShowsDoneOnEarlierDayWithoutCounting() {
    var data = PlanData()
    let id = make("汇报", .deadline(d(10, 4)), created: d(10, 1), into: &data)
    data.toggle(todoID: id, on: d(10, 5), today: d(10, 5), now: d(10, 5).date())

    let past = agenda(for: d(10, 4), today: d(10, 5), data: data)
    let e = past.entries.first { $0.id == id }
    #expect(e?.isDone == true)
    #expect(e?.doneLater == d(10, 5))
    #expect(past.progress == Progress(done: 0, total: 1))

    let s = makeDailySummary(day: d(10, 4), data: data, now: Date())
    #expect(s.done == 0 && s.total == 1)

    let onDay = agenda(for: d(10, 5), today: d(10, 5), data: data).entries.first { $0.id == id }
    #expect(onDay?.isDone == true)
    #expect(onDay?.doneLater == nil)
}
