import Foundation

/// 一笔收支。金额以"分"存储。
public struct LedgerEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var amount: Int
    public var isIncome: Bool
    public var category: String
    public var note: String
    public var day: DayKey
    public var createdAt: Date
    /// Last change, for sync.
    public var modifiedAt: Date? = nil

    public init(id: UUID = UUID(), amount: Int, isIncome: Bool, category: String, note: String,
                day: DayKey, createdAt: Date = Date()) {
        self.id = id
        self.amount = amount
        self.isIncome = isIncome
        self.category = category
        self.note = note
        self.day = day
        self.createdAt = createdAt
    }
}

/// 起始结余：this much money on `day`; entries from that day on move it.
public struct OpeningBalance: Codable, Equatable, Sendable {
    public var amount: Int
    public var day: DayKey

    public init(amount: Int, day: DayKey) {
        self.amount = amount
        self.day = day
    }
}

public struct LedgerData: StoredValue, Sendable {
    public static let presetExpense = ["餐饮", "交通", "购物", "居住", "娱乐", "医疗", "其他"]
    public static let presetIncome = ["工资", "奖金", "其他"]

    public var version = 1
    public var entries: [LedgerEntry] = []
    public var expenseCategories = LedgerData.presetExpense
    public var incomeCategories = LedgerData.presetIncome
    public var opening: OpeningBalance?
    /// Sync bookkeeping: deleted entries ("entry:<uuid>"), the last change to the categories, and to the opening balance.
    public var deletions: [String: Date] = [:]
    public var settingsModifiedAt: Date?
    public var openingModifiedAt: Date?

    public init() {}

    private enum Keys: String, CodingKey { case version, entries, expenseCategories, incomeCategories, opening, deletions, settingsModifiedAt, openingModifiedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        entries = try c.decodeIfPresent([LedgerEntry].self, forKey: .entries) ?? []
        expenseCategories = try c.decodeIfPresent([String].self, forKey: .expenseCategories) ?? Self.presetExpense
        incomeCategories = try c.decodeIfPresent([String].self, forKey: .incomeCategories) ?? Self.presetIncome
        opening = try c.decodeIfPresent(OpeningBalance.self, forKey: .opening)
        deletions = try c.decodeIfPresent([String: Date].self, forKey: .deletions) ?? [:]
        settingsModifiedAt = try c.decodeIfPresent(Date.self, forKey: .settingsModifiedAt)
        openingModifiedAt = try c.decodeIfPresent(Date.self, forKey: .openingModifiedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(version, forKey: .version)
        try c.encode(entries, forKey: .entries)
        try c.encode(expenseCategories, forKey: .expenseCategories)
        try c.encode(incomeCategories, forKey: .incomeCategories)
        try c.encodeIfPresent(opening, forKey: .opening)
        if !deletions.isEmpty { try c.encode(deletions, forKey: .deletions) }
        try c.encodeIfPresent(settingsModifiedAt, forKey: .settingsModifiedAt)
        try c.encodeIfPresent(openingModifiedAt, forKey: .openingModifiedAt)
    }

    /// Money on hand at the end of `day`; nil before a starting balance is set or before its day.
    public func balance(asOf day: DayKey) -> Int? {
        guard let opening, opening.day <= day else { return nil }
        return entries.filter { $0.day >= opening.day && $0.day <= day }
            .reduce(opening.amount) { $0 + ($1.isIncome ? $1.amount : -$1.amount) }
    }

    public func categories(income: Bool) -> [String] { income ? incomeCategories : expenseCategories }

    public mutating func add(_ entry: LedgerEntry, now: Date) {
        var e = entry
        e.createdAt = now
        entries.append(e)
    }

    public mutating func update(_ id: UUID, _ change: (inout LedgerEntry) -> Void) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[i])
    }

    public mutating func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public mutating func addCategory(_ name: String, income: Bool) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !categories(income: income).contains(n) else { return }
        if income { incomeCategories.append(n) } else { expenseCategories.append(n) }
    }

    /// Removes a category from the list; existing entries keep their category name.
    public mutating func removeCategory(_ name: String, income: Bool) {
        if income { incomeCategories.removeAll { $0 == name } } else { expenseCategories.removeAll { $0 == name } }
    }

    /// Renames a category in the list and on its entries.
    public mutating func renameCategory(_ old: String, to new: String, income: Bool) {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard old != "其他", !n.isEmpty, !categories(income: income).contains(n) else { return }
        if income {
            incomeCategories = incomeCategories.map { $0 == old ? n : $0 }
        } else {
            expenseCategories = expenseCategories.map { $0 == old ? n : $0 }
        }
        for i in entries.indices where entries[i].isIncome == income && entries[i].category == old {
            entries[i].category = n
        }
    }
}

