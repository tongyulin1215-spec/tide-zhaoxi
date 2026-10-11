# Cre 第一版 · 计划 1：待办与规划 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做出可以每天自己用的 Mac App 核心：小窗口（随手记、看今天、勾选、钉在桌面）和完整 App 的首页、规划板块，包含四种待办、DDL 折叠、顺延、周五清理、按天安排、"进行中"标记、日历跳转。

**Architecture:** 一个 SwiftPM 包 `apps/Cre`，分两个 target：`CreCore` 是纯 Foundation 的领域逻辑（模型、"某天该显示什么"的计算、时间识别、持久化），全部用单元测试覆盖；`Cre` 是 SwiftUI + AppKit 的界面层（主窗口、菜单栏、全局快捷键、小窗口面板），只调用 `CreCore`。日期一律用自定义的 `DayKey`（年-月-日）做计算，避免时区和夏令时问题。数据存成一个 JSON 文件，沿用 CreTodo 原型"读不出来就先备份、绝不覆盖"的做法。

**Tech Stack:** Swift 6.4、SwiftPM、SwiftUI + AppKit（macOS 14+）、Carbon `RegisterEventHotKey`（全局快捷键，无需辅助功能权限）、Swift Testing（`import Testing`）。

**Spec:** `docs/开发过程/specs/2026-10-03-product-form-design.md`

**范围说明：** 产品文档覆盖三个相对独立的部分。本计划只做"待办与规划"（文档第 2、3 节及第 6 节第一版里对应的条目）。记账（第 5 节）和总结（第 4 节）各自另写计划 2、计划 3，在本计划完成后进行；本计划在侧边栏里为它们留占位页。

## Global Constraints

- 平台：macOS 14 起；只做 Mac，不做 iPhone 和同步。
- 工作名 `Cre`（App 名、数据目录名均为占位，产品命名后统一替换）。数据文件：`~/Library/Application Support/Cre/data.json`。
- 待办就是一句话：`Todo.text` 单行，没有详情字段。
- 四种待办：指定日、DDL、阶段、每日重复；另有"不设时间"只留在规划里。
- DDL 标签文案：`DDL M月d日`（例："DDL 10月8日"）。
- DDL 折叠阈值：剩余天数 ≤ 3 天的单独显示，其余收进"DDL 待办（N）"折叠组。
- 阶段待办在今日视图里没有勾选框，只能在规划里勾。
- 每日重复：每天，或每周选几天；按天安排内容时可选"按星期固定"或"按顺序轮换"。
- ▶ 的含义："今天具体做什么"——有按天安排时显示当天名称，否则显示同组标为进行中的待办（多条用"、"连接）。
- 不设今日数量上限。
- 周五清理：每周五 19:00 起出现，选项只有"今天做""改个日期"。
- 过期的 DDL：暂按指定日待办同样顺延并标出逾期天数；没做的每日重复不顺延（文档第 8 节暂定）。
- 补勾：在过去某天的视图里可勾选，算作那天完成。
- Mac 端输入条一律在顶部。
- 小窗口钉住时不置顶：放在桌面图标之上、普通窗口之下。
- 全局快捷键默认 ⌃⌥Space（暂定，之后在设置里可改）。
- 界面颜色全部取自 `Theme`，视觉风格待定，先用系统中性色占位，四种待办的颜色集中定义在一处。
- 界面文案全部中文。

## Review Focus

1. **跨过午夜**：App 一直开着过了 0 点，"今天"必须切到新的一天（顺延、DDL 天数、重复项都跟着变），而不是停在打开 App 的那天。→ Task 9 加测试 `todayAdvancesAtMidnight`。
2. **输入里混着数字但不是日期**："买 2 斤香蕉""读 10.5 页"——"2"不能被当成日期；"10.5"只有在月、日都合法、且不是紧跟"页/元/斤/个/公里/km"等单位时才算日期。→ Task 8 测试 `numbersThatAreNotDates`。
3. **跨年**：12 月里输入"1月3日 交房租"应是明年 1 月 3 日；"12.28–1.3"的阶段跨年。→ Task 8 测试 `pastMonthDayMeansNextYear`、`spanAcrossYearEnd`。
4. **改动按天安排后的轮换**：轮换模式下删掉或新增一个训练日，今天显示的内容不能越界崩溃，按取模继续。→ Task 6 测试 `rotationSurvivesPlanDayRemoval`。
5. **删除带内容的模块组**：删组时组里的待办不能变成"幽灵"（引用不存在的组还出现在今日）；删组即一并删除组内待办，并需二次确认。→ Task 3 测试 `deletingGroupRemovesItsTodos`。

---

## 文件结构

```
apps/Cre/
  Package.swift
  Info.plist
  build.sh                         # 打包并安装到 ~/Applications/Cre.app
  Sources/CreCore/
    DayKey.swift                   # 年-月-日值类型、加减天数、星期几
    Models.swift                   # Group、Todo、Schedule、Repeat、DayPlan 等
    PlanData.swift                 # 全部数据的根 + 增删改的纯函数
    PlanStore.swift                # JSON 读写、损坏备份
    Agenda.swift                   # "某一天显示什么"的计算（核心）
    Completion.swift               # 勾选、补勾、整行勾、自动勾
    Triage.swift                   # 周五清理
    TimeParser.swift               # 一句话识别时间
  Sources/Cre/
    CreApp.swift                   # 入口、主窗口、菜单栏图标
    AppState.swift                 # ObservableObject，持有 PlanData、当前日期、保存
    Theme.swift                    # 颜色与字号（视觉风格占位）
    Sidebar.swift                  # 首页 / 规划 / 记账 / 总结 / 设置
    DayView/
      DayView.swift                # 首页与小窗口共用的"某一天"视图
      InputBar.swift               # 输入条 + 时间按钮 + 日历按钮
      AgendaRow.swift              # 一行待办（颜色、标签、▶、勾选动画）
      Celebration.swift            # 今日清空的小庆祝
    Planning/
      PlanningView.swift           # 规划板块：模块组列表 + 零散待办
      GroupEditor.swift            # 模块组设置（显示方式、折叠）
      ScheduleEditor.swift         # 四种时间方式的编辑
      DayPlanEditor.swift          # 按天安排（固定/轮换、训练日、动作）
    Widget/
      WidgetPanel.swift            # 小窗口 NSPanel、钉子行为
      HotKey.swift                 # 全局快捷键
    TriageSheet.swift              # 周五清理弹层
    Placeholders.swift             # 记账、总结占位页
  Tests/CreCoreTests/
    DayKeyTests.swift
    ModelsTests.swift
    PlanStoreTests.swift
    AgendaTests.swift
    RepeatPlanTests.swift
    CompletionTests.swift
    TriageTests.swift
    TimeParserTests.swift
```

