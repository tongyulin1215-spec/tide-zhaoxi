import CreCore
import SwiftUI

/// Monday-to-Sunday strip above the day timeline: tap a day, swipe for another week.
struct WeekStrip: View {
    @Binding var day: DayKey
    let today: DayKey

    private var monday: DayKey { day.adding(days: -((day.weekday + 5) % 7)) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let d = monday.adding(days: i)
                let selected = d == day
                Button { day = d } label: {
                    VStack(spacing: 4) {
                        Text(String(Fmt.weekdayName(d.weekday).dropFirst())).font(.caption2).foregroundStyle(.secondary)
                        Text("\(d.day)").font(.callout.weight(selected || d == today ? .semibold : .regular)).monospacedDigit()
                            .frame(width: 34, height: 34)
                            .background(selected ? Color.accentColor : .clear, in: Circle())
                            .foregroundStyle(selected ? Color.white : (d == today ? Color.accentColor : Color.primary))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("day-\(d.day)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { g in
                let dx = g.translation.width
                guard abs(dx) > 50, abs(dx) > abs(g.translation.height) * 2 else { return }
                withAnimation(.easeOut(duration: 0.2)) { day = day.adding(days: dx < 0 ? 7 : -7) }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("week-strip")
    }
}