public typealias LedgerStore = DataStore<LedgerData>

extension DataStore where Value == LedgerData {
    /// `ledger.json` in the App Group container.
    public static func sharedURL(groupID: String = appGroupID) -> URL? {
        sharedFileURL("ledger.json", groupID: groupID)
    }
}

// MARK: - One-line entry

public struct ParsedLedger: Equatable, Sendable {
    public var amount: Int
    public var isIncome: Bool
    public var category: String
    public var note: String
    public var day: DayKey
}

private let amountRe = try! NSRegularExpression(pattern: #"(?<![\d.,])([+＋])?(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?(?![\d.,])"#)
private let monthDayRe = try! NSRegularExpression(pattern: #"(\d{1,2})月(\d{1,2})[日号]?"#)

private let expenseKeywords: [(String, [String])] = [
    ("餐饮", ["早饭", "午饭", "晚饭", "早餐", "午餐", "晚餐", "外卖", "咖啡", "奶茶", "饭", "餐", "面", "零食", "水果", "夜宵", "火锅", "饮料", "食堂"]),
    ("交通", ["地铁", "公交", "打车", "滴滴", "出租", "加油", "停车", "高铁", "火车", "机票", "飞机", "单车", "过路费"]),
    ("居住", ["房租", "水电", "电费", "水费", "燃气", "物业", "宽带", "话费"]),
    ("娱乐", ["电影", "游戏", "KTV", "会员", "演唱会", "旅游", "门票", "唱歌"]),
    ("医疗", ["药", "医院", "挂号", "体检", "看病", "牙"]),
    ("购物", ["淘宝", "京东", "拼多多", "衣服", "鞋", "超市", "日用", "买"]),
]

private let incomeKeywords: [(String, [String])] = [
    ("工资", ["工资", "薪"]),
    ("奖金", ["奖金", "年终", "绩效"]),
]

/// Reads "午饭 35", "工资 +12000", "收入 奖金 3000", "昨天 打车 23.5". The last number is the amount.
public func parseLedger(_ raw: String, today: DayKey, data: LedgerData) -> ParsedLedger? {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return nil }

    var day = today
    for (word, offset) in [("前天", -2), ("昨天", -1), ("今天", 0)] where s.contains(word) {
        day = today.adding(days: offset)
        s = s.replacingOccurrences(of: word, with: " ")
        break
    }
    if let m = monthDayRe.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
       let mo = Range(m.range(at: 1), in: s).flatMap({ Int(s[$0]) }),
       let da = Range(m.range(at: 2), in: s).flatMap({ Int(s[$0]) }) {
        if var d = DayKey(year: today.year, month: mo, day: da) {
            if d > today, let last = DayKey(year: today.year - 1, month: mo, day: da) { d = last }
            day = d
        }
        // An impossible date ("2月30日") is dropped rather than read as an amount.
        s.replaceSubrange(Range(m.range, in: s)!, with: " ")
    }
    s = s.replacingOccurrences(of: #"(\d)，(\d{3})"#, with: "$1,$2", options: .regularExpression)
    s = s.replacingOccurrences(of: #"(\d)\.(?!\d)"#, with: "$1", options: .regularExpression)

    // "35块5" / "35元5角" / "35块5毛" → "35.5"; "3块" → "3".
    s = s.replacingOccurrences(of: #"(\d+)\s*[块元]\s*(\d)\s*[毛角]?"#, with: "$1.$2", options: .regularExpression)
    s = s.replacingOccurrences(of: #"(\d+)\s*[块元]"#, with: "$1", options: .regularExpression)

    guard let m = amountRe.matches(in: s, range: NSRange(s.startIndex..., in: s)).last,
          let intPart = Range(m.range(at: 2), in: s).map({ s[$0].replacingOccurrences(of: ",", with: "") }),
          let yuan = Int(intPart), yuan <= maxYuan else { return nil }
    let fraction = Range(m.range(at: 3), in: s).map { String(s[$0]) } ?? ""
    let cents = fraction.isEmpty ? 0 : Int(fraction.count == 1 ? fraction + "0" : fraction)!
    let amount = yuan * 100 + cents
    guard amount > 0 else { return nil }
    var isIncome = Range(m.range(at: 1), in: s) != nil
    s.replaceSubrange(Range(m.range, in: s)!, with: " ")

    if s.contains("收入") {
        isIncome = true
        s = s.replacingOccurrences(of: "收入", with: " ")
    }
    let note = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    if !isIncome, data.incomeCategories.contains(where: { $0 != "其他" && note == $0 }) { isIncome = true }

    let category = guessCategory(note: note, isIncome: isIncome, data: data)
    return ParsedLedger(amount: amount, isIncome: isIncome, category: category,
                        note: note.isEmpty ? category : note, day: day)
}

/// Same note as before → that category; else keywords; else a category with the note's name; else 其他.
public func guessCategory(note: String, isIncome: Bool, data: LedgerData) -> String {
    let list = data.categories(income: isIncome)
    if let last = data.entries.filter({ $0.note == note && $0.isIncome == isIncome })
        .max(by: { $0.createdAt < $1.createdAt }), list.contains(last.category) {
        return last.category
    }
    for (category, words) in (isIncome ? incomeKeywords : expenseKeywords) where list.contains(category) {
        if words.contains(where: { note.localizedCaseInsensitiveContains($0) }) { return category }
    }
    if list.contains(note) { return note }
    return list.contains("其他") ? "其他" : (list.first ?? "其他")
}

/// Amounts above this are treated as not-an-amount (order numbers, typos), never as money.
public let maxYuan = 100_000_000

/// The form's amount field: "35", "23.5", "1,200" → cents; nil for zero, non-numbers or absurd values.
public func parseAmount(_ text: String) -> Int? {
    let t = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
    guard t.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil,
          let v = Double(t), v.isFinite, v > 0, v <= Double(maxYuan) else { return nil }
    return Int((v * 100).rounded())
}

/// "¥35", "¥23.50", "¥12,000".
public func money(_ cents: Int) -> String {
    let f = cents % 100 == 0 ? wholeFormatter : centsFormatter
    return "¥" + (f.string(from: NSNumber(value: Double(cents) / 100)) ?? "\(cents / 100)")
}

private func moneyFormatter(fraction: Int) -> NumberFormatter {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.numberStyle = .decimal
    f.usesGroupingSeparator = true
    f.groupingSeparator = ","
    f.groupingSize = 3
    f.minimumFractionDigits = fraction
    f.maximumFractionDigits = fraction
    return f
}

nonisolated(unsafe) private let wholeFormatter = moneyFormatter(fraction: 0)
nonisolated(unsafe) private let centsFormatter = moneyFormatter(fraction: 2)

// MARK: - Totals

public struct MonthTotals: Equatable, Sendable {
    public var income: Int
    public var expense: Int
    /// 净收入
    public var net: Int { income - expense }

    public init(income: Int, expense: Int) {
        self.income = income
        self.expense = expense
    }
}

private func totals(_ entries: [LedgerEntry]) -> MonthTotals {
    MonthTotals(income: entries.filter(\.isIncome).reduce(0) { $0 + $1.amount },
                expense: entries.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount })
}

public func monthTotals(_ data: LedgerData, year: Int, month: Int) -> MonthTotals {
    totals(data.entries.filter { $0.day.year == year && $0.day.month == month })
}

public struct DayGroup: Identifiable, Sendable {
    public var id: DayKey { day }
    public var day: DayKey
    public var entries: [LedgerEntry]
    public var income: Int
    public var expense: Int
}

/// Entries grouped by day, newest day first; within a day newest entry first.
public func dayGroups(_ entries: [LedgerEntry]) -> [DayGroup] {
    Dictionary(grouping: entries, by: \.day)
        .map { day, list in
            let t = totals(list)
            return DayGroup(day: day, entries: list.sorted { $0.createdAt > $1.createdAt }, income: t.income, expense: t.expense)
        }
        .sorted { $0.day > $1.day }
}

public struct CategoryAmount: Identifiable, Equatable, Sendable {
    public var id: String { category }
    public var category: String
    public var amount: Int
}

public func categoryShare(_ data: LedgerData, year: Int, month: Int, income: Bool) -> [CategoryAmount] {
    share(data.entries.filter { $0.isIncome == income && $0.day.year == year && $0.day.month == month })
}

/// Category totals for entries dated within `from...to`, largest first.
public func categoryShare(_ data: LedgerData, from: DayKey, to: DayKey, income: Bool) -> [CategoryAmount] {
    share(data.entries.filter { $0.isIncome == income && from <= $0.day && $0.day <= to })
}

private func share(_ entries: [LedgerEntry]) -> [CategoryAmount] {
    Dictionary(grouping: entries, by: \.category)
        .map { CategoryAmount(category: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
        .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.category < $1.category }
}

public struct MonthPoint: Identifiable, Sendable {
    public var id: String { "\(year)-\(month)" }
    public var year: Int
    public var month: Int
    public var totals: MonthTotals
}

/// The `months` months ending with year/month, oldest first.
public func monthlyTrend(_ data: LedgerData, endingYear: Int, month: Int, months: Int) -> [MonthPoint] {
    (0..<months).reversed().map { back in
        var y = endingYear, m = month - back
        while m < 1 { m += 12; y -= 1 }
        return MonthPoint(year: y, month: m, totals: monthTotals(data, year: y, month: m))
    }
}