**前置条件**：仓库尚未配置 git 身份，提交步骤会失败。执行前先由用户设置 `git config user.name` 与 `git config user.email`。

---

### Task 1: 包骨架与 DayKey

**Files:**
- Create: `apps/Cre/Package.swift`, `apps/Cre/Sources/CreCore/DayKey.swift`, `apps/Cre/Sources/Cre/CreApp.swift`（最小可编译入口）
- Test: `apps/Cre/Tests/CreCoreTests/DayKeyTests.swift`

**Interfaces:**
- Produces:
  - `public struct DayKey: Codable, Hashable, Comparable, Sendable { public let year: Int; public let month: Int; public let day: Int }`
  - `public init?(year: Int, month: Int, day: Int)`（非法日期返回 nil）
  - `public static func from(_ date: Date, calendar: Calendar = .current) -> DayKey`
  - `public func adding(days: Int) -> DayKey`
  - `public func days(until other: DayKey) -> Int`（other 在后为正）
  - `public var weekday: Int`（1 = 周日 … 7 = 周六，与 `Calendar` 一致）
  - `public func date(hour: Int = 12, calendar: Calendar = .current) -> Date`
  - Codable 编码为字符串 `"yyyy-MM-dd"`

- [ ] **Step 1: 写 Package.swift**：`platforms: [.macOS(.v14)]`；targets：`.target(name: "CreCore")`、`.executableTarget(name: "Cre", dependencies: ["CreCore"])`、`.testTarget(name: "CreCoreTests", dependencies: ["CreCore"])`。`CreApp.swift` 先放一个只显示 "Cre" 的空 `App`。

- [ ] **Step 2: 写失败的测试**

```swift
@Test func invalidDateIsNil() { #expect(DayKey(year: 2026, month: 2, day: 30) == nil) }
@Test func addingAcrossMonthAndYear() {
    #expect(DayKey(year: 2026, month: 12, day: 30)!.adding(days: 3) == DayKey(year: 2027, month: 1, day: 2)!)
}
@Test func daysUntil() { #expect(DayKey(year: 2026, month: 10, day: 5)!.days(until: DayKey(year: 2026, month: 10, day: 11)!) == 6) }
@Test func weekdayOfKnownMonday() { #expect(DayKey(year: 2026, month: 10, day: 5)!.weekday == 2) }
@Test func codableAsString() throws {
    let data = try JSONEncoder().encode(DayKey(year: 2026, month: 10, day: 8)!)
    #expect(String(data: data, encoding: .utf8) == "\"2026-10-08\"")
}
```

- [ ] **Step 3: 运行确认失败**：`cd apps/Cre && swift test --filter DayKeyTests`，Expected: 编译失败（`DayKey` 未定义）。
- [ ] **Step 4: 实现 `DayKey`**：内部用固定的公历 `Calendar(identifier: .gregorian)` 且时区 UTC 做加减，避免夏令时。
- [ ] **Step 5: 运行确认通过**：同上命令，Expected: 5 passed；`swift build` 成功。
- [ ] **Step 6: Commit**：`git add apps/Cre && git commit -m "feat(cre): package skeleton and DayKey"`

---

### Task 2: 数据模型

**Files:**
- Create: `apps/Cre/Sources/CreCore/Models.swift`
- Test: `apps/Cre/Tests/CreCoreTests/ModelsTests.swift`

**Interfaces:**
- Consumes: `DayKey`
- Produces（全部 `public`，`Codable, Equatable, Sendable`）：

```swift
enum TodayDisplay: String { case hidden, oneLine, expanded }

struct Group: Identifiable { var id: UUID; var name: String; var collapsed: Bool
    var todayDisplay: TodayDisplay; var sortOrder: Double; var createdAt: Date }

enum Schedule { case none
    case day(DayKey)                         // 指定日
    case deadline(DayKey)                    // DDL
    case span(start: DayKey, end: DayKey)    // 阶段
    case repeating(Repeat) }                 // 每日重复

struct Repeat { var weekdays: Set<Int>       // 空 = 每天；否则 1…7
    var start: DayKey
    var plan: DayPlan?
    var completions: [DayKey: Date]          // 某天整行完成的时间
    var itemCompletions: [DayKey: Set<UUID>] }  // 某天完成了哪些动作

enum PlanMode: String { case fixedWeekday, rotate }

struct DayPlan { var mode: PlanMode; var days: [PlanDay] }

struct PlanDay: Identifiable { var id: UUID; var name: String
    var weekday: Int?                        // 仅 fixedWeekday 使用
    var items: [PlanItem] }

struct PlanItem: Identifiable { var id: UUID; var text: String }

struct Todo: Identifiable { var id: UUID; var text: String; var groupID: UUID?
    var tags: [String]; var schedule: Schedule; var isOngoing: Bool
    var createdAt: Date; var completedAt: Date?
    var completedDay: DayKey?                // 统计以此为准（补勾时为过去那天）
    var isDone: Bool { completedDay != nil } }  // 不适用于 .repeating
```

