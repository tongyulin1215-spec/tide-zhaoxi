import Foundation
import Testing
@testable import CreCore

@Test func dailyTotalsCoverEveryDayOfTheMonth() {
    var l = LedgerData()
    l.add(LedgerEntry(amount: 3500, isIncome: false, category: "餐饮", note: "", day: d(10, 3)), now: Date())
    l.add(LedgerEntry(amount: 600, isIncome: false, category: "交通", note: "", day: d(10, 3)), now: Date())
    l.add(LedgerEntry(amount: 1_200_000, isIncome: true, category: "工资", note: "", day: d(10, 5)), now: Date())
    l.add(LedgerEntry(amount: 999, isIncome: false, category: "餐饮", note: "", day: d(9, 30)), now: Date())
    let days = dailyTotals(l, year: 2026, month: 10)
    #expect(days.count == 31)
    #expect(days[2].day == d(10, 3) && days[2].expense == 4100)
    #expect(days[4].income == 1_200_000 && days[4].expense == 0)
    #expect(days.reduce(0) { $0 + $1.expense } == 4100)
}

@Test func profileExpiryIsReadFromTheEmbeddedPlist() {
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0"><dict><key>ExpirationDate</key><date>2026-10-17T05:30:00Z</date><key>Name</key><string>x</string></dict></plist>
    """
    let blob = Data([0x30, 0x82, 0x01]) + Data(plist.utf8) + Data([0x00, 0xA0])
    let expiry = profileExpiry(from: blob)
    #expect(expiry == ISO8601DateFormatter().date(from: "2026-10-17T05:30:00Z"))
    #expect(profileExpiry(from: Data("junk".utf8)) == nil)
}

@Test func syncHintOnlyWhenTheMacIsOutOfReach() {
    let now = d(10, 10).date(hour: 14)
    #expect(syncHint(isPaired: false, failed: true, lastSync: nil, now: now) == nil)
    #expect(syncHint(isPaired: true, failed: false, lastSync: now.addingTimeInterval(-7200), now: now) == nil)
    #expect(syncHint(isPaired: true, failed: true, lastSync: now.addingTimeInterval(-120), now: now) == nil)
    #expect(syncHint(isPaired: true, failed: true, lastSync: now.addingTimeInterval(-3 * 3600), now: now) == "未连上 Mac · 上次同步 3 小时前")
    #expect(syncHint(isPaired: true, failed: true, lastSync: now.addingTimeInterval(-25 * 60), now: now) == "未连上 Mac · 上次同步 25 分钟前")
    #expect(syncHint(isPaired: true, failed: true, lastSync: now.addingTimeInterval(-3 * 86400), now: now) == "未连上 Mac · 上次同步 3 天前")
    #expect(syncHint(isPaired: true, failed: true, lastSync: nil, now: now) == "未连上 Mac")
}
