import CreCore
import SwiftUI
import WidgetKit

/// Where the phone keeps its files: the App Group container shared with the widgets and the share extension.
enum MobileFiles {
    static let group = "group.com.lty.cre.mobile"

    static var directory: URL {
        if DemoData.isOn { return DemoData.directory }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    /// Plan 1 kept data.json in Documents; move it once into the shared container.
    static func migrateFromDocuments() {
        guard !DemoData.isOn else { return }
        // Plan 1 kept 新的一天开始时间 in UserDefaults.
        if let old = UserDefaults.standard.object(forKey: "dayStartHour") as? Int {
            if !FileManager.default.fileExists(atPath: url("day-start.json").path) { saveDayStart(DayStartSetting(hour: old, modifiedAt: nil), to: url("day-start.json")) }
            UserDefaults.standard.removeObject(forKey: "dayStartHour")
        }
        let fm = FileManager.default
        let old = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("data.json")
        let new = url("data.json")
        guard old != new, fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fm.moveItem(at: old, to: new)
    }
}

/// The phone's single source of truth: plan, ledger and schedule data, the real "today", and the day being viewed.
@MainActor
final class MobileState: ObservableObject {
    let store: PlanStore
    let ledgerStore: LedgerStore
    let scheduleStore: ScheduleStore

    @Published var data: PlanData {
        didSet {
            guard !applyingExternal, !stamping else { return }
            stamp(\.data, data.stamped(since: oldValue, now: Date()))
            save()
            remember(oldValue, \.data)
        }
    }
    @Published var ledger: LedgerData {
        didSet {
            guard !applyingExternal, !stamping else { return }
            stamp(\.ledger, ledger.stamped(since: oldValue, now: Date()))
            try? ledgerStore.save(ledger)
            remember(oldValue, \.ledger)
            changed()
        }
    }
    @Published var schedule: ScheduleData {
        didSet {
            guard !applyingExternal, !stamping else { return }
            stamp(\.schedule, schedule.stamped(since: oldValue, now: Date()))
            try? scheduleStore.save(schedule)
            remember(oldValue, \.schedule)
            changed()
        }
    }
    @Published private(set) var today: DayKey
    @Published var viewingDay: DayKey
    @Published var sortMode: SortMode = SortMode(rawValue: UserDefaults.standard.string(forKey: "sortMode") ?? "") ?? .priority {
        didSet { UserDefaults.standard.set(sortMode.rawValue, forKey: "sortMode") }
    }
    @Published var filter: AgendaFilter = .all
    /// 新的一天从几点开始 (0–6).
    /// Kept in day-start.json in the shared container, so the widgets use the same day.
    @Published var dayStartHour: Int = loadDayStartHour(MobileFiles.url("day-start.json")) {
        didSet {
            if !applyingExternal {
                saveDayStartHour(dayStartHour, to: MobileFiles.url("day-start.json"))
                onChange?()
                WidgetCenter.shared.reloadAllTimelines()
            }
            refreshToday()
        }
    }

    /// 新的一天开始时间 with when it was last changed, for sync.
    var dayStart: DayStartSetting { loadDayStart(MobileFiles.url("day-start.json")) }

    /// Everything the phone syncs.
    var syncPayload: SyncPayload { SyncPayload(plan: data, ledger: ledger, schedule: schedule, dayStart: dayStart) }

    /// Takes in a merged sync result as is (stamps kept, no undo step).
    func applySynced(_ p: SyncPayload) {
        // Undo snapshots predate what the Mac sent; undoing one would delete or revert the Mac's changes.
        if p.plan != data || p.ledger != ledger || p.schedule != schedule { undoManager.removeAllActions() }
        applyExternal(plan: p.plan, ledger: p.ledger, schedule: p.schedule)
        if p.dayStart != dayStart {
            saveDayStart(p.dayStart, to: MobileFiles.url("day-start.json"))
            applyingExternal = true
            dayStartHour = p.dayStart.hour
            applyingExternal = false
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    /// The app's own undo history; shaking the phone offers to undo the last change.
    let undoManager = UndoManager()
    /// Called after every local change (sync waits a moment, then sends).
    var onChange: (() -> Void)?

    private var stamping = false
    private var applyingExternal = false
    private var rollover: Timer?

    init() {
        MobileFiles.migrateFromDocuments()
        store = PlanStore(fileURL: MobileFiles.url("data.json"))
        ledgerStore = LedgerStore(fileURL: MobileFiles.url("ledger.json"))
        scheduleStore = ScheduleStore(fileURL: MobileFiles.url("schedule.json"))
        let now = logicalDay(DemoData.fixedNow ?? Date(), startHour: loadDayStartHour(MobileFiles.url("day-start.json")))
        today = now
        viewingDay = now
        if DemoData.isOn {
            data = DemoData.make(today: now)
            ledger = DemoData.makeLedger(today: now)
            schedule = DemoData.makeSchedule(today: now)
        } else {
            data = store.load()
            ledger = ledgerStore.load()
            schedule = scheduleStore.load()
        }
        scheduleRollover()
        NotificationCenter.default.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshToday() }
        }
    }