- [ ] **Step 1: 写失败的测试**：`scheduleRoundTrips`——五种 `Schedule` 各编码再解码后相等；`repeatWithFixedPlanRoundTrips`——带两个 `PlanDay`（周一"练胸"含 3 个动作）的 `Repeat` 往返相等。
- [ ] **Step 2: 运行确认失败**：`swift test --filter ModelsTests`，Expected: 编译失败。
- [ ] **Step 3: 实现模型**：`Schedule` 用带 `kind` 字段的手写 Codable（便于以后迁移）；字典键 `DayKey` 编码为字符串键。
- [ ] **Step 4: 运行确认通过**：Expected: 2 passed。
- [ ] **Step 5: Commit**：`git commit -m "feat(cre): domain models"`

---

### Task 3: PlanData 与持久化

**Files:**
- Create: `apps/Cre/Sources/CreCore/PlanData.swift`, `apps/Cre/Sources/CreCore/PlanStore.swift`
- Test: `apps/Cre/Tests/CreCoreTests/PlanStoreTests.swift`

**Interfaces:**
- Consumes: Task 2 的模型
- Produces:
  - `public struct PlanData: Codable, Equatable { public var version: Int = 1; public var groups: [Group]; public var todos: [Todo] }`
  - `mutating func addTodo(_ text: String, schedule: Schedule, groupID: UUID?, tags: [String], now: Date) -> UUID?`（text 去首尾空白；为空则不添加并返回 nil）
  - `mutating func deleteGroup(_ id: UUID)`（连同组内待办一起删）
  - `mutating func setOngoing(_ todoID: UUID, _ on: Bool)`
  - `func todos(in groupID: UUID?) -> [Todo]`
  - `public final class PlanStore { public init(fileURL: URL); public func load() -> PlanData; public func save(_ data: PlanData) throws }`
  - `public static var defaultURL: URL`（`~/Library/Application Support/Cre/data.json`）

- [ ] **Step 1: 写失败的测试**
  - `emptyTextIsRejected`：`addTodo("   ", …)` 返回 nil，`todos` 为空。
  - `deletingGroupRemovesItsTodos`：建组、组内 2 条、组外 1 条；删组后只剩组外 1 条。
  - `saveThenLoad`：临时目录里存一份再读，相等。
  - `corruptFileIsBackedUpNotOverwritten`：写入 `"not json"`，`load()` 返回空 `PlanData`，目录里出现 `data.broken-*.json` 且内容仍为 `"not json"`。
  - `missingFileGivesEmpty`。
- [ ] **Step 2: 运行确认失败**：`swift test --filter PlanStoreTests`。
- [ ] **Step 3: 实现**：编码用 `.iso8601` 日期、`.prettyPrinted, .sortedKeys`；写入用 `.atomic`。
- [ ] **Step 4: 运行确认通过**：Expected: 5 passed。
- [ ] **Step 5: Commit**：`git commit -m "feat(cre): PlanData mutations and JSON store"`

---

### Task 4: 某一天显示什么（Agenda）

**Files:**
- Create: `apps/Cre/Sources/CreCore/Agenda.swift`
- Test: `apps/Cre/Tests/CreCoreTests/AgendaTests.swift`

**Interfaces:**
- Consumes: `PlanData`, `DayKey`
- Produces:

```swift
public enum EntryKind: Sendable { case day, deadline, span, repeating }

public struct Progress: Equatable, Sendable { public var done: Int; public var total: Int }

public struct AgendaEntry: Identifiable, Equatable, Sendable {
    public var id: UUID            // todo.id，或 group 一行时为 group.id
    public var kind: EntryKind
    public var text: String
    public var groupName: String?  // 阶段与组内待办的标签
    public var deadline: DayKey?   // 供 "DDL M月d日" 标签
    public var overdueDays: Int    // 0 = 未拖延
    public var detail: String?     // ▶ 后的文字（Task 6 填）
    public var progress: Progress?
    public var isCheckable: Bool   // 阶段 = false
    public var isDone: Bool
    public var isGroupRow: Bool    // oneLine 模块组的一整行
    public var movedLater: Bool }  // 过去视图：当天没做、后来被顺延或改期

public struct Agenda: Equatable, Sendable {
    public var entries: [AgendaEntry]          // 主列表
    public var foldedDeadlines: [AgendaEntry]  // "DDL 待办（N）"里的
    public var progress: Progress }  // 顶部"今天 3/7"，只算可勾选的

public func agenda(for day: DayKey, today: DayKey, data: PlanData) -> Agenda
public func ddlLabel(_ day: DayKey) -> String   // "DDL 10月8日"
```

规则（`day` 为要看的那天，`today` 为真实今天）：
- `.none` 不出现。
- `.day(d)`：`d == day` 出现；若 `day == today` 且 `d < today` 且未完成，也出现，`overdueDays = d.days(until: today)`；已完成的只在 `completedDay == day` 那天出现（显示为已勾）。过去视图里 `d == day`、未在当天完成、且现在仍未完成或完成于之后的，`movedLater = true`。
- `.deadline(d)`：`createdDay ≤ day ≤ d` 出现（`createdDay = DayKey.from(createdAt)`）；`day == today && d < today` 且未完成也出现，`overdueDays` 同上；剩余 `day.days(until: d) ≤ 3`（含已过期）进 `entries`，否则进 `foldedDeadlines`。
- `.span(s, e)`：`s ≤ day ≤ e` 出现，`isCheckable = false`。
- `.repeating(r)`：`day ≥ r.start` 且（`weekdays` 为空或包含 `day.weekday`）出现；不顺延。
- 组的显示方式：`hidden` 组内待办都不出现；`oneLine` 组内当天的可勾选项合成一行（`isGroupRow = true`，`progress` 为组内完成数/总数，文字为组名）；`expanded` 逐条出现。`hidden` 对组内所有类型都生效，包括 DDL。
- 排序：未完成在前；未完成内按 kind 顺序 deadline(≤3 天) → day → repeating → span，同类按 `createdAt`；已完成按 `completedAt`。

