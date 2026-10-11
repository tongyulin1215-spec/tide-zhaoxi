import Charts
import CreCore
import SwiftUI

enum LedgerTab: String, CaseIterable, Identifiable {
    case flow = "流水", stats = "统计"
    var id: String { rawValue }
}

struct LedgerView: View {
    @ObservedObject var state: AppState
    @State private var year = DayKey.from(Date()).year
    @State private var month = DayKey.from(Date()).month
    @State private var dayFilter: DayKey?
    @State private var tab: LedgerTab = DemoData.isOn && ProcessInfo.processInfo.environment["CRE_LEDGER_TAB"] == "stats" ? .stats : .flow
    @State private var managingCategories = false
    @State private var draft: ScreenshotDraft?
    @State private var recognizing = false
    /// Screenshots waiting for their confirmation form, and how many came in this batch.
    @State private var queue: [CGImage] = []
    @State private var batch = 0
    @State private var pasteMonitor: Any?

    private var today: DayKey { state.today }
    private var isCurrentMonth: Bool { year == today.year && month == today.month }

    /// 余额 at the end of the viewed day or month (today for the current month).
    private var balanceDay: DayKey {
        if let dayFilter { return dayFilter }
        if isCurrentMonth { return today }
        let next = month == 12 ? DayKey(year: year + 1, month: 1, day: 1) : DayKey(year: year, month: month + 1, day: 1)
        return next!.adding(days: -1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LedgerInput(state: state) { recognize($0) }

            HStack(spacing: 10) {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                Text(verbatim: dayFilter.map { "\($0.month)月\($0.day)日" } ?? "\(year)年\(month)月")
                    .font(.title3.weight(.semibold)).monospacedDigit()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless).disabled(isCurrentMonth || dayFilter != nil)
                if dayFilter != nil || !isCurrentMonth {
                    Button("本月") { dayFilter = nil; year = today.year; month = today.month }.controlSize(.small)
                }
                Spacer()
                SoftSegments(selection: $tab, options: LedgerTab.allCases.map { ($0, $0.rawValue) })
                PastDayButton(today: today) { d in dayFilter = d; year = d.year; month = d.month; tab = .flow }
                Button { managingCategories = true } label: { Image(systemName: "tag") }
                    .buttonStyle(.borderless).help("分类")
            }

            TotalsRow(state: state, totals: dayFilter.map(dayTotals) ?? monthTotals(state.ledger, year: year, month: month),
                      asOf: balanceDay)

            switch tab {
            case .flow: FlowList(state: state, entries: visibleEntries)
            case .stats: LedgerStats(state: state, year: year, month: month)
            }
        }
        .padding(22)
        .sheet(isPresented: $managingCategories) { CategorySheet(state: state) { managingCategories = false } }
        .sheet(item: $draft, onDismiss: next) { d in
            LedgerForm(state: state, entry: nil, prefill: d.entry, image: d.image,
                       notice: (d.position.map { "\($0) · " } ?? "") + (d.foundAmount ? "识别自截图，请确认" : "未识别到金额，请手动填写")) { draft = nil }
        }
        .overlay {
            if recognizing { ProgressView("识别中").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            let usable = providers.filter { $0.canLoadObject(ofClass: NSImage.self) }
            guard !usable.isEmpty else { return false }
            Task { @MainActor in
                var images: [CGImage] = []
                for p in usable { if let img = await loadImage(p) { images.append(img) } }
                recognize(images)
            }
            return true
        }
        .onAppear {
            // ⌘V with an image on the clipboard records it; text pastes go through as usual.
            pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
                guard e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      e.charactersIgnoringModifiers == "v", draft == nil else { return e }
                let images = clipboardImages()
                guard !images.isEmpty else { return e }
                recognize(images)
                return nil
            }
        }
        .onDisappear { if let m = pasteMonitor { NSEvent.removeMonitor(m); pasteMonitor = nil } }
        .onChange(of: state.today) { old, new in
            if year == old.year && month == old.month { year = new.year; month = new.month }
        }
    }

    private func recognize(_ images: [CGImage]) {
        guard !images.isEmpty else { return }
        if queue.isEmpty && draft == nil && !recognizing { batch = 0 }
        queue += images
        batch += images.count
        if draft == nil && !recognizing { next() }
    }

    /// Opens the confirmation form for the next queued screenshot.
    private func next() {
        guard !queue.isEmpty else { return }
        let image = queue.removeFirst()
        let position = batch > 1 ? "\(batch - queue.count)/\(batch)" : nil
        recognizing = true
        Task {
            let (entry, found) = await draftEntry(from: image, state: state)
            recognizing = false
            draft = ScreenshotDraft(entry: entry, foundAmount: found, image: image, position: position)
        }
    }

    private var visibleEntries: [LedgerEntry] {
        state.ledger.entries.filter { e in
            if let d = dayFilter { return e.day == d }
            return e.day.year == year && e.day.month == month
        }
    }

    private func dayTotals(_ d: DayKey) -> MonthTotals {
        let list = state.ledger.entries.filter { $0.day == d }
        return MonthTotals(income: list.filter(\.isIncome).reduce(0) { $0 + $1.amount },
                           expense: list.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount })
    }

    private func shiftMonth(_ delta: Int) {
        dayFilter = nil
        month += delta
        if month < 1 { month = 12; year -= 1 }
        if month > 12 { month = 1; year += 1 }
    }
}

