import CreCore
import SwiftUI

/// 记账: month totals and 余额, 流水 / 统计, the input line at the bottom (camera next to it).
struct LedgerScreen: View {
    @ObservedObject var state: MobileState
    @ObservedObject var intake: ScreenshotIntake

    enum Tab: String, CaseIterable { case flow = "流水", stats = "统计" }

    @State private var tab: Tab = .flow
    @State private var year = 0
    @State private var month = 0
    @State private var dayFilter: DayKey?
    @State private var draft = ""
    @State private var picking = false
    @State private var editing: LedgerEntry?
    @State private var newEntry: LedgerEntry?
    @State private var managingCategories = false
    @State private var settingOpening = false
    @FocusState private var inputFocused: Bool

    private var today: DayKey { state.today }
    private var shownYear: Int { year == 0 ? today.year : year }
    private var shownMonth: Int { month == 0 ? today.month : month }
    private var isCurrentMonth: Bool { shownYear == today.year && shownMonth == today.month }

    /// 余额 at the end of the viewed day or month (today for the current month).
    private var balanceDay: DayKey {
        if let dayFilter { return dayFilter }
        if isCurrentMonth { return today }
        let next = shownMonth == 12 ? DayKey(year: shownYear + 1, month: 1, day: 1) : DayKey(year: shownYear, month: shownMonth + 1, day: 1)
        return next!.adding(days: -1)
    }

    private var visibleEntries: [LedgerEntry] {
        state.ledger.entries.filter { e in
            if let d = dayFilter { return e.day == d }
            return e.day.year == shownYear && e.day.month == shownMonth
        }
    }