- [ ] **Step 1: 写失败的测试**（每条一个 `@Test`，用固定 `today = 2026-10-05`）
  - `dayTodoOnlyOnItsDay`：10-08 的待办在 10-07 不出现、10-08 出现。
  - `overdueDayTodoRollsToToday`：10-02 未完成 → 今天出现且 `overdueDays == 3`。
  - `overdueNotShownOnFutureView`：同一条在 10-07 的视图里不出现。
  - `pastViewMarksMovedLater`：看 10-02 时它出现且 `movedLater == true`。
  - `deadlineShowsEveryDayUntilDue`：10-01 创建、DDL 10-20，10-05 出现于 `foldedDeadlines`，10-18 出现于 `entries`。
  - `deadlineFoldThresholdIsThreeDays`：DDL 10-08 在 10-05 进 `entries`，DDL 10-09 进 `foldedDeadlines`。
  - `ddlLabelFormat`：`ddlLabel(2026-10-08) == "DDL 10月8日"`。
  - `spanIsNotCheckable`：10-05…10-11 的阶段在 10-07 出现且 `isCheckable == false`，不计入 `progress.total`。
  - `repeatOnSelectedWeekdaysOnly`：周一三五，10-05（周一）出现、10-06 不出现。
  - `repeatDoesNotRollOver`：周一未完成，10-06 不出现。
  - `hiddenGroupShowsNothing`、`oneLineGroupCollapsesToOneRow`（2 条中完成 1 条 → `progress == Progress(done: 1, total: 2)`）。
  - `progressCountsCheckableOnly`。
- [ ] **Step 2: 运行确认失败**：`swift test --filter AgendaTests`。
- [ ] **Step 3: 实现 `agenda(for:today:data:)`**，规则如上。
- [ ] **Step 4: 运行确认通过**：Expected: 13 passed。
- [ ] **Step 5: Commit**：`git commit -m "feat(cre): agenda for a day"`

---

### Task 5: 勾选、补勾与整行勾

**Files:**
- Create: `apps/Cre/Sources/CreCore/Completion.swift`
- Test: `apps/Cre/Tests/CreCoreTests/CompletionTests.swift`

**Interfaces:**
- Consumes: `PlanData`, `Agenda`
- Produces（`PlanData` 的 `mutating` 扩展）：
  - `toggle(todoID: UUID, on day: DayKey, now: Date)`：非重复项设置/清除 `completedDay = day`、`completedAt = now`；阶段项只允许从规划调用（Agenda 已标 `isCheckable = false`，此函数不区分）。
  - `toggleRepeat(todoID: UUID, on day: DayKey, now: Date)`：整行勾/取消；勾上时同时把当天所有动作标为完成。
  - `toggleRepeatItem(todoID: UUID, itemID: UUID, on day: DayKey, now: Date)`：勾单个动作；当天动作全部完成时自动写入 `completions[day]`；取消任一动作时移除整行完成。
  - `toggleGroupRow(groupID: UUID, on day: DayKey, today: DayKey, now: Date)`：把该组在当天 agenda 里的所有可勾选项设为全部完成（若已全部完成则全部取消）。

- [ ] **Step 1: 写失败的测试**
  - `backfillCountsForThatDay`：今天 10-05 在 10-03 的视图勾一条 10-03 的待办 → `completedDay == 10-03`；10-05 的 agenda 不再出现它。
  - `untoggleClearsCompletion`。
  - `allItemsDoneAutoCompletesRepeat`：练胸 3 个动作逐个勾完 → `completions[10-05] != nil`。
  - `oneTapCompletesRepeatAndItems`。
  - `uncheckingItemReopensRepeat`。
  - `groupRowTogglesAll`。
- [ ] **Step 2–4**：`swift test --filter CompletionTests` 先失败、实现、再通过（Expected: 6 passed）。
- [ ] **Step 5: Commit**：`git commit -m "feat(cre): completion, backfill, whole-row check"`

---

### Task 6: 按天安排与 ▶ 文字

**Files:**
- Modify: `apps/Cre/Sources/CreCore/Agenda.swift`（填 `detail` 与重复项的 `progress`）
- Test: `apps/Cre/Tests/CreCoreTests/RepeatPlanTests.swift`

**Interfaces:**
- Produces:
  - `public func planDay(for r: Repeat, on day: DayKey) -> PlanDay?`
  - `public func detailText(for todo: Todo, on day: DayKey, data: PlanData) -> String?`

规则：
- `fixedWeekday`：返回 `weekday == day.weekday` 的那个 `PlanDay`，没有则 nil。
- `rotate`：`n = r.plan.days.count`；`k` = 在 `r.start ..< day` 之间、属于安排日且 `completions` 有记录的天数；返回 `days[k % n]`；`n == 0` 返回 nil。
- `detailText`：有 `plan` → 当天 `PlanDay.name`；没有 plan → 同组 `isOngoing && !isDone` 的待办文字按 `createdAt` 用"、"连接；都没有 → nil。
- 重复项的 `progress` = 当天 `PlanDay.items` 中完成数 / 总数；没有 items 时为 nil。

- [ ] **Step 1: 写失败的测试**
  - `fixedShowsMondayPlan`：周一"练胸" → 10-05 的 detail 为"练胸"，`progress == Progress(done: 0, total: 3)`。
  - `fixedSkipsMissedDay`：10-05 未练，10-06（周二）显示"练背"。
  - `rotateShiftsAfterMissedDay`：轮换 [练胸, 练背, 练腿]，10-05 未练 → 10-06 显示"练胸"；10-06 完成 → 10-07 显示"练背"。
  - `rotationSurvivesPlanDayRemoval`：k = 4、n 从 3 改为 2 后返回 `days[0]`，不崩溃。
  - `ongoingShownWhenNoPlan`："读书 1 小时"同组《人类简史》标进行中 → detail = "人类简史"。
  - `multipleOngoingJoined`：两条 → "人类简史、三体"。
  - `ongoingClearedWhenDone`：《人类简史》勾完后 detail 为 nil。
