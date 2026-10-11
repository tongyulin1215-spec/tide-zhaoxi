import Foundation

// MARK: - 记账：按天

public struct DayTotals: Identifiable, Equatable, Sendable {
    public var id: DayKey { day }
    public var day: DayKey
    public var income: Int
    public var expense: Int
}

/// Every day of the month with its income and spending (zero days included, for a steady chart).
public func dailyTotals(_ data: LedgerData, year: Int, month: Int) -> [DayTotals] {
    guard var d = DayKey(year: year, month: month, day: 1) else { return [] }
    var out: [DayTotals] = []
    while d.month == month {
        let list = data.entries.filter { $0.day == d }
        out.append(DayTotals(day: d, income: list.filter(\.isIncome).reduce(0) { $0 + $1.amount },
                             expense: list.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }))
        d = d.adding(days: 1)
    }
    return out
}

// MARK: - 免费签名到期

/// The ExpirationDate inside embedded.mobileprovision (a signed blob wrapping a plist).
public func profileExpiry(from blob: Data) -> Date? {
    guard let start = blob.range(of: Data("<?xml".utf8)), let end = blob.range(of: Data("</plist>".utf8), in: start.lowerBound..<blob.endIndex),
          let plist = try? PropertyListSerialization.propertyList(from: blob[start.lowerBound..<end.upperBound], format: nil) as? [String: Any]
    else { return nil }
    return plist["ExpirationDate"] as? Date
}

// MARK: - 首页同步提示

/// Shown on 首页 only when paired, the last try failed, and the last good sync is over 10 minutes old.
public func syncHint(isPaired: Bool, failed: Bool, lastSync: Date?, now: Date) -> String? {
    guard isPaired, failed else { return nil }
    guard let last = lastSync else { return "未连上 Mac" }
    let minutes = Int(now.timeIntervalSince(last) / 60)
    guard minutes >= 10 else { return nil }
    let ago = minutes < 60 ? "\(minutes) 分钟前" : minutes < 1440 ? "\(minutes / 60) 小时前" : "\(minutes / 1440) 天前"
    return "未连上 Mac · 上次同步 \(ago)"
}