struct TotalsRow: View {
    @ObservedObject var state: AppState
    let totals: MonthTotals
    /// The day 余额 is shown for (end of the viewed day / month, never past today).
    let asOf: DayKey

    @State private var editing = false

    var body: some View {
        HStack(spacing: 28) {
            figure("收入", totals.income, .primary)
            figure("支出", totals.expense, .primary)
            figure("净收入", totals.net, .primary)
            Spacer()
            Button { editing = true } label: {
                if let b = state.ledger.balance(asOf: asOf) {
                    figure("余额", b, b < 0 ? LedgerColors.negative : LedgerColors.income, trailing: true)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("余额").font(.caption).foregroundStyle(.secondary)
                        Text(state.ledger.opening == nil ? "设置" : "—").font(.title3.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("设置起始余额")
            .popover(isPresented: $editing) { OpeningForm(state: state) { editing = false } }
        }
        .padding(.vertical, 4)
    }

    private func figure(_ label: String, _ cents: Int, _ color: Color, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text((cents < 0 ? "-" : "") + money(abs(cents))).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(color)
        }
    }
}

/// 起始余额: an amount on a day; later entries move it.
struct OpeningForm: View {
    @ObservedObject var state: AppState
    let done: () -> Void

    @State private var text = ""
    @State private var day = Date()

    /// "1200", "-35.5", "0" → cents.
    private var cents: Int? {
        let t = text.trimmingCharacters(in: .whitespaces)
        let negative = t.hasPrefix("-")
        let body = negative ? String(t.dropFirst()) : t
        if Double(body) == 0 { return 0 }
        return parseAmount(body).map { negative ? -$0 : $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("起始余额").font(.headline)
            TextField("金额", text: $text).onSubmit(save)
            DayField(label: "日期", day: dayBinding($day), latest: state.today)
            HStack {
                if state.ledger.opening != nil {
                    Button("清除", role: .destructive) { state.ledger.opening = nil; done() }
                }
                Spacer()
                Button("取消", action: done).keyboardShortcut(.cancelAction)
                Button("保存", action: save).keyboardShortcut(.defaultAction).disabled(cents == nil)
            }
        }
        .padding(14)
        .frame(width: 260)
        .onAppear {
            if let o = state.ledger.opening {
                text = String(format: "%.2f", Double(o.amount) / 100).replacingOccurrences(of: ".00", with: "")
                day = o.day.date(hour: 12)
            }
        }
    }

    private func save() {
        guard let cents else { return }
        state.ledger.opening = OpeningBalance(amount: cents, day: DayKey.from(day))
        done()
    }
}



/// Calendar limited to today and earlier.
struct PastDayButton: View {
    let today: DayKey
    let onPick: (DayKey) -> Void
    @State private var open = false
    @State private var picked = Date()

    var body: some View {
        Button { picked = today.date(); open = true } label: { Image(systemName: "calendar") }
            .buttonStyle(.borderless)
            .help("查看某天")
            .popover(isPresented: $open) {
                MonthCalendar(day: Binding(get: { DayKey.from(picked) }, set: { picked = $0.date(); onPick($0) }),
                              latest: today, today: today) { open = false }
            }
    }
}

// MARK: Input

private func loadImage(_ p: NSItemProvider) async -> CGImage? {
    await withCheckedContinuation { c in
        _ = p.loadObject(ofClass: NSImage.self) { obj, _ in
            nonisolated(unsafe) let cg = (obj as? NSImage)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            c.resume(returning: cg)
        }
    }
}

struct LedgerInput: View {
    @ObservedObject var state: AppState
    var onScreenshot: ([CGImage]) -> Void = { _ in }
    @State private var text = ""
    @State private var showingForm = false
    @FocusState private var focused: Bool

    private var parsed: ParsedLedger? { parseLedger(text, today: state.today, data: state.ledger) }

    private func capture() {
        Task { if let img = await captureScreenArea() { onScreenshot([img]) } }
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("午饭 35", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(submit)
            if let p = parsed {
                Text("→ \(p.isIncome ? "收入" : "支出") · \(p.category) · \(money(p.amount))\(p.day == state.today ? "" : " · \(p.day.month)月\(p.day.day)日")")
                    .foregroundStyle(.tertiary).lineLimit(1)
            }
            if parsed == nil && !text.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("缺金额").foregroundStyle(.tertiary)
            }
            Menu {
                Button("框选屏幕") { capture() }
                Button("选择图片…") { onScreenshot(pickScreenshots()) }
                Button("粘贴图片  ⌘V") { onScreenshot(clipboardImages()) }.disabled(clipboardImages().isEmpty)
            } label: { Image(systemName: "text.viewfinder") } primaryAction: { capture() }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .foregroundStyle(.secondary).help("截图记账：点击框选屏幕，按住看更多")
            Button { showingForm = true } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.borderless).foregroundStyle(.secondary).help("表单")
                .popover(isPresented: $showingForm) {
                    LedgerForm(state: state, entry: nil) { showingForm = false }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
    }

    private func submit() {
        guard let p = parsed else { return }
        state.ledger.add(LedgerEntry(amount: p.amount, isIncome: p.isIncome, category: p.category, note: p.note, day: p.day), now: Date())
        text = ""
        focused = true
    }
}

/// Full form: new entry (entry == nil) or edit an existing one.
struct LedgerForm: View {
    @ObservedObject var state: AppState
    let entry: LedgerEntry?
    /// Values to start a new entry with (from a screenshot).
    var prefill: LedgerEntry? = nil
    /// The screenshot the entry was read from.
    var image: CGImage? = nil
    var notice: String? = nil
    let onClose: () -> Void

    @State private var isIncome = false
    @State private var amountText = ""
    @State private var category = "其他"
    @State private var day = Date()
    @State private var note = ""

    private var cents: Int? { parseAmount(amountText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image {
                Image(decorative: image, scale: 2).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            SoftSegments(selection: $isIncome, options: [(false, "支出"), (true, "收入")])
            .onChange(of: isIncome) {
                // Back to the entry's own type: keep its category even if it was deleted from the list.
                if let e = entry, isIncome == e.isIncome { category = e.category; return }
                if !state.ledger.categories(income: isIncome).contains(category) { category = "其他" }
            }
            TextField("金额", text: $amountText).textFieldStyle(.roundedBorder).font(.title3)
            Picker("分类", selection: $category) {
                ForEach(categoryOptions, id: \.self) { Text($0).tag($0) }
            }
            DayField(label: "日期", day: dayBinding($day), latest: state.today)
            TextField("备注", text: $note).textFieldStyle(.roundedBorder)
            HStack {
                if let entry {
                    Button("删除", role: .destructive) { state.ledger.delete(entry.id); onClose() }
                }
                Spacer()
                Button("取消", action: onClose).keyboardShortcut(.cancelAction)
                Button("保存", action: save).keyboardShortcut(.defaultAction).disabled(cents == nil)
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear(perform: load)
    }

    private var categoryOptions: [String] {
        var list = state.ledger.categories(income: isIncome)
        if !list.contains(category) { list.append(category) }
        return list
    }

    private func load() {
        guard let e = entry ?? prefill else { day = state.today.date(); return }
        if entry == nil, e.amount == 0 {
            isIncome = e.isIncome; category = e.category; day = e.day.date(); note = e.note
            return
        }
        isIncome = e.isIncome
        amountText = String(format: e.amount % 100 == 0 ? "%.0f" : "%.2f", Double(e.amount) / 100)
        category = e.category
        day = e.day.date()
        note = e.note
    }

    private func save() {
        guard let cents else { return }
        let n = note.trimmingCharacters(in: .whitespaces)
        let d = DayKey.from(day)
        if let entry {
            state.ledger.update(entry.id) {
                $0.amount = cents; $0.isIncome = isIncome; $0.category = category; $0.day = d; $0.note = n.isEmpty ? category : n
            }
        } else {
            state.ledger.add(LedgerEntry(amount: cents, isIncome: isIncome, category: category,
                                         note: n.isEmpty ? category : n, day: d), now: Date())
        }
        onClose()
    }
}


// MARK: Flow

struct FlowList: View {
    @ObservedObject var state: AppState
    let entries: [LedgerEntry]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if entries.isEmpty {
                    Text("无记录").foregroundStyle(.secondary).padding(.vertical, 20)
                }
                ForEach(dayGroups(entries)) { g in
                    HStack {
                        Text(Fmt.title(g.day, today: state.today)).font(.caption.weight(.semibold))
                        Spacer()
                        if g.income > 0 { Text("收入 \(money(g.income))").font(.caption).foregroundStyle(LedgerColors.income) }
                        if g.expense > 0 { Text("支出 \(money(g.expense))").font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(.top, 12).padding(.bottom, 4)
                    ForEach(g.entries) { LedgerRow(state: state, entry: $0) }
                }
            }
        }
    }
}

struct LedgerRow: View {
    @ObservedObject var state: AppState
    let entry: LedgerEntry
    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            HStack(spacing: 8) {
                // Icon and category read as one chip, so the icon never seems to describe the note.
                let tint = CategoryIcon.tint(entry.category, isIncome: entry.isIncome, data: state.ledger)
                HStack(spacing: 4) {
                    Image(systemName: CategoryIcon.symbol(entry.category)).font(.system(size: 10, weight: .semibold))
                    Text(entry.category).font(.caption.weight(.medium))
                }
                .foregroundStyle(tint)
                .padding(.leading, 6).padding(.trailing, 8).padding(.vertical, 3)
                .background(tint.opacity(0.13), in: Capsule())
                .frame(minWidth: 58, alignment: .leading)  // notes line up in one column
                let note = entry.note.trimmingCharacters(in: .whitespaces)
                if !note.isEmpty { Text(note).lineLimit(1) }
                Spacer()
                Text((entry.isIncome ? "+" : "-") + money(entry.amount))
                    .monospacedDigit()
                    .foregroundStyle(entry.isIncome ? LedgerColors.income : .primary)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowHover()
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
        .popover(isPresented: $editing) { LedgerForm(state: state, entry: entry) { editing = false } }
    }
}

// MARK: Stats

struct LedgerStats: View {
    @ObservedObject var state: AppState
    let year: Int
    let month: Int
    @State private var income = false
    @State private var custom = false
    @State private var from = Date()
    @State private var to = Date()

    private static let palette: [Color] = [
        Color(red: 0.184, green: 0.435, blue: 0.929), Color(red: 0.941, green: 0.541, blue: 0.141),
        Color(red: 0.122, green: 0.643, blue: 0.388), Color(red: 0.557, green: 0.357, blue: 0.847),
        Color(red: 0.898, green: 0.282, blue: 0.302), Color(red: 0.0, green: 0.62, blue: 0.70),
        Color(red: 0.75, green: 0.6, blue: 0.1), Color.gray,
    ]

    private var range: (DayKey, DayKey) {
        if custom { return (DayKey.from(min(from, to)), DayKey.from(max(from, to))) }
        let first = DayKey(year: year, month: month, day: 1)!
        var next = DayKey(year: month == 12 ? year + 1 : year, month: month == 12 ? 1 : month + 1, day: 1)!
        next = next.adding(days: -1)
        return (first, next)
    }

    var body: some View {
        let (a, b) = range
        let share = categoryShare(state.ledger, from: a, to: b, income: income)
        let total = max(share.reduce(0) { $0 + $1.amount }, 1)
        let trend = monthlyTrend(state.ledger, endingYear: year, month: month, months: 6)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Text("分类占比").font(.headline)
                    Spacer()
                    SoftSegments(selection: $custom, options: [(false, "本月"), (true, "自选")])
                    SoftSegments(selection: $income, options: [(false, "支出"), (true, "收入")])
                }
                if custom {
                    RangeField(label: "范围", from: dayBinding($from), to: dayBinding($to), latest: state.today)
                        .fixedSize()
                }
                if share.isEmpty {
                    Text("无记录").foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .center, spacing: 28) {
                        Chart(share) { c in
                            SectorMark(angle: .value("金额", c.amount), innerRadius: .ratio(0.55), angularInset: 1.5)
                                .cornerRadius(3)
                                .foregroundStyle(color(for: c, in: share))
                        }
                        .chartBackground { _ in
                            VStack(spacing: 2) {
                                Text(income ? "收入" : "支出").font(.caption).foregroundStyle(.secondary)
                                Text(money(total)).font(.headline).monospacedDigit()
                            }
                        }
                        .frame(width: 200, height: 200)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(share) { c in
                                HStack(spacing: 8) {
                                    Circle().fill(color(for: c, in: share)).frame(width: 9, height: 9)
                                    Text(c.category).frame(width: 56, alignment: .leading)
                                    Text(money(c.amount)).monospacedDigit().frame(width: 96, alignment: .trailing)
                                    Text("\(Int((Double(c.amount) / Double(total) * 100).rounded()))%")
                                        .foregroundStyle(.secondary).monospacedDigit().frame(width: 40, alignment: .trailing)
                                }
                            }
                        }
                        Spacer()
                    }
                }

                Text("近 6 个月").font(.headline).padding(.top, 6)
                Chart {
                    ForEach(trend) { p in
                        BarMark(x: .value("月", "\(p.month)月"), y: .value("金额", Double(p.totals.income) / 100))
                            .foregroundStyle(by: .value("类型", "收入"))
                            .position(by: .value("类型", "收入"))
                        BarMark(x: .value("月", "\(p.month)月"), y: .value("金额", Double(p.totals.expense) / 100))
                            .foregroundStyle(by: .value("类型", "支出"))
                            .position(by: .value("类型", "支出"))
                    }
                    ForEach(trend) { p in
                        LineMark(x: .value("月", "\(p.month)月"), y: .value("金额", Double(p.totals.net) / 100))
                            .foregroundStyle(by: .value("类型", "净收入"))
                            .symbol(.circle)
                    }
                }
                .chartForegroundStyleScale(["收入": LedgerColors.income, "支出": Theme.color(for: .day), "净收入": Color.orange])
                .frame(height: 220)
            }
            .padding(.top, 4)
        }
        .onAppear {
            from = range.0.date()
            to = range.1.date()
        }
    }

    /// Expenses match the flow list's icon colours; income (all green there) goes by rank.
    private func color(for c: CategoryAmount, in list: [CategoryAmount]) -> Color {
        if !income { return CategoryIcon.tint(c.category, isIncome: false, data: state.ledger) }
        let i = list.firstIndex { $0.category == c.category } ?? 0
        return Self.palette[i % Self.palette.count]
    }
}