- [ ] **Step 2–4**：`swift test --filter RepeatPlanTests` 先失败、实现、再通过（Expected: 7 passed）。
- [ ] **Step 5: Commit**：`git commit -m "feat(cre): day plans, rotation and ongoing detail"`

---

### Task 7: 周五清理

**Files:**
- Create: `apps/Cre/Sources/CreCore/Triage.swift`
- Test: `apps/Cre/Tests/CreCoreTests/TriageTests.swift`

**Interfaces:**
- Produces:
  - `public let triageHour = 19`
  - `public func shouldOfferTriage(now: Date, lastTriagedWeek: DayKey?, calendar: Calendar = .current) -> Bool`：周五且时间 ≥ 19:00，且本周（以当周周五的 `DayKey` 标识）还没处理过。
  - `public func triageCandidates(today: DayKey, data: PlanData) -> [Todo]`：未完成的 `.day(d)` 且 `d < today`，以及未完成的 `.deadline(d)` 且 `d < today`。
  - `PlanData`：`mutating func doToday(_ id: UUID, today: DayKey)`（改为 `.day(today)`，DDL 也改为指定日今天）、`mutating func reschedule(_ id: UUID, to: DayKey)`（保持原类型，只改日期）。
  - `PlanData` 新增字段 `public var lastTriagedWeek: DayKey?`

- [ ] **Step 1: 写失败的测试**：`offeredFridayEvening`（10-09 19:05 → true）、`notBeforeSeven`（18:59 → false）、`notTwiceSameWeek`、`notOnSaturday`、`candidatesAreOverdueOnly`、`doTodayMovesToToday`、`rescheduleKeepsKind`。
- [ ] **Step 2–4**：`swift test --filter TriageTests`（Expected: 7 passed）。
- [ ] **Step 5: Commit**：`git commit -m "feat(cre): Friday triage"`

---

### Task 8: 一句话识别时间

**Files:**
- Create: `apps/Cre/Sources/CreCore/TimeParser.swift`
- Test: `apps/Cre/Tests/CreCoreTests/TimeParserTests.swift`

**Interfaces:**
- Produces:
  - `public struct ParsedInput: Equatable { public var text: String; public var schedule: Schedule }`
  - `public func parseInput(_ raw: String, today: DayKey) -> ParsedInput`

识别规则（从原文中删掉识别到的时间片段，剩余部分去空白作为 `text`；识别不到则 `.none`）：
- 日期写法：`M月d日`、`M月d号`、`M.d`、`M/d`、`今天`、`明天`、`后天`、`下周X`。月日不合法则不算日期；`M.d` 紧跟 `页|元|块|斤|个|次|公里|km|kg|%` 不算日期。
- 不带年份时：若早于 `today`，取下一年。
- `ddl`（不分大小写）或 `截止` 紧挨日期（前后均可）→ `.deadline`。
- 两个日期用 `-`、`–`、`—`、`~`、`至`、`到` 连接 → `.span`（结束早于开始时结束取下一年）。
- `每天` → `.repeating(weekdays: [])`；`每周` 后跟 `一…日` 的若干字，或 `周X到周Y`/`周X至Y`、`每周X到X` → 对应 weekdays；`start = today`。
- 单个日期 → `.day`。

- [ ] **Step 1: 写失败的测试**（`today = 2026-10-05`）
  - `dayWithChineseDate`："10月8日 买香蕉" → ("买香蕉", .day(10-08))
  - `deadlineKeyword`："买香蕉 ddl 10月8日" → ("买香蕉", .deadline(10-08))；"买香蕉 10.8 截止" 同样
  - `spanWithDash`："学习 10.5–10.11" → ("学习", .span(10-05, 10-11))
  - `everyDay`："健身 每天" → ("健身", .repeating 空 weekdays)
  - `weekdaysList`："健身 每周一三五" → weekdays [2, 4, 6]
  - `weekdayRange`："健身 周一到周六" → [2, 3, 4, 5, 6, 7]
  - `relativeDays`："明天 交表" → .day(10-06)
  - `noDate`："买香蕉" → ("买香蕉", .none)
  - `numbersThatAreNotDates`："买 2 斤香蕉"、"读 10.5 页"、"跑 3.5 公里" 都是 `.none` 且原文不变
  - `pastMonthDayMeansNextYear`："1月3日 交房租"（today 2026-12-20）→ 2027-01-03
  - `spanAcrossYearEnd`："放假 12.28–1.3"（today 2026-12-01）→ 2026-12-28…2027-01-03
- [ ] **Step 2–4**：`swift test --filter TimeParserTests`（Expected: 11 passed）。
- [ ] **Step 5: Commit**：`git commit -m "feat(cre): one-line time parsing"`

---

### Task 9: App 骨架、AppState 与侧边栏

**Files:**
- Create: `apps/Cre/Sources/Cre/AppState.swift`, `Theme.swift`, `Sidebar.swift`, `Placeholders.swift`；Modify: `CreApp.swift`
- Test: `apps/Cre/Tests/CreCoreTests/AgendaTests.swift`（加跨午夜测试，见下）

**Interfaces:**
- Consumes: `PlanStore`, `PlanData`, `agenda(for:today:data:)`
- Produces:
  - `@MainActor final class AppState: ObservableObject { @Published var data: PlanData; @Published private(set) var today: DayKey; @Published var viewingDay: DayKey; func agendaForViewingDay() -> Agenda; func refreshToday(now: Date) }`——`data` 的 `didSet` 里保存；监听 `NSCalendarDayChanged` 和唤醒通知调用 `refreshToday(now: Date())`；`refreshToday` 若 `viewingDay` 原本等于旧的 today，则一起前移。
  - `enum Section: String, CaseIterable { case home, planning, ledger, summary }`（显示名：首页、规划、记账、总结）
  - `enum Theme`：`static func color(for kind: EntryKind) -> Color`（day 蓝、deadline 橙、span 紫、repeating 绿，均为占位）、`static let overdue: Color`。

