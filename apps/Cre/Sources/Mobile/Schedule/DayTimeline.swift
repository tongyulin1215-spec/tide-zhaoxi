import CreCore
import SwiftUI

/// Hour grid for one day (portrait) or seven (landscape). Tap a free slot to add (or to place the armed tray card);
/// long-press a block to move it, drag its bottom handle to change the length; tray cards can be dropped in.
struct TimelineGrid: View {
    @ObservedObject var state: MobileState
    let days: [DayKey]
    @Binding var armed: TrayItem?
    @Binding var editing: EditorTarget?
    @Binding var pending: PendingChange?
    var onSwipeDay: ((Int) -> Void)? = nil

    /// The block picked up by a long press; only it can be moved or resized, so scrolling never edits.
    @State private var selected: String?

    static let hourHeight: CGFloat = 52
    static let labelWidth: CGFloat = 44
    private let hh = TimelineGrid.hourHeight

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    hourLabels
                    GeometryReader { geo in
                        let colW = geo.size.width / CGFloat(days.count)
                        ZStack(alignment: .topLeading) {
                            background(colW: colW)
                            ForEach(Array(days.enumerated()), id: \.offset) { di, d in
                                ForEach(state.schedule.layout(on: d), id: \.occurrence.id) { slot in
                                    BlockView(state: state, slot: slot, dayIndex: di, colW: colW, days: days,
                                              editing: $editing, pending: $pending, selected: $selected)
                                }
                            }
                            nowLine(colW: colW)
                        }
                    }
                    .frame(height: hh * 24)
                }
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            }
            // While a block is picked up, drags belong to it (move, grips), not to scrolling; tap off it to scroll again.
            .scrollDisabled(selected != nil)
            .accessibilityIdentifier(days.count > 1 ? "week-grid" : "timeline")
            .onAppear {
                let h = minuteOfDay(DemoData.fixedNow ?? Date()) / 60
                proxy.scrollTo(days.contains(state.today) ? max(0, min(h - 1, 15)) : 7, anchor: .top)
            }
        }
    }

    private var hourLabels: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                Text(h == 0 ? "" : clock(h * 60)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: Self.labelWidth - 6, height: hh, alignment: .topTrailing)
                    .offset(y: -6)
                    .id(h)
            }
        }
        .padding(.trailing, 6)
    }

    private func background(colW: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { h in
                    VStack(spacing: 0) { Divider(); Spacer(minLength: 0) }
                        .frame(height: hh)
                        .contentShape(Rectangle())
                        .accessibilityElement()
                        .accessibilityIdentifier("hour-\(h)")
                }
            }
            if days.count > 1 {
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { d in
                        Rectangle().fill(d == state.today ? Color.accentColor.opacity(0.04) : .clear)
                            .overlay(alignment: .leading) { Divider() }
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { loc in
            if selected != nil { selected = nil; return }  // a tap off the picked-up block just puts it down
            let day = days[dayIndex(loc.x, colW)]
            let a = floorQuarter(minute(loc.y))
            if let t = armed {
                state.schedule.add(title: t.title, day: day, start: a, end: min(1440, a + (minutesInTitle(t.title) ?? 60)), kind: t.kind)
                armed = nil
            } else {
                editing = EditorTarget(day: day, start: a, end: min(1440, a + 60))
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { g in
                let dx = g.translation.width, dy = g.translation.height
                guard let onSwipeDay, abs(dx) > 60, abs(dx) > abs(dy) * 2 else { return }
                onSwipeDay(dx < 0 ? 1 : -1)
            }
        )
        .dropDestination(for: String.self) { items, loc in
            guard let t = items.first else { return false }
            let a = floorQuarter(minute(loc.y))
            let kind = trayItems(on: days[dayIndex(loc.x, colW)], today: state.today, data: state.data).first { $0.title == t }?.kind
            state.schedule.add(title: t, day: days[dayIndex(loc.x, colW)], start: a, end: min(1440, a + (minutesInTitle(t) ?? 60)), kind: kind)
            armed = nil
            return true
        }
    }

    @ViewBuilder private func nowLine(colW: CGFloat) -> some View {
        if let di = days.firstIndex(of: state.today) {
            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                let y = CGFloat(minuteOfDay(DemoData.fixedNow ?? ctx.date)) / 60 * hh
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color.red).frame(width: colW * CGFloat(days.count - di), height: 1.5).offset(x: CGFloat(di) * colW, y: y)
                    Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: CGFloat(di) * colW - 4, y: y - 3.5)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func dayIndex(_ x: CGFloat, _ colW: CGFloat) -> Int { min(days.count - 1, max(0, Int(x / colW))) }
    private func minute(_ y: CGFloat) -> Int { Int(y / hh * 60) }
    private func floorQuarter(_ m: Int) -> Int { min(1425, max(0, m / 15 * 15)) }
}

/// One schedule block. A tap opens it; a long press picks it up (haptic, outlined, grips at both ends).
/// Only a picked-up block can be dragged (15-minute steps) or resized by its grips; any other touch lets the timeline scroll.
struct BlockView: View {
    @ObservedObject var state: MobileState
    let slot: ScheduleSlot
    let dayIndex: Int
    let colW: CGFloat
    let days: [DayKey]
    @Binding var editing: EditorTarget?
    @Binding var pending: PendingChange?
    @Binding var selected: String?

    @State private var moveBy: CGSize = .zero
    @State private var startBy: CGFloat = 0
    @State private var endBy: CGFloat = 0

    private let hh = TimelineGrid.hourHeight
    private var o: ScheduleOccurrence { slot.occurrence }
    private var color: Color { scheduleColor(o.kind) }
    private var isSelected: Bool { selected == o.id }
    private var lifted: Bool { isSelected }
    /// Over already: lighter. Still ahead: the full colour.
    private var past: Bool { scheduleIsPast(o, minuteNow: minuteOfDay(DemoData.fixedNow ?? Date()), today: state.today) }

    var body: some View {
        let w = colW / CGFloat(max(slot.columns, 1))
        let h = max(CGFloat(o.end - o.start) / 60 * hh - startBy + endBy, hh / 4)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(o.title).font(.caption.weight(.semibold)).lineLimit(h > 34 ? 2 : 1)
                if o.isRepeating { Image(systemName: "repeat").font(.system(size: 8)) }
            }
            if h > 34 {
                Text("\(clock(previewStart)) – \(clock(previewEnd))").font(.caption2).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(past ? color.opacity(0.55) : color)
        .padding(.leading, 6).padding(.top, 3).padding(.trailing, 2)
        // Inset from the hour lines (2pt each end), so back-to-back blocks show a gap.
        .frame(width: max(w - 3, 8), height: max(h - 4, 8), alignment: .topLeading)
        // The block reads as one element; the grips (overlays below) stay separate so they can be found.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(o.title) \(clock(o.start))–\(clock(o.end))")
        .accessibilityIdentifier("block-\(o.title)")
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(uiColor: .systemBackground))
                RoundedRectangle(cornerRadius: 6).fill(color.opacity((past ? 0.07 : 0.18) + (lifted ? 0.12 : 0)))
            }
        }
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(color.opacity(past ? 0.45 : 1)).frame(width: 3) }
        .overlay { if lifted { RoundedRectangle(cornerRadius: 6).strokeBorder(color, lineWidth: 1.5) } }
        .overlay(alignment: .topTrailing) { if isSelected { grip(top: true) } }
        .overlay(alignment: .bottomLeading) { if isSelected { grip(top: false) } }
        .shadow(color: .black.opacity(lifted ? 0.18 : 0), radius: 6, y: 2)
        .offset(x: CGFloat(dayIndex) * colW + CGFloat(slot.column) * w + 1 + moveBy.width,
                y: CGFloat(o.start) / 60 * hh + 2 + moveBy.height + startBy)
        .zIndex(lifted ? 1 : 0)
        .onTapGesture { editing = EditorTarget(occurrence: o, day: o.day, start: o.start, end: o.end, title: o.title) }
        // onLongPressGesture, unlike a LongPress+Drag gesture, doesn't hold the touch, so the timeline still scrolls.
        .onLongPressGesture(minimumDuration: 0.35) {
            selected = o.id
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        .gesture(isSelected ? move : nil)
    }

    /// Picked up: a plain drag moves it.
    private var move: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { moveBy = $0.translation }
            .onEnded { finishMove($0.translation) }
    }

    private func finishMove(_ t: CGSize) {
        moveBy = .zero
        let target = min(days.count - 1, max(0, dayIndex + Int((t.width / colW).rounded())))
        let len = o.end - o.start
        let start = min(1440 - len, snapMinute(o.start + Int(t.height / hh * 60)))
        commit(to: days[target], start: max(0, start), end: max(0, start) + len)
    }

    /// Round handle on the top (start) or bottom (end) edge of the picked-up block.
    private func grip(top: Bool) -> some View {
        Circle().fill(Color(uiColor: .systemBackground)).frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(color, lineWidth: 2.5))
            .frame(width: 44, height: 44).contentShape(Rectangle())  // a fingertip-sized target around a small dot
            .offset(x: top ? 14 : -14, y: top ? -15 : 15)  // straddles the edge, so most of the target is on the block
            .highPriorityGesture(DragGesture(minimumDistance: 1)
                .onChanged { g in if top { startBy = g.translation.height } else { endBy = g.translation.height } }
                .onEnded { g in
                    startBy = 0; endBy = 0
                    let shift = Int(g.translation.height / hh * 60)
                    if top {
                        let start = max(0, min(o.end - 15, snapMinute(o.start + shift)))
                        commit(to: o.day, start: start, end: o.end)
                    } else {
                        let end = min(1440, max(o.start + 15, snapMinute(o.end + shift)))
                        commit(to: o.day, start: o.start, end: end)
                    }
                })
            .accessibilityElement()
            .accessibilityLabel(top ? "调整开始" : "调整结束")
            .accessibilityIdentifier("grip-\(top ? "start" : "end")-\(o.title)")
    }

    private var previewStart: Int {
        moveBy != .zero ? snapMinute(o.start + Int(moveBy.height / hh * 60)) : snapMinute(o.start + Int(startBy / hh * 60))
    }
    private var previewEnd: Int {
        moveBy != .zero ? previewStart + (o.end - o.start) : max(previewStart + 15, snapMinute(o.end + Int(endBy / hh * 60)))
    }

    private func commit(to day: DayKey, start: Int, end: Int) {
        guard day != o.day || start != o.start || end != o.end else { return }
        let change = PendingChange(id: o.itemID, from: o.day, to: day, start: start, end: end)
        if o.isRepeating { pending = change } else { change.apply(.all, &state.schedule) }
        // Still picked up after a change on the same day, so start, end and place can be adjusted in turn.
        if day != o.day { selected = nil }
    }
}