    private var totals: MonthTotals {
        if let d = dayFilter {
            let list = state.ledger.entries.filter { $0.day == d }
            return MonthTotals(income: list.filter(\.isIncome).reduce(0) { $0 + $1.amount },
                               expense: list.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount })
        }
        return monthTotals(state.ledger, year: shownYear, month: shownMonth)
    }

    var body: some View {
        List {
            Section {
                PageTitleRow { Text("记账") } trailing: { moreMenu }
                monthRow
                totalsRow
                Picker("", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 16))

            if intake.latest != nil {
                Section { latestBanner }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            switch tab {
            case .flow: flow
            case .stats:
                Section { LedgerStatsView(state: state, year: shownYear, month: shownMonth) }
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollDismissesKeyboard(.immediately)  // the input keeps focus for the next entry; any scroll puts the keyboard away
        .safeAreaInset(edge: .bottom) { input }
        .sheet(isPresented: $picking) {
            MonthCalendar(day: Binding(get: { dayFilter ?? today }, set: { d in
                dayFilter = d; year = d.year; month = d.month; tab = .flow
            }), latest: today, today: today) { picking = false }
            .phoneCalendarSheet()
        }
        .sheet(item: $editing) { e in LedgerFormScreen(state: state, entry: e) { editing = nil } }
        .sheet(item: $newEntry) { e in LedgerFormScreen(state: state, entry: nil, prefill: e) { newEntry = nil } }
        .sheet(isPresented: $managingCategories) { CategoryScreen(state: state) { managingCategories = false } }
        .sheet(isPresented: $settingOpening) { OpeningScreen(state: state) { settingOpening = false } }
        .sheet(item: Binding(get: { intake.draft }, set: { if $0 == nil, intake.draft != nil { intake.finished(state: state) } })) { d in
            LedgerFormScreen(state: state, entry: nil, prefill: d.entry, position: d.position, image: d.image) { intake.finished(state: state) }
        }
        .onAppear {
            intake.checkLatest()
            intake.takeDemoScreenshot(state: state)
        }
        .onChange(of: state.today) { old, new in
            if shownYear == old.year && shownMonth == old.month { year = new.year; month = new.month }
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("分类") { managingCategories = true }
            Button("起始余额") { settingOpening = true }
        } label: {
            Image(systemName: "ellipsis.circle").frame(width: 40, height: 40)
        }
        .accessibilityLabel("更多")
    }

    private var monthRow: some View {
        HStack(spacing: 4) {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 30, height: 30) }
                .foregroundStyle(.secondary)
                .accessibilityLabel("上个月")
            Button { picking = true } label: {
                Text(verbatim: dayFilter.map { "\($0.month)月\($0.day)日" } ?? "\(shownYear)年\(shownMonth)月")
                    .font(.headline).monospacedDigit().foregroundStyle(.primary)
            }
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 30, height: 30) }
                .foregroundStyle(isCurrentMonth || dayFilter != nil ? Color.secondary.opacity(0.4) : .secondary)
                .disabled(isCurrentMonth || dayFilter != nil)
                .accessibilityLabel("下个月")
            Spacer()
            if dayFilter != nil || !isCurrentMonth {
                Button("本月") { dayFilter = nil; year = today.year; month = today.month }.font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, -8)
    }

    private var totalsRow: some View {
        HStack(alignment: .top) {
            figure("收入", totals.income, .primary)
            Spacer()
            figure("支出", totals.expense, .primary)
            Spacer()
            figure("净收入", totals.net, .primary)
            Spacer()
            Button { settingOpening = true } label: {
                if let b = state.ledger.balance(asOf: balanceDay) {
                    figure("余额", b, b < 0 ? LedgerColors.negative : LedgerColors.income, trailing: true, id: "balance")
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("余额").font(.caption).foregroundStyle(.secondary)
                        Text(state.ledger.opening == nil ? "设置" : "—").font(.headline).foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func figure(_ label: String, _ cents: Int, _ color: Color, trailing: Bool = false, id: String? = nil) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text((cents < 0 ? "-" : "") + money(abs(cents))).font(.headline).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityIdentifier(id ?? "")
        }
    }

    @ViewBuilder private var flow: some View {
        if visibleEntries.isEmpty {
            Text("无记录").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 40)
                .listRowSeparator(.hidden)
        }
        ForEach(dayGroups(visibleEntries)) { g in
            Section {
                ForEach(g.entries) { e in
                    entryRow(e)
                        .swipeActions(edge: .trailing) {
                            Button("删除", role: .destructive) { state.ledger.delete(e.id) }
                        }
                }
            } header: {
                HStack {
                    Text(Fmt.title(g.day, today: today)).font(.footnote.weight(.semibold))
                    Spacer()
                    if g.income > 0 { Text("收入 \(money(g.income))").font(.caption).foregroundStyle(LedgerColors.income) }
                    if g.expense > 0 { Text("支出 \(money(g.expense))").font(.caption).foregroundStyle(.secondary) }
                }
                .textCase(nil)
            }
        }
    }

    /// Layout A: the category chip (icon + name) as one unit, then the note, then the amount.
    private func entryRow(_ e: LedgerEntry) -> some View {
        let tint = CategoryIcon.tint(e.category, isIncome: e.isIncome, data: state.ledger)
        let note = e.note.trimmingCharacters(in: .whitespaces)
        let amount = (e.isIncome ? "+" : "-") + money(e.amount)
        return Button { editing = e } label: {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: CategoryIcon.symbol(e.category)).font(.system(size: 11, weight: .semibold))
                    Text(e.category).font(.caption.weight(.medium))
                }
                .foregroundStyle(tint)
                .padding(.leading, 7).padding(.trailing, 9).padding(.vertical, 4)
                .background(tint.opacity(0.13), in: Capsule())
                .frame(minWidth: 64, alignment: .leading)
                if !note.isEmpty && note != e.category { Text(note).lineLimit(1) }
                Spacer()
                Text(amount).monospacedDigit().foregroundStyle(e.isIncome ? LedgerColors.income : .primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(e.category) \(note) \(amount)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("entry-\(note.isEmpty ? e.category : note)")
    }

    /// Shown after a fresh screenshot: one tap records it.
    private var latestBanner: some View {
        HStack {
            Button { intake.takeLatest(state: state) } label: {
                Label("记录这张？", systemImage: "camera.viewfinder").font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderless)
            Spacer()
            Button { intake.dismissLatest() } label: { Image(systemName: "xmark").font(.footnote.weight(.semibold)) }
                .buttonStyle(.borderless).foregroundStyle(.secondary).accessibilityLabel("忽略")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var input: some View {
        BottomInputBar(placeholder: "午饭 35", text: $draft, focus: $inputFocused, onSubmit: submit) {
            if let p = parseLedger(draft, today: today, data: state.ledger) {
                Text("\(p.category) \(money(p.amount))").font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            ScreenshotMenu(state: state, intake: intake)
            Button { newEntry = LedgerEntry(amount: 0, isIncome: false, category: "其他", note: "", day: today) } label: {
                Image(systemName: "square.and.pencil")
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("表单")
        }
    }

    /// A line with an amount is saved at once; anything else opens the form with the text as the note.
    private func submit() {
        let t = draft.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        if let p = parseLedger(t, today: today, data: state.ledger) {
            state.ledger.add(LedgerEntry(amount: p.amount, isIncome: p.isIncome, category: p.category, note: p.note, day: p.day), now: Date())
        } else {
            newEntry = LedgerEntry(amount: 0, isIncome: false, category: guessCategory(note: t, isIncome: false, data: state.ledger),
                                   note: t, day: today)
        }
        draft = ""
        inputFocused = true
    }

    private func shiftMonth(_ delta: Int) {
        dayFilter = nil
        var y = shownYear, m = shownMonth + delta
        if m == 0 { m = 12; y -= 1 } else if m == 13 { m = 1; y += 1 }
        year = y; month = m
    }
}