- [ ] **Step 1: 写失败的测试** `todayAdvancesAtMidnight`：把 `refreshToday` 的日期逻辑抽为 `CreCore` 里的纯函数 `public func advanceViewing(viewing: DayKey, oldToday: DayKey, newToday: DayKey) -> DayKey`；断言 viewing == oldToday 时返回 newToday，否则原样返回。
- [ ] **Step 2–4**：`swift test --filter todayAdvancesAtMidnight` 先失败、实现、再通过。
- [ ] **Step 5: 实现界面骨架**：`NavigationSplitView`，左侧 `Sidebar`（四项 + 底部"设置"占位），记账、总结显示"下一阶段做"的占位页。`swift build` 通过；`swift run Cre` 能打开主窗口并切换四个板块。
- [ ] **Step 6: Commit**：`git commit -m "feat(cre): app shell, sidebar, app state"`

---

### Task 10: 某一天视图（首页与小窗口共用）

**Files:**
- Create: `apps/Cre/Sources/Cre/DayView/DayView.swift`, `InputBar.swift`, `AgendaRow.swift`, `Celebration.swift`

**Interfaces:**
- Consumes: `AppState`, `Agenda`, `parseInput`, `ddlLabel`, `Theme`, Task 5 的勾选函数
- Produces: `struct DayView: View { init(state: AppState, compact: Bool) }`——`compact = true` 用于小窗口（不显示快捷按钮）。

界面从上到下：
1. `InputBar`：输入框（占位"记录你的想法或安排…"）；回车 → `parseInput` → `addTodo`；输入框保持焦点、清空，可连续记。如果正在看未来某天且识别结果为 `.none`，按 `.day(viewingDay)` 保存。输入时实时显示识别结果：时间按钮 `[某天] [截止] [阶段] [重复]` 中对应的那个高亮，点按钮弹出对应的日期 / 范围 / 星期选择覆盖识别结果。右侧日历按钮弹出日期选择，选中即设 `viewingDay`；非今天时显示"回到今天"。
2. 标题行："今天 · 10月5日 周一"或所看日期；右侧进度"今天 3/7"（仅今天视图）。
3. 首页（非 compact）：快捷按钮"创建一个任务"（聚焦输入条）；"总结一下今天"本计划不放，计划 3 加。
4. 列表：`entries`，然后折叠行"DDL 待办（N）▸"展开 `foldedDeadlines`。
5. `AgendaRow`：左侧颜色条取 `Theme.color(for:)`；勾选框（`isCheckable` 为 false 时不显示）；文字；`detail` 非空时显示" ▶ \(detail)"；`progress` 显示"2/3"；标签：deadline 显示 `ddlLabel`，组内项显示组名，repeating 显示循环图标；`overdueDays > 0` 显示"拖了 N 天"；`movedLater` 显示"已顺延"并置灰。重复项、组一行可点开展开当天动作 / 组内条目并逐项勾。
6. 勾选：弹性缩放 + 划线动画（`prefers-reduced-motion` 等价的 `NSWorkspace.accessibilityDisplayShouldReduceMotion` 为真时只淡出），播放系统音效 `NSSound(named: "Pop")`；勾完后今天 `progress.done == total && total > 0` 时显示 `Celebration`（"今天清空了"，2 秒后自动消失）。

- [ ] **Step 1: 实现上述视图**。
- [ ] **Step 2: 手动验证**（`swift run Cre`，用一份测试数据）：
  - 输入"买香蕉 ddl 10月20日"回车 → 列表出现在 DDL 折叠组里，标签为"DDL 10月20日"。
  - 输入"学习 10.5–10.11" → 无勾选框，紫色。
  - 勾选一条 → 有动画和声音；全部勾完出现"今天清空了"。
  - 日历跳到昨天勾一条 → 回到今天后该条不再出现。
  - 日历跳到下周一 → 看到"健身 ▶ 练胸"。
- [ ] **Step 3: Commit**：`git commit -m "feat(cre): day view shared by home and widget"`

---

### Task 11: 规划板块

**Files:**
- Create: `apps/Cre/Sources/Cre/Planning/PlanningView.swift`, `GroupEditor.swift`, `ScheduleEditor.swift`, `DayPlanEditor.swift`

**Interfaces:**
- Consumes: `AppState`, `PlanData` 的增删改、`setOngoing`、`deleteGroup`、`parseInput`
- Produces: `struct PlanningView: View`

内容：
- 顶部输入条（同 `InputBar`，新建到"零散待办"）。
- 模块组列表：可折叠；组标题右侧"…"菜单：重命名、今日显示方式（不显示 / 只显示一行 / 展开显示）、删除（二次确认文案："删除「\(name)」及其中 N 条待办？"）。
- 组内输入条：新建的待办自动属于该组。
- 每条待办：勾选（阶段也在这里勾）、文字可改、时间方式按钮打开 `ScheduleEditor`（无 / 某天 / 截止 / 阶段 / 重复）、"进行中"开关（▶ 图标）、标签编辑、删除。
- 重复项可打开 `DayPlanEditor`：选"不按天安排 / 按星期固定 / 按顺序轮换"；增删训练日（名称、固定模式下选星期几）、每个训练日下增删动作。
- 零散待办区：同样的行，带标签。

