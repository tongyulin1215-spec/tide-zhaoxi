import Foundation
import Testing
@testable import CreCore

@Test func trayListsOpenItemsOnce() {
    let today = d(10, 9)
    let now = today.date()
    var data = PlanData()
    let doneID = data.addTodo("寄快递", schedule: .day(today), groupID: nil, tags: [], now: now)!
    data.toggle(todoID: doneID, on: today, today: today, now: now)
    data.addTodo("交周报", schedule: .day(today), groupID: nil, tags: [], now: now)
    let other = data.addGroup("杂事", now: now)
    data.addTodo("交周报", schedule: .day(today), groupID: other, tags: [], now: now)
    let g = data.addGroup("出门", now: now)
    data.updateGroup(g) { $0.todayDisplay = .oneLine }
    data.addTodo("买菜", schedule: .day(today), groupID: g, tags: [], now: now)
    data.addTodo("取钱", schedule: .day(today), groupID: g, tags: [], now: now)

    let titles = trayItems(on: today, today: today, data: data).map(\.title)
    #expect(!titles.contains("寄快递"))
    #expect(titles.filter { $0 == "交周报" }.count == 1)
    #expect(titles.contains("买菜") && titles.contains("取钱"))
    #expect(!titles.contains("出门"))
}

@Test func pastMeansEndedToday() {
    let today = d(10, 9)
    let o = ScheduleOccurrence(itemID: UUID(), day: today, title: "开会", start: 540, end: 600, isRepeating: false, kind: nil)
    #expect(scheduleIsPast(o, minuteNow: 600, today: today))
    #expect(!scheduleIsPast(o, minuteNow: 599, today: today))
    var y = o; y.day = d(10, 8)
    #expect(scheduleIsPast(y, minuteNow: 0, today: today))
    var t = o; t.day = d(10, 10)
    #expect(!scheduleIsPast(t, minuteNow: 1439, today: today))
    #expect(clock(545) == "09:05")
}
