import AppKit
import CreCore
import SwiftUI
import WidgetKit

enum AppSection: String, CaseIterable, Identifiable {
    case home, planning, schedule, ledger, summary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .planning: "规划"
        case .schedule: "日程"
        case .ledger: "记账"
        case .summary: "总结"
        }
    }

    var icon: String {
        switch self {
        case .home: "sun.horizon"
        case .planning: "list.bullet.rectangle"
        case .schedule: "calendar.day.timeline.left"
        case .ledger: "creditcard"
        case .summary: "chart.bar"
        }
    }
}

/// The app's single source of truth: plan data, the real "today", and the day being viewed.
@MainActor
final class AppState: ObservableObject {
    @Published var data: PlanData {
        didSet {
            guard !applyingExternal, !stamping else { return }
            let stamped = data.stamped(since: oldValue, now: Date())
            if stamped != data { stamping = true; data = stamped; stamping = false }
            save()
            remember(oldValue, \.data)
        }
    }
    /// The main window's undo manager: every user change to todos, ledger and schedule can be undone with ⌘Z.
    weak var undoManager: UndoManager?

    /// Registers "put it back" for one change; doing so during an undo registers the redo.
    private func remember<V>(_ old: V, _ path: ReferenceWritableKeyPath<AppState, V>) {
        undoManager?.registerUndo(withTarget: self) { s in s[keyPath: path] = old }
    }
    /// True while taking in a change made by the widget, so it isn't saved straight back.
    private var applyingExternal = false
    /// True while writing sync stamps back, so that write isn't saved or registered for undo twice.
    private var stamping = false