// MARK: Categories

struct CategorySheet: View {
    @ObservedObject var state: AppState
    let onClose: () -> Void
    @State private var income = false
    @State private var newName = ""
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var conflict: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SoftSegments(selection: $income, options: [(false, "支出"), (true, "收入")])
            List {
                ForEach(state.ledger.categories(income: income), id: \.self) { c in
                    HStack {
                        if renaming == c {
                            TextField("", text: $renameText).onSubmit {
                                let n = renameText.trimmingCharacters(in: .whitespaces)
                                if n != c && state.ledger.categories(income: income).contains(n) {
                                    conflict = "已有「\(n)」"
                                } else {
                                    state.ledger.renameCategory(c, to: n, income: income); renaming = nil; conflict = nil
                                }
                            }
                        } else {
                            Text(c)
                        }
                        Spacer()
                        Button { renaming = c; renameText = c } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless).disabled(c == "其他")
                        Button { state.ledger.removeCategory(c, income: income) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).disabled(c == "其他")
                    }
                }
            }
            .frame(height: 260)
            if let conflict { Text(conflict).font(.caption).foregroundStyle(.red) }
            HStack {
                TextField("新分类", text: $newName).textFieldStyle(.roundedBorder)
                    .onSubmit { state.ledger.addCategory(newName, income: income); newName = "" }
                Button("添加") { state.ledger.addCategory(newName, income: income); newName = "" }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack { Spacer(); Button("完成", action: onClose).keyboardShortcut(.defaultAction) }
        }
        .padding(18)
        .frame(width: 340)
    }
}
