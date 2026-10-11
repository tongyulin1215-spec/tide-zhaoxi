import Foundation
import Testing
@testable import CreCore

// 1. list groups take a free-text standard
@Test func listStandardIsFreeText() {
    var data = PlanData()
    let g = data.addGroup("对外交流文档学习", kind: .list(standard: "两篇"), schedule: Repeat(start: d(10, 1)), now: Date())
    #expect(data.anchor(of: g)?.text == "对外交流文档学习 两篇")
    #expect(agenda(for: today, today: today, data: data).entries.map(\.text) == ["对外交流文档学习 两篇"])
}

@Test func oldListMinutesDecodeAsStandard() throws {
    let dec = JSONDecoder()
    let k = try dec.decode(GroupKind.self, from: Data(#"{"kind":"list","minutes":90}"#.utf8))
    #expect(k == .list(standard: "1 小时 30 分钟"))
}

// 2. pulled-in far deadlines are folded too
@Test func pulledFarDeadlineIsFolded() {
    var data = PlanData()
    let a = make("交材料", .deadline(d(10, 30)), created: d(10, 6), into: &data) // created after today → not shown by date
    data.update(a) { $0.tags = ["秋招"] }
    let b = make("笔试", .deadline(d(10, 7)), created: d(10, 6), into: &data)
    data.update(b) { $0.tags = ["秋招"] }
    data.pulledTags[today] = ["秋招"]
    let ag = agenda(for: today, today: today, data: data)
    #expect(ag.entries.map(\.text) == ["笔试"])
    #expect(ag.foldedDeadlines.map(\.text) == ["交材料"])
}

// 3. sort by tag
@Test func sortByTagGroupsTagsAlphabeticallyUntaggedLast() {
    var data = PlanData()
    let a = make("无标签", .day(today), into: &data)
    let b = make("秋招项", .day(today), into: &data)
    let c = make("工作项", .day(today), into: &data)
    _ = a
    data.update(b) { $0.tags = ["秋招"] }
    data.update(c) { $0.tags = ["工作"] }
    let order = agenda(for: today, today: today, data: data, sort: .tag).entries.map(\.text)
    #expect(order == ["工作项", "秋招项", "无标签"])
}

// 4. filter by tag or group
@Test func filterByTagAndGroup() {
    var data = PlanData()
    let g = data.addGroup("工作", now: Date())
    _ = make("周报", .day(today), group: g, into: &data)
    let b = make("交材料", .day(today), into: &data)
    data.update(b) { $0.tags = ["秋招"] }
    let far = make("远期", .deadline(d(10, 30)), into: &data)
    data.update(far) { $0.tags = ["秋招"] }
    let all = agenda(for: today, today: today, data: data)
    let byTag = filtered(all, by: .tag("秋招"), data: data)
    #expect(byTag.entries.map(\.text) == ["交材料"])
    #expect(byTag.foldedDeadlines.map(\.text) == ["远期"])
    #expect(byTag.progress == Progress(done: 0, total: 1))
    let byGroup = filtered(all, by: .group(g), data: data)
    #expect(byGroup.entries.map(\.text) == ["周报"])
    #expect(filtered(all, by: .all, data: data).entries.count == 2)
}
