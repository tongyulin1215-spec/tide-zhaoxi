import CreCore
import SwiftUI

extension AppState {
    /// Friday 19:00+ with overdue items and this week not handled yet.
    var triageOffered: Bool {
        triageCount > 0 && shouldOfferTriage(now: Date(), lastTriagedWeek: data.lastTriagedWeek)
    }

    /// Marks this Friday's triage as handled so the banner stops showing.
    func finishTriage() {
        if shouldOfferTriage(now: Date(), lastTriagedWeek: data.lastTriagedWeek) {
            data.lastTriagedWeek = today
        }
        showTriage = false
    }
}

/// Banner at the top of the day view on Friday evenings.
struct TriageBanner: View {
    @ObservedObject var state: AppState
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full")
                Text("拖延 \(state.triageCount) 项")
                Spacer()
                Text("处理").fontWeight(.semibold)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(Theme.overdue)
            .background(Theme.overdue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

/// 整理拖延：each overdue item → 今天做 / 改日期.
struct TriageSheet: View {
    @ObservedObject var state: AppState
    @State private var picking: UUID?
    @State private var pickedDate = Date()

    private var items: [Todo] { triageCandidates(today: state.today, data: state.data) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("整理拖延").font(.title3.weight(.semibold))
            if items.isEmpty {
                Text("已清空").foregroundStyle(.secondary).padding(.vertical, 20)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(items) { todo in row(todo) }
                }
            }
            .frame(maxHeight: 360)
            HStack {
                Spacer()
                Button("稍后") { state.finishTriage() }.keyboardShortcut(.cancelAction)
                Button("完成") { state.finishTriage() }.keyboardShortcut(.defaultAction).disabled(!items.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func row(_ todo: Todo) -> some View {
        HStack(spacing: 8) {
            if let p = todo.priority { PriorityChip(priority: p) }
            Text(todo.text).lineLimit(1)
            Spacer()
            if let label = overdueLabel(todo) { Tag(text: label, color: Theme.overdue) }
            Button("今天做") { state.data.doToday(todo.id, today: state.today) }
            Button("改日期") { pickedDate = state.today.adding(days: 1).date(); picking = todo.id }
                .popover(isPresented: Binding(get: { picking == todo.id }, set: { if !$0 { picking = nil } })) {
                    MonthCalendar(day: Binding(get: { DayKey.from(pickedDate) }, set: { pickedDate = $0.date() }),
                                  earliest: state.today, today: state.today) {
                        state.data.reschedule(todo.id, to: DayKey.from(pickedDate))
                        picking = nil
                    }
                    .padding(10)
                }
        }
        .controlSize(.small)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private func overdueLabel(_ todo: Todo) -> String? {
        switch todo.schedule {
        case .day(let d), .deadline(let d): return "拖了 \(d.days(until: state.today)) 天"
        default: return nil
        }
    }
}
