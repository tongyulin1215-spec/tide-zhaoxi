import CreCore
import SwiftUI

/// The app's one calendar. Single mode: a click picks the day. Range mode: first click starts, second ends.
struct MonthCalendar: View {
    @Binding var from: DayKey
    @Binding var to: DayKey
    var range = false
    var earliest: DayKey? = nil
    var latest: DayKey? = nil
    var today: DayKey = DayKey.from(Date())
    var onDone: () -> Void = {}

    @State private var month: DayKey = DayKey(year: 2000, month: 1, day: 1)!
    @State private var picking = false  // range: start chosen, waiting for the end

    private static let heads = ["日", "一", "二", "三", "四", "五", "六"]

    #if os(iOS)
    // Phone: full width, finger-sized days.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let cellHeight: CGFloat = 40
    private let headFont = Font.title3.weight(.semibold)
    private let dayFont = Font.body
    #else
    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 0), count: 7)
    private let cellHeight: CGFloat = 28
    private let headFont = Font.headline
    private let dayFont = Font.callout
    #endif

    private var cells: [DayKey?] {
        var days: [DayKey?] = Array(repeating: nil, count: month.weekday - 1)
        var d = month
        while d.month == month.month { days.append(d); d = d.adding(days: 1) }
        return days
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: arrowSpacing) {
                Text(verbatim: "\(month.year)年\(month.month)月").font(headFont)
                Spacer()
                if !(month.year == today.year && month.month == today.month) {
                    Button("今天") { month = first(of: today) }.buttonStyle(.borderless).font(.caption)
                }
                Button { shift(-1) } label: { arrow("chevron.left") }.buttonStyle(.borderless)
                    .disabled(earliest.map { first(of: $0) >= month } ?? false)
                Button { shift(1) } label: { arrow("chevron.right") }.buttonStyle(.borderless)
                    .disabled(latest.map { first(of: $0) <= month } ?? false)
            }
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Self.heads, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, d in
                    if let d { cell(d) } else { Color.clear.frame(height: cellHeight) }
                }
            }
            if range {
                Text(picking ? "再点结束日期" : Fmt.range(from, to)).font(.caption).foregroundStyle(.secondary)
            }
        }
        #if os(iOS)
        .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        #else
        .padding(12)
        .frame(width: 240)
        #endif
        .onAppear { month = first(of: to) }
    }

    #if os(iOS)
    private let arrowSpacing: CGFloat = 22
    private func arrow(_ name: String) -> some View {
        Image(systemName: name).font(.title3.weight(.medium)).frame(width: 32, height: 32).contentShape(Rectangle())
    }
    #else
    private let arrowSpacing: CGFloat? = nil
    private func arrow(_ name: String) -> some View { Image(systemName: name) }
    #endif

    private func first(of d: DayKey) -> DayKey { DayKey(year: d.year, month: d.month, day: 1)! }

    private func cell(_ d: DayKey) -> some View {
        let isEnd = d == from || (!picking && d == to)
        let inRange = range && !picking && from <= d && d <= to
        let blocked = (earliest.map { d < $0 } ?? false) || (latest.map { d > $0 } ?? false)
        return Button { pick(d) } label: {
            Text("\(d.day)")
                .font(dayFont.weight(d == today ? .semibold : .regular)).monospacedDigit()
                #if os(iOS)
                .frame(maxWidth: .infinity).frame(height: cellHeight)
                .background(inRange && !isEnd ? Color.accentColor.opacity(0.15) : .clear)
                .background(isEnd ? Color.accentColor : .clear, in: Circle().inset(by: 2))
                #else
                .frame(width: 30, height: cellHeight)
                .background(isEnd ? Color.accentColor : (inRange ? Color.accentColor.opacity(0.15) : .clear),
                            in: RoundedRectangle(cornerRadius: 6))
                #endif
                .overlay(alignment: .bottom) {
                    if d == today && !isEnd { Circle().fill(Color.accentColor).frame(width: 4, height: 4).padding(.bottom, 2) }
                }
                .foregroundStyle(isEnd ? Color.white : (blocked ? Color.secondary.opacity(0.4) : Color.primary))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(blocked)
    }

    private func pick(_ d: DayKey) {
        if !range {
            from = d; to = d
            onDone()
        } else if picking {
            if d < from { to = from; from = d } else { to = d }
            picking = false
            onDone()
        } else {
            from = d; to = d
            picking = true
        }
    }

    private func shift(_ n: Int) {
        var y = month.year, m = month.month + n
        if m == 0 { m = 12; y -= 1 } else if m == 13 { m = 1; y += 1 }
        month = DayKey(year: y, month: m, day: 1)!
    }
}

extension MonthCalendar {
    /// Single-day calendar.
    init(day: Binding<DayKey>, earliest: DayKey? = nil, latest: DayKey? = nil, today: DayKey = DayKey.from(Date()),
         onDone: @escaping () -> Void = {}) {
        self.init(from: day, to: day, range: false, earliest: earliest, latest: latest, today: today, onDone: onDone)
    }
}

/// A form field showing a day; click to pick from the calendar.
struct DayField: View {
    let label: String
    @Binding var day: DayKey
    var earliest: DayKey? = nil
    var latest: DayKey? = nil
    @State private var open = false

    var body: some View {
        LabeledContent(label) {
            Button(Fmt.date(day)) { open = true }
                .popover(isPresented: $open, arrowEdge: .trailing) {
                    MonthCalendar(day: $day, earliest: earliest, latest: latest) { open = false }
                        .phoneCalendarSheet()
                }
        }
    }
}

/// A form field showing a range; click to pick both ends on one calendar.
struct RangeField: View {
    let label: String
    @Binding var from: DayKey
    @Binding var to: DayKey
    var earliest: DayKey? = nil
    var latest: DayKey? = nil
    @State private var open = false

    var body: some View {
        LabeledContent(label) {
            Button(Fmt.range(from, to)) { open = true }
                .popover(isPresented: $open, arrowEdge: .trailing) {
                    MonthCalendar(from: $from, to: $to, range: true, earliest: earliest, latest: latest) { open = false }
                        .phoneCalendarSheet()
                }
        }
    }
}

/// Date-typed bindings for views that keep `Date` state.
func dayBinding(_ date: Binding<Date>) -> Binding<DayKey> {
    Binding(get: { DayKey.from(date.wrappedValue) }, set: { date.wrappedValue = $0.date() })
}

extension View {
    /// On the phone a calendar opens as a short sheet sized to the month; on the Mac it stays a popover.
    func phoneCalendarSheet() -> some View {
        #if os(iOS)
        presentationDetents([.height(390)]).presentationDragIndicator(.visible)
        #else
        self
        #endif
    }
}
