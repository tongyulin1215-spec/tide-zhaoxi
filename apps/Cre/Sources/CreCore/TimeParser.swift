import Foundation

public struct ParsedInput: Equatable, Sendable {
    public var text: String
    public var schedule: Schedule
    public var priority: Priority?
    public var tags: [String]

    public init(text: String, schedule: Schedule, priority: Priority? = nil, tags: [String] = []) {
        self.text = text
        self.schedule = schedule
        self.priority = priority
        self.tags = tags
    }
}

/// Reads a time out of one line of input ("买香蕉 ddl 10月8日", "学习 10.5–10.11", "健身 每周一三五")
/// and returns the remaining text plus the schedule. Unrecognized input keeps `.none` and its text unchanged.
public func parseInput(_ raw: String, today: DayKey) -> ParsedInput {
    var s = chineseNumeralDates(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    var priority: Priority?
    // "优先级p1" / "优先级：P0" / "优先级1" first, so the word itself goes too; then a bare "p1".
    for re in [priorityWordRe, priorityRe] {
        if priority == nil, let m = matches(re, s).first, let digit = group(m, 1, in: s), let n = Int(digit) {
            priority = Priority(rawValue: n)
            s = strip(s, Range(m.range, in: s)!)
        }
    }
    var tags: [String] = []
    while let m = matches(tagRe, s).first, let tag = group(m, 1, in: s) {
        if !tags.contains(tag) { tags.append(tag) }
        s = strip(s, Range(m.range, in: s)!)
    }
    var result = parseTime(s, today: today)
    result.priority = priority
    result.tags = tags
    result.text = tidy(result.text)
    return result
}

/// Drops punctuation left at the ends after times were taken out, and doubled separators.
private func tidy(_ s: String) -> String {
    var t = s.replacingOccurrences(of: #"\s*([，,。；;])\s*(?:[，,。；;]\s*)+"#, with: "$1", options: .regularExpression)
    t = t.trimmingCharacters(in: CharacterSet(charactersIn: " ，,。、；;：:"))
    return t
}

private let cnDigits: [Character: Int] = ["一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]

/// 一…三十一 → 1…31 (nil if it isn't one).
private func cnNumber(_ s: String) -> Int? {
    let c = Array(s)
    switch c.count {
    case 1: return c[0] == "十" ? 10 : cnDigits[c[0]]
    case 2:
        if c[0] == "十" { return cnDigits[c[1]].map { 10 + $0 } }
        if c[1] == "十" { return cnDigits[c[0]].map { $0 * 10 } }
        return nil
    case 3:
        guard c[1] == "十", let a = cnDigits[c[0]], let b = cnDigits[c[2]] else { return nil }
        return a * 10 + b
    default: return nil
    }
}

/// "十月八号" → "10月8号".
private func chineseNumeralDates(_ s: String) -> String {
    let re = try! NSRegularExpression(pattern: #"([一二两三四五六七八九十]{1,3})月([一二两三四五六七八九十]{1,3})([日号])"#)
    var out = s
    for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
        guard let a = Range(m.range(at: 1), in: s).flatMap({ cnNumber(String(s[$0])) }),
              let b = Range(m.range(at: 2), in: s).flatMap({ cnNumber(String(s[$0])) }),
              let suffix = Range(m.range(at: 3), in: s).map({ String(s[$0]) }),
              let whole = Range(m.range, in: out) else { continue }
        out.replaceSubrange(whole, with: "\(a)月\(b)\(suffix)")
    }
    return out
}

private func parseTime(_ s: String, today: DayKey) -> ParsedInput {
    if let m = matches(nextWeekRangeRe, s).first, let a = group(m, 1, in: s)?.first, let b = group(m, 2, in: s)?.first {
        let start = nextWeekDay(weekday(a), today: today)
        var end = nextWeekDay(weekday(b), today: today)
        if end < start { end = end.adding(days: 7) }
        return ParsedInput(text: strip(s, Range(m.range, in: s)!), schedule: .span(start: start, end: end))
    }
    if let (range, weekdays) = matchRepeat(in: s) {
        var rest = strip(s, range)
        var start = today
        // "从10.8开始，每天…" / "每天…，10月8日起": the repeat begins that day.
        if let (dr, day) = matchDate(in: rest, today: today), let widened = startKeyword(around: dr, in: rest) {
            start = day
            rest = strip(rest, widened)
        }
        return ParsedInput(text: rest, schedule: .repeating(Repeat(weekdays: weekdays, start: start)))
    }
    if let (range, start, end) = matchSpan(in: s, today: today) {
        return ParsedInput(text: strip(s, range), schedule: .span(start: start, end: end))
    }
    if let (range, day) = matchDate(in: s, today: today) {
        if let widened = startKeyword(around: range, in: s) {
            return ParsedInput(text: strip(s, widened), schedule: .day(day))
        }
        if let widened = deadlineKeyword(around: range, in: s) {
            return ParsedInput(text: strip(s, widened), schedule: .deadline(day))
        }
        return ParsedInput(text: strip(s, range), schedule: .day(day))
    }
    return ParsedInput(text: s, schedule: .none)
}

// MARK: - Patterns

private let units = "页|元|块|斤|个|次|公里|km|kg|%|小时|分钟|分|岁|cm|米|楼|号线"
private let datePart = #"(?:(\d{1,2})月(\d{1,2})[日号]?|(\d{1,2})[./](\d{1,2})(?![\d.])(?![A-Za-z倍点%])(?!\s*(?:"# + units + #")))"#
private let dateRe = try! NSRegularExpression(pattern: #"(?<![\d.])"# + datePart)
private let spanRe = try! NSRegularExpression(pattern: #"(?<![\d.])"# + datePart + #"\s*[-–—~至到]\s*"# + datePart)
private let relativeRe = try! NSRegularExpression(pattern: #"今天|今晚|明天|后天|下(?:周|星期)([一二三四五六日天])|(?<![每下])(?:周|星期)([一二三四五六日天])"#)
private let nextWeekRangeRe = try! NSRegularExpression(pattern: #"下周([一二三四五六日天])\s*(?:到|至|-|–|~)\s*周?([一二三四五六日天])"#)
private let rangeRe = try! NSRegularExpression(pattern: #"(?<!下)每?周([一二三四五六日天])\s*(?:到|至|-|–|~)\s*周?([一二三四五六日天])"#)
private let listRe = try! NSRegularExpression(pattern: #"每周([一二三四五六日天]+)"#)
private let priorityRe = try! NSRegularExpression(pattern: #"(?i)(?<![A-Za-z0-9])p([0-2])(?![A-Za-z0-9])"#)
/// A tag runs until whitespace, punctuation, another tag, or a time / priority word ("开会#工作明天" → 工作).
private let priorityWordRe = try! NSRegularExpression(pattern: #"优先级\s*[:：是为]?\s*[pP]?([0-2])(?![0-9])"#)
private let tagRe = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9])[#＃]([^\s#＃，。,.!?！？、；;:：]+?)(?=$|[\s#＃，。,.!?！？、；;:：]|今天|明天|后天|下周|每天|每日|每周|周[一二三四五六日天]|(?i:ddl)|截止|\d|[pP][0-2])"#)
private let dailyRe = try! NSRegularExpression(pattern: #"每天|每日"#)
private let ddlBeforeRe = try! NSRegularExpression(pattern: #"(?i)(?:ddl|deadline|截止日期|截止到|截止|截至)\s*[:：]?\s*$"#)
private let ddlAfterRe = try! NSRegularExpression(pattern: #"(?i)^\s*(?:之前|以前|前|截止|到期|ddl)"#)

/// 一→2 … 六→7, 日/天→1 (Calendar weekday numbering).
private func weekday(_ c: Character) -> Int {
    switch c {
    case "一": 2
    case "二": 3
    case "三": 4
    case "四": 5
    case "五": 6
    case "六": 7
    default: 1
    }
}

private func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String? {
    guard let r = Range(m.range(at: i), in: s) else { return nil }
    return String(s[r])
}

/// Month/day without a year: this year, or next year when it is already past.
private func resolve(month: Int, day: Int, today: DayKey) -> DayKey? {
    guard let this = DayKey(year: today.year, month: month, day: day) else { return nil }
    return this < today ? DayKey(year: today.year + 1, month: month, day: day) : this
}

/// The dot form ("10.8") is only taken as a date this close to today, since decimals look the same.
private let dotWindow = -30...90

/// Date groups start at `base` (four groups per date: 月-form month/day, dot-form month/day).
/// Returns month/day and whether it was the dot form.
private func monthDay(_ m: NSTextCheckingResult, base: Int, in s: String) -> (Int, Int, Bool)? {
    if let mo = group(m, base, in: s), let da = group(m, base + 1, in: s), let mm = Int(mo), let dd = Int(da) {
        return (mm, dd, false)
    }
    if let mo = group(m, base + 2, in: s), let da = group(m, base + 3, in: s), let mm = Int(mo), let dd = Int(da) {
        return (mm, dd, true)
    }
    return nil
}

private func date(_ m: NSTextCheckingResult, base: Int, in s: String, today: DayKey) -> DayKey? {
    guard let (mm, dd, dot) = monthDay(m, base: base, in: s) else { return nil }
    guard dot else { return resolve(month: mm, day: dd, today: today) }
    for year in [today.year, today.year + 1] {
        if let d = DayKey(year: year, month: mm, day: dd), dotWindow.contains(today.days(until: d)) { return d }
    }
    return nil
}

private func matches(_ re: NSRegularExpression, _ s: String) -> [NSTextCheckingResult] {
    re.matches(in: s, range: NSRange(s.startIndex..., in: s))
}

// MARK: - Matchers

private func matchRepeat(in s: String) -> (Range<String.Index>, Set<Int>)? {
    if let m = matches(rangeRe, s).first, let a = group(m, 1, in: s)?.first, let b = group(m, 2, in: s)?.first {
        var days: Set<Int> = []
        var w = weekday(a)
        while true {
            days.insert(w)
            if w == weekday(b) { break }
            w = w % 7 + 1
        }
        return (Range(m.range, in: s)!, days)
    }
    if let m = matches(listRe, s).first, let chars = group(m, 1, in: s) {
        return (Range(m.range, in: s)!, Set(chars.map(weekday)))
    }
    if let m = matches(dailyRe, s).first {
        return (Range(m.range, in: s)!, [])
    }
    return nil
}

private func matchSpan(in s: String, today: DayKey) -> (Range<String.Index>, DayKey, DayKey)? {
    for m in matches(spanRe, s) {
        guard let (sm, sd, _) = monthDay(m, base: 1, in: s), let (em, ed, _) = monthDay(m, base: 5, in: s),
              var start = DayKey(year: today.year, month: sm, day: sd),
              var end = DayKey(year: today.year, month: em, day: ed) else { continue }
        // A span crossing New Year: the end is next year — or, typed in January, the start was last year.
        if end < start {
            if today.month <= 6, let lastYear = DayKey(year: today.year - 1, month: sm, day: sd) {
                start = lastYear
            } else if let next = DayKey(year: today.year + 1, month: em, day: ed) {
                end = next
            }
        }
        // Only a span that is entirely over moves to next year; one under way stays.
        if end < today, let s2 = DayKey(year: start.year + 1, month: sm, day: sd),
           let e2 = DayKey(year: end.year + 1, month: em, day: ed) {
            start = s2
            end = e2
        }
        return (Range(m.range, in: s)!, start, end)
    }
    return nil
}

private func matchDate(in s: String, today: DayKey) -> (Range<String.Index>, DayKey)? {
    for m in matches(dateRe, s) {
        if let day = date(m, base: 1, in: s, today: today) {
            return (Range(m.range, in: s)!, day)
        }
    }
    if let m = matches(relativeRe, s).first {
        let token = group(m, 0, in: s)!
        let day: DayKey
        switch token {
        case "今天", "今晚": day = today
        case "明天": day = today.adding(days: 1)
        case "后天": day = today.adding(days: 2)
        default:
            if let w = group(m, 1, in: s)?.first {
                day = nextWeekDay(weekday(w), today: today)
            } else {
                // "周五": the coming one (today counts).
                let target = weekday(group(m, 2, in: s)!.first!)
                day = today.adding(days: (target - today.weekday + 7) % 7)
            }
        }
        return (Range(m.range, in: s)!, day)
    }
    return nil
}

/// Widens a date's range to include an adjacent "ddl" / "截止", or nil when there is none.
private func deadlineKeyword(around range: Range<String.Index>, in s: String) -> Range<String.Index>? {
    let before = String(s[..<range.lowerBound])
    if let m = matches(ddlBeforeRe, before).first, let r = Range(m.range, in: before) {
        let lower = s.index(s.startIndex, offsetBy: before.distance(from: before.startIndex, to: r.lowerBound))
        return lower..<range.upperBound
    }
    let after = String(s[range.upperBound...])
    if let m = matches(ddlAfterRe, after).first, let r = Range(m.range, in: after) {
        let upper = s.index(range.upperBound, offsetBy: after.distance(from: after.startIndex, to: r.upperBound))
        return range.lowerBound..<upper
    }
    return nil
}

private let startBeforeRe = try! NSRegularExpression(pattern: #"(?:从|自)\s*$"#)
// 起 alone, not 起床 / 起来 / 起飞 …
private let startAfterRe = try! NSRegularExpression(pattern: #"^\s*(?:开始|起(?![床来飞身草码诉步早]))"#)

/// The date widened over "从 … 开始" / "… 起" around it; nil when neither word is there.
private func startKeyword(around range: Range<String.Index>, in s: String) -> Range<String.Index>? {
    var lower = range.lowerBound, upper = range.upperBound
    let before = String(s[..<range.lowerBound])
    if let m = matches(startBeforeRe, before).first, let r = Range(m.range, in: before) {
        lower = s.index(s.startIndex, offsetBy: before.distance(from: before.startIndex, to: r.lowerBound))
    }
    let after = String(s[range.upperBound...])
    if let m = matches(startAfterRe, after).first, let r = Range(m.range, in: after) {
        upper = s.index(range.upperBound, offsetBy: after.distance(from: after.startIndex, to: r.upperBound))
    }
    return lower == range.lowerBound && upper == range.upperBound ? nil : lower..<upper
}

private func strip(_ s: String, _ range: Range<String.Index>) -> String {
    var t = s
    t.replaceSubrange(range, with: " ")
    return t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// The given weekday (1 = Sunday … 7 = Saturday) in the week after today's (weeks start on Monday).
private func nextWeekDay(_ w: Int, today: DayKey) -> DayKey {
    let sinceMonday = (today.weekday + 5) % 7
    return today.adding(days: 7 - sinceMonday + (w + 5) % 7)
}