    private func stamp<V: Equatable>(_ path: ReferenceWritableKeyPath<MobileState, V>, _ value: V) {
        guard self[keyPath: path] != value else { return }
        stamping = true
        self[keyPath: path] = value
        stamping = false
    }

    private func remember<V>(_ old: V, _ path: ReferenceWritableKeyPath<MobileState, V>) {
        undoManager.registerUndo(withTarget: self) { s in s[keyPath: path] = old }
    }

    private func save() {
        guard !store.isReadOnly else { return }
        try? store.save(data)
        changed()
    }

    private func changed() {
        WidgetCenter.shared.reloadAllTimelines()
        onChange?()
    }

    /// Writes data that already carries its own stamps (a sync result): no new stamps, no undo step.
    func applyExternal(plan: PlanData? = nil, ledger newLedger: LedgerData? = nil, schedule newSchedule: ScheduleData? = nil) {
        applyingExternal = true
        if let plan, plan != data { data = plan; try? store.save(plan) }
        if let newLedger, newLedger != ledger { ledger = newLedger; try? ledgerStore.save(newLedger) }
        if let newSchedule, newSchedule != schedule { schedule = newSchedule; try? scheduleStore.save(newSchedule) }
        applyingExternal = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Picks up writes made by the widgets or the quick-add shortcut while the app was in the background.
    func reloadFromDisk() {
        guard !DemoData.isOn else { return }
        applyExternal(plan: store.load(), ledger: ledgerStore.load(), schedule: scheduleStore.load())
    }

    var isViewingToday: Bool { viewingDay == today }

    func refreshToday(now: Date = DemoData.fixedNow ?? Date()) {
        defer { scheduleRollover(after: now) }
        let newToday = logicalDay(now, startHour: dayStartHour)
        guard newToday != today else { return }
        viewingDay = advanceViewing(viewing: viewingDay, oldToday: today, newToday: newToday)
        today = newToday
    }

    /// Fires once at the next day start so "today" moves on while the app stays open.
    private func scheduleRollover(after now: Date = DemoData.fixedNow ?? Date()) {
        rollover?.invalidate()
        guard DemoData.fixedNow == nil else { return }
        let at = nextRefresh(after: now, startHour: dayStartHour)
        rollover = Timer.scheduledTimer(withTimeInterval: max(1, at.timeIntervalSince(now) + 1), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refreshToday() }
        }
    }

    func agendaForViewingDay() -> Agenda {
        filtered(agenda(for: viewingDay, today: today, data: data, sort: sortMode), by: filter, data: data)
    }

    @discardableResult
    func add(_ raw: String, override: TimeChoice? = nil, groupID: UUID? = nil, defaultToViewingDay: Bool = true) -> Bool {
        data.addLine(raw, override: override, groupID: groupID, viewingDay: defaultToViewingDay ? viewingDay : nil,
                     today: today, now: Date()) != nil
    }

    func toggle(_ entry: AgendaEntry) {
        let now = Date()
        if entry.isGroupRow {
            data.toggleGroupRow(groupID: entry.id, on: viewingDay, today: today, now: now)
        } else if entry.kind == .repeating {
            data.toggleRepeat(todoID: entry.id, on: viewingDay, now: now)
        } else {
            data.toggle(todoID: entry.id, on: viewingDay, today: today, now: now)
        }
    }

    func toggleItem(todoID: UUID, itemID: UUID) {
        data.toggleRepeatItem(todoID: todoID, itemID: itemID, on: viewingDay, now: Date())
    }

    func togglePulledTag(_ tag: String) {
        var list = data.pulledTags[viewingDay] ?? []
        if let i = list.firstIndex(of: tag) { list.remove(at: i) } else { list.append(tag) }
        data.pulledTags[viewingDay] = list.isEmpty ? nil : list
    }

    func summarizeToday() { data.generateSummary(day: today, now: Date()) }

    var triageCount: Int { triageCandidates(today: today, data: data).count }

    func todo(_ id: UUID) -> Todo? { data.todos.first { $0.id == id } }
}
