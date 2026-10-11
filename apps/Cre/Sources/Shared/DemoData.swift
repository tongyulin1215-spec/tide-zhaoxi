import CreCore
import Foundation

/// Example data for screenshots and manual checks. Only used when launched with CRE_DEMO=1,
/// and then stored in a temporary file so real data is never touched.
enum DemoData {
    #if PUBLIC_DEMO
    /// The public edition (for people trying 朝夕) always runs on example data.
    static var isOn: Bool { true }
    #else
    static var isOn: Bool { ProcessInfo.processInfo.environment["CRE_DEMO"] == "1" }
    #endif

    static var storeURL: URL { directory.appendingPathComponent("data.json") }

    /// Temporary folder holding the demo's data, ledger and schedule files.
    static var directory: URL {
        #if PUBLIC_DEMO
        // Its own folder, nowhere near a real 朝夕's data.
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TideDemo")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
        #else
        return FileManager.default.temporaryDirectory.appendingPathComponent("cre-demo")
        #endif
    }

    /// CRE_TODAY=2026-10-09 pins the demo's clock to noon that day, so UI tests don't depend on the real date.
    static var fixedNow: Date? {
        guard isOn, let s = ProcessInfo.processInfo.environment["CRE_TODAY"], let d = DayKey(string: s) else { return nil }
        return d.date(hour: 12)
    }

    static func make(today: DayKey) -> PlanData {
        var d = PlanData()
        let now = today.adding(days: -3).date()

        @discardableResult
        func add(_ text: String, _ s: Schedule, _ p: Priority? = nil, group: UUID? = nil) -> UUID {
            let id = d.addTodo(text, schedule: s, groupID: group, tags: [], now: now)!
            d.update(id) { $0.priority = p }
            return id
        }

        add("买香蕉", .deadline(today.adding(days: 1)), .p0)
        add("交周报", .day(today.adding(days: -2)), .p1)
        add("交季度报告", .deadline(today.adding(days: 12)), .p1)
        add("续费域名", .deadline(today.adding(days: 20)))
        let mail = add("回复邮件", .day(today))
        d.toggle(todoID: mail, on: today, now: Date())

        let fit = d.addGroup("健身", kind: .cycle, schedule: Repeat(weekdays: [2, 3, 4, 5, 6, 7], start: today.adding(days: -7),
            plan: DayPlan(mode: .fixedWeekday, days: [
                PlanDay(name: "练胸", weekday: 2, items: [PlanItem(text: "卧推 4×8"), PlanItem(text: "上斜推举 3×10"), PlanItem(text: "飞鸟 3×12")]),
                PlanDay(name: "练背", weekday: 3, items: [PlanItem(text: "引体向上 4×6"), PlanItem(text: "划船 4×10")]),
                PlanDay(name: "练腿", weekday: 4, items: [PlanItem(text: "深蹲 5×5"), PlanItem(text: "硬拉 3×5"), PlanItem(text: "箭步蹲 3×10")]),
                PlanDay(name: "练肩", weekday: 5, items: [PlanItem(text: "推举 4×8")]),
                PlanDay(name: "练臂", weekday: 6, items: [PlanItem(text: "弯举 4×10")]),
                PlanDay(name: "核心", weekday: 7, items: [PlanItem(text: "平板支撑 3×1分钟")]),
            ])), now: now)
        d.updateGroup(fit) { $0.todayDisplay = .expanded }

        let read = d.addGroup("读书", kind: .list(standard: "1 小时"), schedule: Repeat(start: today.adding(days: -7)), now: now)
        let book = add("人类简史", .none, group: read)
        d.setOngoing(book, true)
        add("置身事内", .none, group: read)
        add("三体", .none, group: read)
        if let anchor = d.anchor(of: read) { d.toggleRepeat(todoID: anchor.id, on: today, now: Date()) }

        let game = d.addGroup("做一款游戏", kind: .phase, now: now)
        add("学习", .span(start: today.adding(days: -2), end: today.adding(days: 4)), group: game)
        add("上手", .span(start: today.adding(days: 5), end: today.adding(days: 11)), group: game)

        add("换个新键盘", .none)
        d.notes[today] = "上午效率不错，下午被会议打断。"
        d.generateSummary(day: today.adding(days: -1), now: today.adding(days: -1).date(hour: 22))
        d.generateSummary(day: today.adding(days: -2), now: today.adding(days: -2).date(hour: 22))
        d.generateSummary(day: today, now: Date())
        let doc = add("整理文档", .none)
        d.update(doc) { $0.tags = ["工作"] }
        d.update(mail) { $0.tags = ["工作"] }
        if let a = d.anchor(of: read) {
            for back in 1...5 { d.toggleRepeat(todoID: a.id, on: today.adding(days: -back), now: Date()) }
        }
        let old = d.addGroup("搬家", now: now)
        add("退押金", .none, group: old)
        d.updateGroup(old) { $0.isArchived = true }
        d.updateGroup(fit) { $0.isPinned = true }
        let t = d.addTemplate(name: "本周总结", scope: .all, period: .thisWeek, metrics: SummaryMetric.allCases, now: now)
        d.generate(templateID: t, today: today, now: Date())
        return d
    }

    static func makeLedger(today: DayKey) -> LedgerData {
        var l = LedgerData()
        func add(_ yuan: Double, _ income: Bool, _ cat: String, _ note: String, _ back: Int) {
            l.add(LedgerEntry(amount: Int(yuan * 100), isIncome: income, category: cat, note: note,
                              day: today.adding(days: -back)), now: today.adding(days: -back).date(hour: 12 + back % 6))
        }
        add(12000, true, "工资", "工资", 3)
        add(35, false, "餐饮", "午饭", 0)
        add(6, false, "交通", "地铁", 0)
        add(23.5, false, "交通", "打车", 1)
        add(28, false, "餐饮", "晚饭", 1)
        add(4200, false, "居住", "房租", 3)
        add(199, false, "购物", "运动鞋", 2)
        add(60, false, "娱乐", "电影", 2)
        for back in 30...170 where back % 9 == 0 {
            add(Double(80 + back), false, back % 2 == 0 ? "餐饮" : "购物", "日常", back)
        }
        for back in [33, 63, 94, 124, 155] { add(12000, true, "工资", "工资", back); add(4200, false, "居住", "房租", back) }
        return l
    }

    static func makeSchedule(today: DayKey) -> ScheduleData {
        var s = ScheduleData()
        let monday = today.adding(days: -((today.weekday + 5) % 7))
        s.add(title: "读书 1 小时", day: monday, start: 7 * 60, end: 8 * 60, repeats: .daily)
        s.add(title: "健身", day: monday, start: 19 * 60, end: 20 * 60 + 30, repeats: .weekly([2, 4, 6]))
        s.add(title: "组会", day: today, start: 10 * 60, end: 11 * 60 + 30)
        s.add(title: "交周报", day: today, start: 11 * 60, end: 11 * 60 + 45)
        s.add(title: "Apex练枪半小时", day: today.adding(days: 1), start: 21 * 60, end: 21 * 60 + 30)
        return s
    }
}
