import CreCore
import SwiftUI

/// Visual style "A 加强版": plain, airy, system light/dark; four kind colors on a thick bar and the check ring.
enum Theme {
    static func color(for kind: EntryKind) -> Color {
        switch kind {
        case .day: Color(red: 0.184, green: 0.435, blue: 0.929)       // #2f6fed
        case .deadline: Color(red: 0.941, green: 0.541, blue: 0.141)  // #f08a24
        case .repeating: Color(red: 0.122, green: 0.643, blue: 0.388) // #1fa463
        case .span: Color(red: 0.557, green: 0.357, blue: 0.847)      // #8e5bd8
        }
    }

    static func color(for p: Priority) -> Color {
        switch p {
        case .p0: Color(red: 0.898, green: 0.282, blue: 0.302)        // #e5484d
        case .p1: Color(red: 0.941, green: 0.541, blue: 0.141)
        case .p2: Color.gray
        }
    }

    static let overdue = Color(red: 0.831, green: 0.235, blue: 0.235)
    static let undated = Color.gray.opacity(0.45)
    static let doneOpacity = 0.4
    static let barWidth: CGFloat = 5
}

enum Fmt {
    private static let weekdays = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    private static let short = ["", "日", "一", "二", "三", "四", "五", "六"]

    static func title(_ day: DayKey, today: DayKey) -> String {
        let base = "\(day.month)月\(day.day)日 \(weekdays[day.weekday])"
        switch today.days(until: day) {
        case 0: return "今天 · " + base
        case 1: return "明天 · " + base
        case -1: return "昨天 · " + base
        default: return base
        }
    }

    static func date(_ day: DayKey) -> String { "\(day.month)月\(day.day)日" }

    /// "10月5日 – 10月11日"; a single day is written once.
    static func range(_ from: DayKey, _ to: DayKey) -> String {
        from == to ? date(from) : "\(date(from)) – \(date(to))"
    }

    static func weekdayName(_ w: Int) -> String { weekdays[w] }

    /// [2,3,4,5,6,7] → "一至六"; [2,4,6] → "一三五"; [] → "每天".
    static func weekdaySet(_ set: Set<Int>) -> String {
        if set.isEmpty || set.count == 7 { return "每天" }
        let order = [2, 3, 4, 5, 6, 7, 1]
        let picked = order.filter(set.contains)
        let idx = picked.compactMap { order.firstIndex(of: $0) }
        if picked.count >= 3, idx.last! - idx.first! == picked.count - 1 {
            return short[picked.first!] + "至" + short[picked.last!]
        }
        return picked.map { short[$0] }.joined()
    }

    /// Short description of a schedule for the input hint and time tags.
    static func schedule(_ s: Schedule) -> String? {
        switch s {
        case .none: return nil
        case .day(let d): return date(d)
        case .deadline(let d): return "截止 " + date(d)
        case .span(let a, let b): return "\(a.month).\(a.day)–\(b.month).\(b.day)"
        case .repeating(let r): return r.weekdays.isEmpty ? "每天" : "每周" + weekdaySet(r.weekdays)
        }
    }
}

/// Faint background under the row the pointer is on.
struct RowHover: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.045 : 0)))
            .onHover { hovering = $0 }
    }
}

extension View {
    func rowHover() -> some View { modifier(RowHover()) }
}
