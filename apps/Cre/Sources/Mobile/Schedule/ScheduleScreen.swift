import CreCore
import SwiftUI

/// 日程: portrait = one day under a week strip; landscape = the week. 「待办」 brings up the day's todos to place.
struct ScheduleScreen: View {
    @ObservedObject var state: MobileState
    @Environment(\.verticalSizeClass) private var vSize

    @State private var day: DayKey?
    @State private var armed: TrayItem?
    @State private var editing: EditorTarget?
    @State private var pending: PendingChange?
    @State private var trayOpen = false

    private var landscape: Bool { vSize == .compact }
    private var shownDay: DayKey { day ?? state.today }
    private var dayBinding: Binding<DayKey> { Binding(get: { shownDay }, set: { day = $0 }) }
    private var monday: DayKey { shownDay.adding(days: -((shownDay.weekday + 5) % 7)) }
    private var week: [DayKey] { (0..<7).map { monday.adding(days: $0) } }

    var body: some View {
        VStack(spacing: 0) {
            if landscape { weekHeader } else { dayHeader }
            TimelineGrid(state: state, days: landscape ? week : [shownDay], armed: $armed, editing: $editing, pending: $pending,
                         onSwipeDay: { step in
                             withAnimation(.easeOut(duration: 0.2)) { day = shownDay.adding(days: landscape ? step * 7 : step) }
                         })
                .id(landscape ? "week-\(monday)" : "day-\(shownDay)")
        }
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottomTrailing) { trayArea }
        .sheet(item: $editing) { t in ScheduleEditScreen(state: state, target: t) { editing = nil } }
        .confirmationDialog("这是重复日程", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button("只改这一次") { pending?.apply(.one, &state.schedule); pending = nil }
            Button("改全部") { pending?.apply(.all, &state.schedule); pending = nil }
            Button("取消", role: .cancel) { pending = nil }
        }
    }

    private var dayHeader: some View {
        VStack(spacing: 6) {
            PageTitleRow { Text("日程") } trailing: {
                if shownDay != state.today {
                    Button("回今天") { day = state.today }.font(.subheadline.weight(.medium)).foregroundStyle(Color.accentColor)
                        .padding(.trailing, 8)
                }
            }
            .padding(.leading, 20).padding(.trailing, 12).padding(.top, 4)
            WeekStrip(day: dayBinding, today: state.today).padding(.horizontal, 8)
            Divider().padding(.top, 4)
        }
    }

    private var weekHeader: some View {
        VStack(spacing: 2) {
            HStack(spacing: 12) {
                Button { day = shownDay.adding(days: -7) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("上一周")
                Text(verbatim: "\(monday.month)月\(monday.day)日 – \(week[6].month == monday.month ? "" : "\(week[6].month)月")\(week[6].day)日")
                    .font(.headline).monospacedDigit()
                Button { day = shownDay.adding(days: 7) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("下一周")
                Spacer()
                if !week.contains(state.today) { Button("回今天") { day = state.today }.font(.subheadline.weight(.medium)) }
            }
            .padding(.horizontal, 16).padding(.top, 6)
            HStack(spacing: 0) {
                Color.clear.frame(width: TimelineGrid.labelWidth, height: 1)
                ForEach(week, id: \.self) { d in
                    let isToday = d == state.today
                    VStack(spacing: 0) {
                        Text(String(Fmt.weekdayName(d.weekday).dropFirst())).font(.caption2)
                        Text("\(d.day)").font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
                    .frame(maxWidth: .infinity)
                    .onTapGesture { day = d }
                }
            }
            .padding(.trailing, 8)
            Divider()
        }
    }

    @ViewBuilder private var trayArea: some View {
        if trayOpen {
            TrayPanel(state: state, day: shownDay, armed: $armed) { trayOpen = false; armed = nil }
                .frame(maxWidth: landscape ? 320 : .infinity)
                .padding(12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            Button { withAnimation(.easeOut(duration: 0.2)) { trayOpen = true } } label: {
                Label("待办", systemImage: "tray").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .padding(16)
            .accessibilityLabel("待办")
        }
    }
}
