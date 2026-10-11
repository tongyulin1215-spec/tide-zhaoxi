import Foundation
import Testing
@testable import CreCore

@Test func groupStartingLaterIsAbsentBefore() {
    var data = PlanData()
    _ = data.addGroup("Apex 练枪", kind: .list(standard: "半小时"), schedule: Repeat(start: d(10, 8)), now: today.date())
    #expect(!texts(agenda(for: d(10, 7), today: today, data: data)).contains { $0.contains("Apex") })
    #expect(texts(agenda(for: d(10, 8), today: today, data: data)).contains { $0.contains("Apex") })
}

@Test func editingGroupCanMoveItsStart() {
    var data = PlanData()
    let g = data.addGroup("Apex 练枪", kind: .list(standard: "半小时"), schedule: Repeat(start: today), now: today.date())
    data.setGroupSchedule(g, kind: .list(standard: "半小时"), rule: Repeat(start: d(10, 8)), now: today.date())
    guard case .repeating(let r)? = data.anchor(of: g)?.schedule else { Issue.record("no anchor"); return }
    #expect(r.start == d(10, 8))
}