- [ ] **Step 1: 实现上述视图**。
- [ ] **Step 2: 手动验证**：
  - 建"读书"组，加"读书 1 小时 每天"和三本书，把《人类简史》设为进行中 → 首页显示"读书 1 小时 ▶ 人类简史"。
  - 建"健身"组，"健身 每周一到六"按星期固定，周一"练胸"三个动作 → 下周一视图显示"健身 ▶ 练胸 0/3"。
  - 把"健身"组设为"只显示一行" → 首页只剩一行带进度。
  - 删除带待办的组 → 出现确认；确认后首页不再有其中任何待办。
- [ ] **Step 3: Commit**：`git commit -m "feat(cre): planning section"`

---

### Task 12: 小窗口、钉子与全局快捷键

**Files:**
- Create: `apps/Cre/Sources/Cre/Widget/WidgetPanel.swift`, `apps/Cre/Sources/Cre/Widget/HotKey.swift`；Modify: `CreApp.swift`

**Interfaces:**
- Consumes: `DayView(state:compact: true)`
- Produces:
  - `final class WidgetController { func toggle(); var isPinned: Bool }`
  - `final class HotKey { init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) }`，默认 ⌃⌥Space

行为：
- 菜单栏图标（`NSStatusItem`，SF Symbol `checklist`）点击 → `toggle()`；全局快捷键同样 → `toggle()`。
- 未钉住：`NSPanel`（`.nonactivatingPanel`、圆角、约 340×480），出现在菜单栏图标下方，失去焦点即收起。
- 钉子按钮（右上角 `pin` / `pin.fill`）：钉住后窗口层级设为 `CGWindowLevelForKey(.desktopIconWindow) + 1`，`collectionBehavior = [.canJoinAllSpaces, .stationary]`，失焦不收起，可拖动，位置记在 `UserDefaults`；再次点钉子取消钉住并恢复为弹出式。
- 钉住状态在 App 重启后保持。

- [ ] **Step 1: 实现**。
- [ ] **Step 2: 手动验证**：
  - 在任意 App 里按 ⌃⌥Space 出现小窗口，再按收起。
  - 钉住后打开 Safari 全屏覆盖，小窗口被挡住；按 F11 / 触控板展开显示桌面，小窗口可见。
  - 退出重开 App，小窗口仍钉在原位置。
- [ ] **Step 3: Commit**：`git commit -m "feat(cre): widget panel, pin, global hotkey"`

---

### Task 13: 周五清理弹层与打包

**Files:**
- Create: `apps/Cre/Sources/Cre/TriageSheet.swift`, `apps/Cre/build.sh`, `apps/Cre/Info.plist`

**Interfaces:**
- Consumes: `shouldOfferTriage`, `triageCandidates`, `doToday`, `reschedule`

- [ ] **Step 1: 实现 `TriageSheet`**：每分钟及唤醒时检查 `shouldOfferTriage`；为真且有候选项时，在主窗口与小窗口顶部出现提示条"有 N 件拖延的事，周末处理一下？"，点开列出每条及两个按钮"今天做""改个日期"（后者弹日期选择）；全部处理完或点"稍后"后写入 `lastTriagedWeek`。
- [ ] **Step 2: 写 `build.sh`**：仿照 `tools/CreTodo/build.sh`，产物 `build/Cre.app`，安装到 `~/Applications/Cre.app`；`Info.plist` 的 `CFBundleIdentifier` 为 `com.lty.cre`、`CFBundleName` 为 `Cre`。
- [ ] **Step 3: 全量验证**：`cd apps/Cre && swift test`，Expected: 全部通过；`./build.sh` 输出 `Installed: ~/Applications/Cre.app`；双击打开，按 Task 10–12 的手动验证清单走一遍。
- [ ] **Step 4: Commit**：`git commit -m "feat(cre): Friday triage sheet and packaging"`

---

## 之后的计划

- **计划 2：记账**——一句话记账、完整表单、流水、本月收入/支出/结余、预设分类、统计页、日历只看过去。
- **计划 3：总结**——预置每日总结、首页"总结一下今天"、随笔/感想、历史回看。

两份计划在本计划完成、你试用过核心功能后再写，届时视觉风格也应已确定。

---

## 修订（2026-10-04）：界面草图确认后的变更

产品文档第 2、3 节已按界面草图更新（视觉风格、模块组四种类型、优先级、排序、点击修改、快捷按钮）。Task 1–9 已完成，保持不变。**原 Task 10–12 作废，由下面的 Task 10a、10b、10、11、12 取代**；Task 13 不变。

### Task 10a: 优先级与排序（CreCore）

**Files:** Modify `Models.swift`、`Agenda.swift`、`TimeParser.swift`；Test `PriorityTests.swift`

**Interfaces:**
- `public enum Priority: Int, Codable, Comparable, Sendable { case p0 = 0, p1 = 1, p2 = 2 }`；`Todo.priority: Priority?`（解码缺省 nil）
- `public enum SortMode: String, Codable, Sendable { case priority, category }`
- `agenda(for:today:data:sort: SortMode = .priority)`；`AgendaEntry.priority: Priority?`
- `ParsedInput.priority: Priority?`；识别独立的 `p0|p1|p2`（不分大小写，前后为空白或行首行尾）
- 排序：未完成在前；`.priority` 按 P0→P1→P2→nil，同级再按原 kind 顺序与 createdAt；`.category` 按 kind 顺序（deadline→day→repeating→span），同类再按优先级

- [ ] 测试：`priorityParsed`（"p0 交报告 ddl 10月12日" → text "交报告"、.deadline、.p0）、`p0InsideWordIgnored`（"top0" 不识别）、`sortByPriorityPutsNoneLast`、`sortByCategoryGroupsKinds`、`oldFileWithoutPriorityLoads`
- [ ] 先失败、实现、通过；提交 `feat(cre): priority and sort modes`

### Task 10b: 模块组类型（CreCore）

**Files:** Modify `Models.swift`、`PlanData.swift`、`Completion.swift`、`Agenda.swift`；Test `GroupKindTests.swift`

