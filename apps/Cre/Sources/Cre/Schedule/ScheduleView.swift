import CreCore
import SwiftUI

/// 日程：周视图，按小时排时间。只做参考，不打勾、不统计。
struct ScheduleView: View {
    @ObservedObject var state: AppState

    @State private var weekStart: DayKey = DayKey.from(Date())
    /// Whose todos the quick buttons show.
    @State private var chipDay: DayKey = DayKey.from(Date())
    /// A quick button picked by click, waiting for a slot.
    @State private var armed: String?
    @State private var editing: EditorTarget?
    @State private var pending: PendingChange?
    @AppStorage("scheduleTrayOpen") private var trayOpen = true

    static let hourHeight: CGFloat = 44
    static let labelWidth: CGFloat = 46

    private var days: [DayKey] { (0..<7).map { weekStart.adding(days: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 6) {
                    dayHeaders
                    grid
                }
                if trayOpen {
                    Divider().padding(.leading, 12)
                    tray.frame(width: 200)
                }
            }
        }
        .padding(22)
        .onAppear { weekStart = monday(of: state.today); chipDay = state.today }
        .sheet(item: $editing) { t in
            ScheduleEditor(state: state, target: t) { editing = nil }
        }
        .confirmationDialog("这是重复日程", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("只改这一次") { pending?.apply(.one, &state.schedule); pending = nil }
            Button("改全部") { pending?.apply(.all, &state.schedule); pending = nil }
            Button("取消", role: .cancel) { pending = nil }
        }
    }

    private var grid: some View {
            WeekGrid(state: state, days: days, armed: $armed, editing: $editing, pending: $pending,
                     kindOf: { t in chipItems.first { $0.title == t }?.kind })
                .id(weekStart)  // a new week scrolls itself again
    }

    private func monday(of d: DayKey) -> DayKey { d.adding(days: -((d.weekday + 5) % 7)) }

    private var header: some View {
        HStack(spacing: 10) {
            if weekStart != monday(of: state.today) {
                Button("今天") { weekStart = monday(of: state.today); chipDay = state.today }
            }
            Button { weekStart = weekStart.adding(days: -7) } label: { ToolbarIcon(name: "chevron.left") }
                .buttonStyle(.borderless).help("上一周")
            Button { weekStart = weekStart.adding(days: 7) } label: { ToolbarIcon(name: "chevron.right") }
                .buttonStyle(.borderless).help("下一周")
            Text(verbatim: rangeTitle).font(.title3.weight(.semibold)).monospacedDigit()
            Spacer()
            Button { withAnimation(.easeOut(duration: 0.15)) { trayOpen.toggle() } } label: { ToolbarIcon(name: "sidebar.right") }
                .buttonStyle(.borderless).help(trayOpen ? "收起待办栏" : "展开待办栏")
        }
    }

    private var rangeTitle: String {
        let a = days.first!, b = days.last!
        let tail = a.month == b.month ? "\(b.day)日" : "\(b.month)月\(b.day)日"
        return "\(a.year)年\(a.month)月\(a.day)日 – \(tail)"
    }

    /// The chosen day's todo names, as buttons to drag (or click, then click a slot).
    private var chipItems: [(title: String, kind: EntryKind)] {
        trayItems(on: chipDay, today: state.today, data: state.data).map { ($0.title, $0.kind) }
    }

    /// A button already placed on its day takes that block's colour and depth.
    private func chipStyle(_ title: String) -> (Color, Bool)? {
        let placed = state.schedule.occurrences(on: chipDay).filter { $0.title == title }
        guard let first = placed.first else { return nil }
        let upcoming = placed.contains { !scheduleIsPast($0, now: Date(), today: state.today) }
        return (scheduleColor(first.kind), upcoming)
    }

    /// 待办栏: the chosen day's todos as cards to drag (or click, then click a slot).
    private var tray: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                Text("待办 · \(Fmt.date(chipDay)) \(Fmt.weekdayName(chipDay.weekday))").font(.subheadline.weight(.semibold))
                Spacer()
                Button { chipDay = chipDay.adding(days: -1) } label: { Image(systemName: "chevron.left").font(.caption) }
                    .buttonStyle(.borderless).help("前一天")
                Button { chipDay = chipDay.adding(days: 1) } label: { Image(systemName: "chevron.right").font(.caption) }
                    .buttonStyle(.borderless).help("后一天")
            }
            ScrollView {
                VStack(spacing: 6) {
                    if chipItems.isEmpty {
                        Text("这天没有待办").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(chipItems, id: \.title) { item in trayCard(item.title, item.kind) }
                }
            }
            Text(armed == nil ? "拖到时间表，或点卡片再点时段" : "点一个时段放入")
                .font(.caption).foregroundStyle(armed == nil ? Color.secondary : Color.accentColor)
        }
        .padding(.leading, 12)
    }

    private func trayCard(_ t: String, _ kind: EntryKind) -> some View {
        let style = chipStyle(t)
        let mins = minutesInTitle(t) ?? 60
        let length = mins >= 60 ? "\(mins / 60) 小时" + (mins % 60 > 0 ? " \(mins % 60) 分" : "") : "\(mins) 分"
        return HStack(spacing: 7) {
            Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(.tertiary)
            RoundedRectangle(cornerRadius: 1.5).fill(Theme.color(for: kind)).frame(width: 3, height: 16)
            Text(t).font(.callout).lineLimit(1)
            Spacer(minLength: 4)
            if let (color, upcoming) = style, let at = placedStart(t) {
                Text(clock(at)).font(.caption).monospacedDigit().foregroundStyle(upcoming ? color : color.opacity(0.55))
            } else {
                Text(length).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(style.map { $0.0.opacity($0.1 ? 0.12 : 0.05) } ?? Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(armed == t ? Color.accentColor : Color.primary.opacity(0.08),
                                                                lineWidth: armed == t ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { armed = armed == t ? nil : t }
        .draggable(t)
        .help("拖到时间表，或点一下再点时段")
    }

    /// When a todo is already placed on the tray's day (earliest start).
    private func placedStart(_ title: String) -> Int? {
        state.schedule.occurrences(on: chipDay).filter { $0.title == title }.map(\.start).min()
    }

    private var dayHeaders: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.labelWidth, height: 1)
            ForEach(days, id: \.self) { d in
                let isToday = d == state.today
                VStack(spacing: 1) {
                    Text(Fmt.weekdayName(d.weekday)).font(.caption)
                    Text("\(d.day)").font(.title3.weight(.semibold)).monospacedDigit()
                }
                .foregroundStyle(isToday ? Color.accentColor : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
            }
        }
    }
}

/// Already over: an earlier day, or today with its end passed.
func scheduleIsPast(_ o: ScheduleOccurrence, now: Date, today: DayKey) -> Bool {
    scheduleIsPast(o, minuteNow: minuteOfDay(now), today: today)
}

// MARK: - Grid

struct WeekGrid: View {
    @ObservedObject var state: AppState
    let days: [DayKey]
    @Binding var armed: String?
    @Binding var editing: EditorTarget?
    @Binding var pending: PendingChange?
    /// The todo kind behind a quick button's title, for the new block's colour.
    var kindOf: (String) -> EntryKind? = { _ in nil }

    /// A new range being dragged out: (day index, start, end) in minutes.
    @State private var sweep: (Int, Int, Int)?

    private let hh = ScheduleView.hourHeight

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    hourLabels
                    GeometryReader { geo in
                        let colW = geo.size.width / 7
                        ZStack(alignment: .topLeading) {
                            background(colW: colW)
                            if let (di, a, b) = sweep {
                                RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.18))
                                    .frame(width: colW - 4, height: CGFloat(b - a) / 60 * hh)
                                    .offset(x: CGFloat(di) * colW + 2, y: CGFloat(a) / 60 * hh)
                                    .allowsHitTesting(false)
                            }
                            ForEach(Array(days.enumerated()), id: \.offset) { di, d in
                                ForEach(state.schedule.layout(on: d), id: \.occurrence.id) { slot in
                                    EventBlock(state: state, slot: slot, dayIndex: di, colW: colW, days: days,
                                               editing: $editing, pending: $pending)
                                }
                            }
                            nowLine(colW: colW)
                        }
                    }
                    .frame(height: hh * 24)
                }
            }
            .onAppear {
                // This week: open around now; other weeks: from 6:00 (so 7:00 reads fully).
                let h = Calendar.current.component(.hour, from: Date())
                proxy.scrollTo(days.contains(state.today) ? max(0, min(h - 1, 15)) : 6, anchor: .top)
            }
        }
    }

    private var hourLabels: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                Text(h == 0 ? "" : clock(h * 60)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: ScheduleView.labelWidth - 6, height: hh, alignment: .topTrailing)
                    .offset(y: -6)
                    .id(h)
            }
        }
        .padding(.trailing, 6)
    }

    private func background(colW: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { _ in
                    VStack(spacing: 0) { Divider(); Spacer(minLength: 0) }.frame(height: hh)
                }
            }
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { d in
                    Rectangle().fill(d == state.today ? Color.accentColor.opacity(0.03) : .clear)
                        .overlay(alignment: .leading) { Divider() }
                }
            }
        }
        .contentShape(Rectangle())
        // A click and a sweep are separate gestures, so a click right after a drag still registers.
        .onTapGesture { loc in
            let day = days[dayIndex(loc.x, colW)]
            let a = floorQuarter(minute(loc.y))
            if let t = armed {
                state.schedule.add(title: t, day: day, start: a, end: min(1440, a + (minutesInTitle(t) ?? 60)), kind: kindOf(t))
                armed = nil
            } else {
                editing = EditorTarget(day: day, start: a, end: min(1440, a + 60))
            }
        }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { g in
                    let di = dayIndex(g.startLocation.x, colW)
                    let a = floorQuarter(minute(g.startLocation.y)), b = floorQuarter(minute(g.location.y))
                    sweep = (di, min(a, b), max(a, b) + 15)
                }
                .onEnded { g in
                    guard let (di, a, b) = sweep else { return }
                    sweep = nil
                    editing = EditorTarget(day: days[di], start: a, end: min(b, 1440))
                }
        )
        .dropDestination(for: String.self) { items, loc in
            guard let t = items.first else { return false }
            let a = floorQuarter(minute(loc.y))
            state.schedule.add(title: t, day: days[dayIndex(loc.x, colW)], start: a, end: min(1440, a + (minutesInTitle(t) ?? 60)),
                               kind: kindOf(t))
            return true
        }
    }

    @ViewBuilder private func nowLine(colW: CGFloat) -> some View {
        if let di = days.firstIndex(of: state.today) {
            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                let c = Calendar.current.dateComponents([.hour, .minute], from: ctx.date)
                let y = CGFloat((c.hour ?? 0) * 60 + (c.minute ?? 0)) / 60 * hh
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color.red.opacity(0.35)).frame(height: 1).offset(y: y)
                    Rectangle().fill(Color.red).frame(width: colW * CGFloat(7 - di), height: 1.5).offset(x: CGFloat(di) * colW, y: y)
                    Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: CGFloat(di) * colW - 4, y: y - 3.5)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func dayIndex(_ x: CGFloat, _ colW: CGFloat) -> Int { min(6, max(0, Int(x / colW))) }
    private func minute(_ y: CGFloat) -> Int { Int(y / hh * 60) }
    private func floorQuarter(_ m: Int) -> Int { min(1425, max(0, m / 15 * 15)) }
}

