import CreCore
import SwiftUI

/// 待办卡片: the day's open todos. Tap a card, then a slot; or long-press a card and drag it onto the timeline.
struct TrayPanel: View {
    @ObservedObject var state: MobileState
    let day: DayKey
    @Binding var armed: TrayItem?
    let onClose: () -> Void

    private var items: [TrayItem] { trayItems(on: day, today: state.today, data: state.data) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("待办 · \(Fmt.date(day)) \(Fmt.weekdayName(day.weekday))").font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark").font(.footnote.weight(.semibold)).frame(width: 30, height: 30) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("收起")
            }
            ScrollView {
                VStack(spacing: 6) {
                    if items.isEmpty {
                        Text("这天没有待办").font(.footnote).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(items, id: \.title) { card($0) }
                }
            }
            .frame(maxHeight: 210)
            Text(armed == nil ? "拖到时间表，或点卡片再点时段" : "点一个时段放入")
                .font(.caption).foregroundStyle(armed == nil ? Color.secondary : Color.accentColor)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private func card(_ item: TrayItem) -> some View {
        let placed = state.schedule.occurrences(on: day).filter { $0.title == item.title }
        let at = placed.map(\.start).min()
        let upcoming = placed.contains { !scheduleIsPast($0, minuteNow: minuteOfDay(DemoData.fixedNow ?? Date()), today: state.today) }
        let color = placed.first.map { scheduleColor($0.kind) }
        let isArmed = armed?.title == item.title
        return Button { armed = isArmed ? nil : item } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5).fill(Theme.color(for: item.kind)).frame(width: 3, height: 18)
                Text(item.title).font(.callout).lineLimit(1)
                Spacer(minLength: 4)
                if let at, let color {
                    Text(clock(at)).font(.caption).monospacedDigit().foregroundStyle(upcoming ? color : color.opacity(0.55))
                } else {
                    Text(durationText(minutesInTitle(item.title) ?? 60)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(color.map { $0.opacity(upcoming ? 0.12 : 0.05) } ?? Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isArmed ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(item.title)
        .accessibilityLabel(at.map { "\(item.title) \(clock($0))" } ?? item.title)
        .accessibilityIdentifier("tray-\(item.title)")
    }
}