    // Writing the stamped value back goes through the setter directly, never via inout:
    // an inout write-back re-runs didSet even when nothing changed, which loops forever.
    @Published private(set) var today: DayKey
    @Published var viewingDay: DayKey
    @Published var section: AppSection = .home
    /// Bumped when "today" is cleared, so views can celebrate.
    @Published var celebrateToken = 0
    /// Set by "整理拖延" or the Friday prompt; the triage sheet observes it.
    @Published var showTriage = false
    /// The global hotkey couldn't be registered (another app holds it).
    @Published var hotKeyFailed = false
    /// Captured from the main scene so the widget can reopen the main window.
    var openMainWindow: (() -> Void)?
    @Published var filter: AgendaFilter = {
        guard let d = UserDefaults.standard.data(forKey: "agendaFilter"),
              let f = try? JSONDecoder().decode(AgendaFilter.self, from: d) else { return .all }
        return f
    }() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(filter), forKey: "agendaFilter") }
    }

    /// The filter's label for the header ("#秋招" / group name), nil for 全部.
    var filterLabel: String? {
        switch filter {
        case .all: return nil
        case .tag(let t): return "#" + t
        case .group(let g): return data.group(g)?.name
        }
    }
    @Published var sortMode: SortMode = SortMode(rawValue: UserDefaults.standard.string(forKey: "sortMode") ?? "") ?? .priority {
        didSet { UserDefaults.standard.set(sortMode.rawValue, forKey: "sortMode") }
    }

    let store: PlanStore
    let ledgerStore: LedgerStore
    @Published var ledger: LedgerData {
        didSet {
            guard !applyingExternal, !stamping else { return }
            let stamped = ledger.stamped(since: oldValue, now: Date())
            if stamped != ledger { stamping = true; ledger = stamped; stamping = false }
            saveLedger()
            remember(oldValue, \.ledger)
        }
    }
    let scheduleStore: ScheduleStore
    /// 日程: separate file, never touches todos.
    @Published var schedule: ScheduleData {
        didSet {
            guard !applyingExternal, !stamping else { return }
            let stamped = schedule.stamped(since: oldValue, now: Date())
            if stamped != schedule { stamping = true; schedule = stamped; stamping = false }
            saveSchedule()
            remember(oldValue, \.schedule)
        }
    }
    /// The day the summary page shows.
    @Published var summaryDay: DayKey
    /// 新的一天从几点开始 (0–6). Shared with the widget.
    @Published var dayStartHour: Int = loadDayStartHour(AppState.dayStartFile) {
        didSet {
            if !applyingExternal { saveDayStartHour(dayStartHour, to: AppState.dayStartFile) }
            refreshToday()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    /// A custom report shown on the summary page instead of a day (nil = show `summaryDay`).
    @Published var summaryReportID: UUID?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var syncTimer: Timer?
    private var widgetBasis: (todos: [Todo], groups: [TodoGroup], pulled: [DayKey: [String]]) = ([], [], [:])

    /// Demo file, else the App Group file shared with the widget (migrating old data once), else the old location.
    nonisolated static func makeStore() -> PlanStore {
        if DemoData.isOn { return PlanStore(fileURL: DemoData.storeURL) }
        if let shared = PlanStore.sharedURL() {
            let migrated = migrateLegacyData(from: PlanStore.defaultURL, to: shared)
            launchLog("store=\(shared.path) migrated=\(migrated) sharedExists=\(FileManager.default.fileExists(atPath: shared.path))")
            return PlanStore(fileURL: shared)
        }
        launchLog("store=legacy (no app group container)")
        return PlanStore(fileURL: PlanStore.defaultURL)
    }

    nonisolated static func makeLedgerStore() -> LedgerStore {
        if DemoData.isOn { return LedgerStore(fileURL: DemoData.storeURL.deletingLastPathComponent().appendingPathComponent("ledger.json")) }
        if let shared = LedgerStore.sharedURL() { return LedgerStore(fileURL: shared) }
        return LedgerStore(fileURL: PlanStore.defaultURL.deletingLastPathComponent().appendingPathComponent("ledger.json"))
    }

    /// One line per launch in ~/Library/Logs/Tide.log, for diagnosing where data lives.
    nonisolated static func launchLog(_ line: String) {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/Tide.log")
        let text = "\(Date()) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    init(store: PlanStore = AppState.makeStore()) {
        self.store = store
        let now = logicalDay(Date(), startHour: loadDayStartHour(AppState.dayStartFile))
        today = now
        viewingDay = now
        data = DemoData.isOn ? DemoData.make(today: now) : store.load()
        ledgerStore = AppState.makeLedgerStore()
        ledger = DemoData.isOn ? DemoData.makeLedger(today: now) : ledgerStore.load()
        scheduleStore = AppState.makeScheduleStore()
        schedule = DemoData.isOn ? DemoData.makeSchedule(today: now) : scheduleStore.load()
        summaryDay = now
        if DemoData.isOn {
            // Example data starts fresh every launch: write it out now, or the file watcher reloads last session's file.
            try? store.save(data); try? ledgerStore.save(ledger); try? scheduleStore.save(schedule)
        }
        if let s = ProcessInfo.processInfo.environment["CRE_SECTION"], let sec = AppSection(rawValue: s) { section = sec }
        if DemoData.isOn && ProcessInfo.processInfo.environment["CRE_TRIAGE"] == "1" { showTriage = true }
        if DemoData.isOn && ProcessInfo.processInfo.environment["CRE_REPORT"] == "1" { summaryReportID = data.reports.first?.id }

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshToday() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshToday() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshToday() }
        }
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pickUpExternalChanges() }
        }
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pickUpExternalChanges() }
        })
    }

    private func save() {
        guard !store.isReadOnly else { return }
        do {
            try store.save(data)
            // Only todos and groups show on the widget; notes and summaries don't need a reload.
            if data.todos != widgetBasis.todos || data.groups != widgetBasis.groups || data.pulledTags != widgetBasis.pulled {
                widgetBasis = (data.todos, data.groups, data.pulledTags)
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            NSLog("Cre save failed: \(error)")
        }
    }

    private func saveSchedule() {
        guard !scheduleStore.isReadOnly else { return }
        do { try scheduleStore.save(schedule) } catch { NSLog("Cre schedule save failed: \(error)") }
    }

    nonisolated static func makeScheduleStore() -> ScheduleStore {
        if DemoData.isOn { return ScheduleStore(fileURL: DemoData.storeURL.deletingLastPathComponent().appendingPathComponent("schedule.json")) }
        if let shared = ScheduleStore.sharedURL() { return ScheduleStore(fileURL: shared) }
        return ScheduleStore(fileURL: PlanStore.defaultURL.deletingLastPathComponent().appendingPathComponent("schedule.json"))
    }

    private func saveLedger() {
        guard !ledgerStore.isReadOnly else { return }
        do { try ledgerStore.save(ledger) } catch { NSLog("Cre ledger save failed: \(error)") }
    }

    /// 总结一下今天：generate today's summary and show it.
    func summarizeToday() {
        data.generateSummary(day: today, now: Date())
        summaryDay = today
        summaryReportID = nil
        section = .summary
    }

    /// day-start.json (a temporary copy in demo mode, so a demo sync never touches the real one).
    nonisolated static var dayStartFile: URL? {
        DemoData.isOn ? DemoData.directory.appendingPathComponent("day-start.json") : dayStartURL()
    }

    /// Everything this Mac syncs.
    var syncPayload: SyncPayload {
        SyncPayload(plan: data, ledger: ledger, schedule: schedule, dayStart: loadDayStart(AppState.dayStartFile))
    }

    /// Takes in a merged sync result as is: its stamps stay, and it's no undo step.
    func applySynced(_ p: SyncPayload) {
        // Undo snapshots predate what the phone sent; undoing one would delete or revert the phone's changes.
        if p.plan != data || p.ledger != ledger || p.schedule != schedule { undoManager?.removeAllActions() }
        applyingExternal = true
        if p.plan != data { data = p.plan; save() }
        if p.ledger != ledger { ledger = p.ledger; saveLedger() }
        if p.schedule != schedule { schedule = p.schedule; saveSchedule() }
        if p.dayStart != loadDayStart(AppState.dayStartFile) {
            saveDayStart(p.dayStart, to: AppState.dayStartFile)
            dayStartHour = p.dayStart.hour
        }
        applyingExternal = false
    }

    /// Takes in edits the desktop widget wrote to the shared file.
    func pickUpExternalChanges() {
        guard let fresh = store.loadIfChanged(), fresh != data else { return }
        applyingExternal = true
        data = fresh
        applyingExternal = false
    }

    /// Shown once at launch when the data file could not be read.
    var loadIssueMessage: String? {
        switch store.loadIssue {
        case .movedAside(let url)?: return "数据文件无法读取，已备份至：\n\(url.path)"
        case .unreadable?: return "数据文件无法读取，本次以只读方式打开，不会保存修改。\n\(store.fileURL.path)"
        case nil: break
        }
        switch ledgerStore.loadIssue {
        case .movedAside(let url)?: return "记账文件无法读取，已备份至：\n\(url.path)"
        case .unreadable?: return "记账文件无法读取，本次记账不会保存。\n\(ledgerStore.fileURL.path)"
        case nil: return nil
        }
    }

    var isViewingToday: Bool { viewingDay == today }

    func agendaForViewingDay() -> Agenda {
        filtered(agenda(for: viewingDay, today: today, data: data, sort: sortMode), by: filter, data: data)
    }

    func refreshToday(now: Date = Date()) {
        let newToday = logicalDay(now, startHour: dayStartHour)
        guard newToday != today else {
            objectWillChange.send() // minute tick: lets triage and clocks re-evaluate
            return
        }
        viewingDay = advanceViewing(viewing: viewingDay, oldToday: today, newToday: newToday)
        today = newToday
    }

    // MARK: Actions

    /// Adds one line of input. `override` wins over the parsed time; on a future/past view an
    /// undated line becomes a todo for that day.
    @discardableResult
    func add(_ raw: String, override: TimeChoice? = nil, groupID: UUID? = nil, defaultToViewingDay: Bool = true) -> Bool {
        data.addLine(raw, override: override, groupID: groupID, viewingDay: defaultToViewingDay ? viewingDay : nil,
                     today: today, now: Date()) != nil
    }

    func editText(_ id: UUID, _ text: String) { data.rename(id, text) }

    func setTime(_ id: UUID, _ choice: TimeChoice) { data.setTime(id, choice) }

    /// Pull a tag's items into (or out of) the viewed day.
    func togglePulledTag(_ tag: String) {
        var list = data.pulledTags[viewingDay] ?? []
        if let i = list.firstIndex(of: tag) { list.remove(at: i) } else { list.append(tag) }
        data.pulledTags[viewingDay] = list.isEmpty ? nil : list
    }

    var triageCount: Int { triageCandidates(today: today, data: data).count }

    func toggle(_ entry: AgendaEntry) {
        let wasCleared = isCleared
        let now = Date()
        if entry.isGroupRow {
            data.toggleGroupRow(groupID: entry.id, on: viewingDay, today: today, now: now)
        } else if entry.kind == .repeating {
            data.toggleRepeat(todoID: entry.id, on: viewingDay, now: now)
        } else {
            data.toggle(todoID: entry.id, on: viewingDay, today: today, now: now)
        }
        if !wasCleared && isCleared { celebrateToken += 1 }
    }

    func toggleItem(todoID: UUID, itemID: UUID) {
        let wasCleared = isCleared
        data.toggleRepeatItem(todoID: todoID, itemID: itemID, on: viewingDay, now: Date())
        if !wasCleared && isCleared { celebrateToken += 1 }
    }

    private var isCleared: Bool {
        guard isViewingToday else { return false }
        let p = agenda(for: today, today: today, data: data).progress
        return p.total > 0 && p.done == p.total
    }

    func todo(_ id: UUID) -> Todo? { data.todos.first { $0.id == id } }
}

/// What the edit card / date button produces: a schedule plus a priority.