// MARK: - Block

struct EventBlock: View {
    @ObservedObject var state: AppState
    let slot: ScheduleSlot
    let dayIndex: Int
    let colW: CGFloat
    let days: [DayKey]
    @Binding var editing: EditorTarget?
    @Binding var pending: PendingChange?

    @State private var moveBy: CGSize = .zero
    @State private var growBy: CGFloat = 0
    @State private var hovering = false

    private let hh = ScheduleView.hourHeight
    private var o: ScheduleOccurrence { slot.occurrence }
    private var color: Color { scheduleColor(o.kind) }
    /// Over already: lighter. Still ahead: the full colour.
    private var past: Bool { scheduleIsPast(o, now: Date(), today: state.today) }

    var body: some View {
        let w = colW / CGFloat(max(slot.columns, 1))
        let h = max(CGFloat(o.end - o.start) / 60 * hh + growBy, hh / 4)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(o.title).font(.caption.weight(.semibold)).lineLimit(h > 30 ? 2 : 1)
                if o.isRepeating { Image(systemName: "repeat").font(.system(size: 8)) }
            }
            if h > 30 {
                Text("\(clock(previewStart)) – \(clock(previewEnd))").font(.caption2).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(past ? color.opacity(0.55) : color)
        .padding(.leading, 6).padding(.top, 3).padding(.trailing, 2)
        // Inset from the hour lines (2pt each end), so back-to-back blocks show a gap like Feishu.
        .frame(width: w - 3, height: max(h - 4, 8), alignment: .topLeading)
        // An opaque base under the tint, so hour lines don't show through the block.
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor))
                RoundedRectangle(cornerRadius: 5).fill(color.opacity((past ? 0.07 : 0.18) + (hovering ? 0.1 : 0)))
            }
        }
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(color.opacity(past ? 0.45 : 1)).frame(width: 3) }
        .shadow(color: .black.opacity(hovering || moveBy != .zero ? 0.15 : 0), radius: 4, y: 1)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
        .overlay(alignment: .bottom) {
            // Bottom edge: drag to change the length.
            Color.clear.frame(height: 6).contentShape(Rectangle())
                .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { growBy = $0.translation.height }
                    .onEnded { g in
                        growBy = 0
                        let end = max(o.start + 15, snapMinute(o.end + Int(g.translation.height / hh * 60)))
                        commit(to: o.day, start: o.start, end: end)
                    })
        }
        .offset(x: CGFloat(dayIndex) * colW + CGFloat(slot.column) * w + 1 + moveBy.width,
                y: CGFloat(o.start) / 60 * hh + 2 + moveBy.height)
        .zIndex(moveBy == .zero ? 0 : 1)
        .onTapGesture { editing = EditorTarget(occurrence: o, day: o.day, start: o.start, end: o.end, title: o.title) }
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { moveBy = $0.translation }
            .onEnded { g in
                moveBy = .zero
                let target = min(6, max(0, dayIndex + Int((g.translation.width / colW).rounded())))
                let len = o.end - o.start
                let start = min(1440 - len, snapMinute(o.start + Int(g.translation.height / hh * 60)))
                commit(to: days[target], start: max(0, start), end: max(0, start) + len)
            })
    }

    private var previewStart: Int { snapMinute(o.start + Int(moveBy.height / hh * 60)) }
    private var previewEnd: Int {
        moveBy != .zero ? previewStart + (o.end - o.start) : max(o.start + 15, snapMinute(o.end + Int(growBy / hh * 60)))
    }

    private func commit(to day: DayKey, start: Int, end: Int) {
        guard day != o.day || start != o.start || end != o.end else { return }
        let change = PendingChange(id: o.itemID, from: o.day, to: day, start: start, end: end)
        if o.isRepeating { pending = change } else { change.apply(.all, &state.schedule) }
    }
}