**Interfaces:**
- `public enum GroupKind: Codable, Equatable, Sendable { case cycle, list(minutes: Int), phase, ungrouped }`；`TodoGroup.kind`（解码缺省 `.ungrouped`）
- 周循环与清单各自由组内**一条托管的重复待办**承载排期（`Todo.isGroupAnchor = true`，文字：周循环为组名，清单为"组名 + 时长"，如"读书 1 小时"）。界面不把它当普通待办列出，而是渲染成模块组的排期。
- `PlanData.addGroup(_ name:, kind:, schedule: Repeat?, now:) -> UUID`：周循环、清单时创建托管待办。
- `PlanData.setGroupKind(_ id:, _ kind:)`：改类型时托管待办变为普通重复待办（不删内容）。
- `DayPlan` 轮换语义改为"循环周期 N"：`DayPlan.mode == .rotate` 时 `days.count == N`（1…7），`Repeat.weekdays` 为空。
- `planDay(for:on:)` 轮换规则：`k` = start 之后、day 之前的完成次数；若最近一次完成使 `k % N == 0` 且 `k > 0`，则其后 `7 − N` 天为停顿日，返回 nil 且该天不出现；否则返回 `days[k % N]`。N = 7 无停顿日。
- `Agenda`：托管待办在停顿日不出现。

- [ ] 测试：`rotateCycleSixStopsOneDay`（周期 6，连续完成 6 天后第 7 天不出现，第 8 天显示第 1 天）、`rotateMissedDayDoesNotAdvance`、`rotateCycleSevenNeverStops`、`listAnchorShowsDurationAndOngoing`（"读书 1 小时 ▶ 人类简史"）、`listWeeklyOnlyOnChosenDays`、`changingKindKeepsTodos`、`oldGroupsDecodeAsUngrouped`
- [ ] 删除或改写 Task 6 中与旧轮换语义冲突的 `rotateShiftsAfterMissedDay`、`rotationSurvivesPlanDayRemoval`（按新语义重写，仍覆盖"删减天数不崩溃"）
- [ ] 先失败、实现、通过；提交 `feat(cre): group kinds and cycle period`

### Task 10: 某一天视图（取代原 Task 10）

**Files:** `DayView/DayView.swift`、`InputBar.swift`、`AgendaRow.swift`、`Celebration.swift`、`EditCard.swift`、`QuickActions.swift`；删除 `Planning/ScheduleEditor.swift` 中的 `TimeButtons`

- 输入条：无时间按钮；打字时右侧浅灰显示识别结果（"→ P0 · 截止 10月12日"）；右端"日历加号"弹出 `EditCard`（类型分段：不设/某天/截止/阶段/重复 + 日期 + 优先级）。
- 标题行：日期、"今天 3/7"、排序切换（按优先级/按类别，记在 UserDefaults）、日历跳转、"回到今天"。
- 首页（非 compact）快捷按钮：总结一下今天（`note.text` 图标，计划 3 前置灰）、看看明天（`calendar.badge.clock`）、整理拖延（N）（`tray.full`，仅 N>0 显示）。
- 列表：未完成 / 已完成两组，带条数，可收起，状态记在 UserDefaults；DDL 折叠组在未完成内。
- `AgendaRow`：整行高 5pt 色条 + 同色勾选圈（完成填满）；阶段显示进度饼 + "第 N/M 天"；完成项文字与色条降低不透明度、不划线；优先级标签 P0 红 / P1 橙 / P2 灰；点文字原地编辑；点时间或优先级标签弹 `EditCard`。
- 文案遵守"精炼、不用大白话"。
- 手动验证同原 Task 10，另加：输入"p0 交报告 ddl 10月12日"显示提示并正确保存；切换排序；收起已完成后重启仍收起。

### Task 11: 规划板块（取代原 Task 11）

- 新建模块组：名称 → 类型（周循环/清单/阶段/未分组）→ 周循环：排期方式（按星期固定 → 选周几；按顺序轮换 → 循环周期 1–7）；清单：排期方式（每天 → 时长；每周 → 选周几 + 时长）。
- 卡片标题旁徽标："周循环 · 一至六"/"周循环 · 周期 6"/"清单 · 每天 1 小时"/"清单 · 一三五 2 小时"/"阶段 · 1/3"/无。
- 周循环：训练日直接列在组下（"周一 · 练胸"/"第 1 天 · 练胸"），下挂动作，勾的是本轮该天，今天那项带"今天"。
- 清单：条目可随时"设为进行中"；完成显示日期。
- 阶段：新阶段默认接在上一个之后。
- ⋯ 菜单：重命名、类型、今日显示方式、删除（确认）。
- 规划页下方保留"零散待办"。

### Task 12: 小窗口（同原 Task 12），小窗口不显示快捷按钮。


### 修订二（2026-10-04）：循环改为"不分周"

Task 10b 中的轮换语义改为：
- 类型名"周循环"改回"循环"；`GroupKind.cycle`。
- 轮换参数：`DayPlan.mode == .rotate` 时 `days.count` = 周期 N（≥1，不再限制 ≤7），新增 `DayPlan.gap: Int`（每轮做完后停几天，≥0，解码缺省 0）。
- `planDay(for:on:)` 轮换规则：`k` = start 之后、day 之前的完成次数；若 `k > 0` 且 `k % N == 0`，设 `last` 为第 k 次完成的那天，则 `last` 之后的 `gap` 天为停顿日（返回 nil，不出现）；否则返回 `days[k % N]`。与星期无关，跨周照样接着。
- 徽标："循环 · 一至六"/"循环 · 周期 6 · 间隔 1"。
- Task 10b 测试改为：`rotateGapStopsAfterRound`（周期 6、间隔 1：做满 6 次后下一天不出现，再下一天显示第 1 天）、`rotateMissedDayCarriesAcrossWeeks`（周二周三没做，下周一仍接着第 6 天）、`rotateGapZeroNeverStops`、`rotateLongPeriodAllowed`（周期 10）。
