# 朝夕 iPhone 版 · 计划 2：其余全部（四个板块、同步、小组件与快捷入口、整体自查） Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一次做完方案剩下的全部：规划、日程（竖 / 横）、记账（四种截图入口 + 分享）、总结；与 Mac 的 Wi-Fi 同步；主屏幕 / 锁屏小组件、快速记一条、每晚提醒；最后整体自查出改进清单，装到手机。

**Architecture:** 手机界面全部写在 `Sources/Mobile/<板块>/`，状态仍由 `MobileState` 统一持有（新增记账、日程两份数据，同样打时间戳、可摇一摇撤销）。Mac 界面里夹带的纯逻辑（待办卡片清单、日程是否已过、截图转草稿）先挪进 `CreCore` 或 `Sources/Shared` 并补测试，两端共用；Mac 界面行为不变。手机数据放在 App Group `group.com.lty.cre.mobile` 容器（已验证免费签名可用），小组件与分享扩展共读写。同步：Mac 上的朝夕开局域网服务（Bonjour `_tide._tcp`），手机发现后整份发送三类数据，双方用 `CreCore` 同一套逐条合并规则合并。每个板块沿用首页已定的视觉：白底、左上大标题（`PageTitleRow`）、底部输入条、取消 / 保存在顶部两侧、日历用 `phoneCalendarSheet()`。

**Tech Stack:** Swift 6.4、SwiftUI（iOS 17）、Swift Charts、PhotosUI、Photos、Vision、UIKit 相机、Network.framework（`NWListener` / `NWBrowser`）、WidgetKit + App Intents（交互小组件、锁屏、控制中心）、UserNotifications、Swift Testing、XCUITest。

**Spec:** `docs/开发过程/specs/2026-10-09-iphone-design.md`（第二至四节；第五节第 3–6 步）。

**范围：** 方案开发顺序第 3–6 步全部 + `docs/开发过程/progress/iphone.md` 中标「计划 2」「计划 4」的问题。用户要求一次做完（2026-10-10）。

## Global Constraints

- iOS 17 起；Mac 版界面、行为、数据不变。
- 手机数据：`Documents/data.json`、`Documents/ledger.json`、`Documents/schedule.json`，格式与 Mac 完全相同；`CRE_DEMO=1` 时用演示数据与临时文件。
- 改动一律经 `stamped(since:now:)` 打时间戳，并进摇一摇撤销。
- 界面文字精炼，沿用 Mac 已有文案（「＋ 加一项」「只改这一次 / 改全部」「拖到时间表，或点卡片再点时段」「记录这张？」等）；不加解释性大白话。
- 每个记录类型的所有入口显示该类型的全部记录（如规划里写的感想，总结里一定看得到）。
- DDL 标签格式「DDL 10月8日」不变；日历一律 `MonthCalendar`。
- 日程颜色：块沿用来源待办的类别色，自建为蓝；未发生深色、已过浅色。
- 开发验证只用模拟器 / `CRE_DEMO=1`；同步联调用两份临时数据目录（`CRE_DEMO=1`），不碰用户 Mac 上的真实数据；装真机与重装 Mac 版只在最后一个任务。
- 同步前 Mac 先把全部数据备份到「文稿/朝夕备份」；同步内容：规划数据、记账、日程、新的一天开始时间；不同步：每晚提醒、小组件筛选、模块组收起等界面偏好。
- 小组件、锁屏、快速记一条、每晚提醒都是可选入口，默认不出现 / 关闭（用户自己添加或在设置里打开）。
- 不在用户使用电脑时模拟点击；跑界面测试前看前台应用与空闲时间（同计划 1）。

## Review Focus

1. 新手机（空数据）第一次和 Mac 同步 → Mac 上的数据一条不少，手机拿到全部；空 ≠ 删除。→ Task 7 `emptyPhoneDoesNotEraseMac`
2. 两边分开时改了同一条 / 一边删了另一边后来又改 → 以后改的为准，两边结果一致；同步不会把旧改动打成「刚改」。→ Task 7 `laterEditWins`、`editAfterDeleteRevives`、`deleteAfterEditRemoves`、`mergedIsNotRestamped`
3. App 开着跨过「新的一天开始时间」→ 首页、日程、记账的「今天」自动换天。→ Task 1 `todayRollsOverWhileOpen`
4. 拖动 / 拉长每周重复的日程 → 先问「只改这一次 / 改全部」，选「只改这一次」后其他周不动。→ Task 3 `testDragRepeatingAsksScope`
5. 截图认不出金额 → 表单照样弹出、金额空、填好前不能保存；多张按「1/3」逐张确认。→ Task 5 `testScreenshotWithoutAmountNeedsInput`、`draftQueueAdvancesOnCancel`

---

### Task 1: 手机数据底座 + 首页遗留问题

**Files:**
- Modify: `Sources/Mobile/MobileState.swift`、`Sources/Mobile/TideMobileApp.swift`、`Sources/Mobile/Home/HomeScreen.swift`、`Sources/Mobile/Home/HomeRow.swift`、`Sources/Cre/Schedule/ScheduleView.swift`、`Sources/Cre/Ledger/ScreenshotLedger.swift`、`Sources/Cre/Ledger/LedgerView.swift`（`CategoryIcon` 移走）
- Create: `Sources/CreCore/ScheduleTray.swift`、`Sources/Shared/TextRecognition.swift`、`Sources/Shared/CategoryIcon.swift`
- Test: `Tests/CreCoreTests/ScheduleTrayTests.swift`、`Tests/CreCoreTests/DayStartTests.swift`、`Tests/MobileUITests/HomeUITests.swift`

**Interfaces:**
- Produces:
  - `Shared`/`Mobile`: `enum MobileFiles { static var directory: URL }`：App Group `group.com.lty.cre.mobile` 容器；首次启动把 `Documents/data.json` 移过去（已存在则不动）。`project.yml` 给 TideMobile 加该 App Group 授权。
  - `MobileState`: `@Published var ledger: LedgerData`、`@Published var schedule: ScheduleData`（同 `data` 的打时间戳 + 撤销写法，存 `MobileFiles.directory` 下 `ledger.json` / `schedule.json`，演示模式用 `DemoData.makeLedger/makeSchedule`）；`func add(_ raw: String, override: TimeChoice? = nil, groupID: UUID? = nil, defaultToViewingDay: Bool = true) -> Bool`（签名对齐 Mac `AppState.add`）。
  - `CreCore`: `public struct TrayItem: Equatable, Sendable { public var title: String; public var kind: EntryKind }`、`public func trayItems(on day: DayKey, today: DayKey, data: PlanData) -> [TrayItem]`（从 Mac `chipItems` 原样搬：当天未完成、组行展开为子项、同名去重）、`public func scheduleIsPast(_ o: ScheduleOccurrence, minuteNow: Int, today: DayKey) -> Bool`、`public func clock(_ minutes: Int) -> String`。Mac `ScheduleView` 改用它们。
  - `Shared`: `func recognizeLines(in image: CGImage) async -> [String]`（从 Mac 搬，Vision 两端可用）、`func draftEntry(from image: CGImage, ledger: LedgerData, today: DayKey) async -> (LedgerEntry, Bool)`、`enum CategoryIcon`（从 `LedgerView.swift` 搬）。

- [ ] **Step 1: 写失败测试**
  - `ScheduleTrayTests.trayListsOpenItemsOnce`：一条已完成、两条同名未完成、一个组行带两个子项 → 结果只含未完成项，同名一条，子项展开。
  - `ScheduleTrayTests.pastMeansEndedToday`：今天 9:00–10:00 在 `minuteNow` 600 时为已过、599 时未过；昨天任意为已过、明天为未过。
  - `DayStartTests.todayRollsOverWhileOpen`：`nextRefresh(after: 10月9日 23:59, startHour: 0)` 为 10月10日 0:00；`startHour: 4` 时为 10月10日 4:00（已有函数，补用例锁住手机要用的行为）。
  - `HomeUITests.testCalendarButtonNeedsText`：输入条为空时日历按钮不可点；输入文字后可点。
  - `HomeUITests.testRepeatRowArrowExpandsTapEdits`：演示数据「健身」行，点右侧箭头展开出「练臂」，点文字打开「编辑」。
  - `HomeUITests.testJapaneseCalendarKeepsChineseDates`：`-AppleLocale ja_JP@calendar=japanese` 下仍显示「10月9日」。
- [ ] **Step 2:** 跑 `swift test --filter "ScheduleTrayTests|DayStartTests"` 与 `TideMobileUITests/HomeUITests` → 新用例失败（函数未定义 / 行为不符）。
- [ ] **Step 3: 实现**
  - `CreCore/ScheduleTray.swift` 写上列三个函数；Mac `ScheduleView` 的 `chipItems`、`scheduleIsPast`、`clock` 改为调用它们。
  - `MobileState` 加 `ledger`、`schedule` 与 `add(groupID:defaultToViewingDay:)`；`today` 刷新：前台时按 `nextRefresh(after:startHour:)` 设一次性 `Timer`，并监听 `UIApplication.significantTimeChangeNotification`，触发 `refreshToday()`。
  - 输入条日历按钮 `.disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)`。
  - `HomeRow`：可展开行的箭头单独成按钮（`accessibilityIdentifier("expand-<text>")`），点它展开；点其余处走编辑（组行无编辑时仍展开）。
- [ ] **Step 4:** 跑 `swift test`（全部通过）与 `TideMobileUITests` 全部 → 通过；Mac `xcodebuild -scheme Cre build` 成功。
- [ ] **Step 5:** Commit `feat(mobile): ledger and schedule state, day rollover, home leftovers`；在 `progress/iphone.md` 勾掉对应的计划 2 条目。

### Task 2: 规划

**Files:**
- Create: `Sources/Mobile/Planning/PlanningScreen.swift`、`GroupCardView.swift`、`PlanItemRow.swift`、`NewGroupScreen.swift`、`DayPlanScreen.swift`
- Modify: `Sources/Mobile/RootTabs.swift`
- Test: `Tests/MobileUITests/PlanningUITests.swift`

**Interfaces:**
- Consumes: Task 1 `MobileState.add(_:override:groupID:defaultToViewingDay:)`；`CreCore` 已有 `addGroup`、`setGroupSchedule`、`updateGroup`、`moveTodo`、`setOngoing`、`deleteGroup`、`updateRepeat`、`streak`。
- Produces: `struct PlanItemRow: View`（`state: MobileState, todo: Todo`），其长按菜单含「移到」「写感想 / 查看感想」「删除」，首页在 Task 6 复用同一菜单 `PlanItemMenu`。

界面（与 Mac `PlanningView` / `GroupCard` / `NewGroupSheet` 功能逐项对应）：
- 顶部 `PageTitleRow`「规划」，右侧「＋」新建模块组（名称 → 类型 → 排期方式 → 具体排期，同 Mac 步骤），以 `NavigationStack` 推入的整页表单呈现。
- 模块组卡片单列；卡片头点按收起 / 展开；卡片头「…」菜单：置顶 / 取消置顶、重命名、编辑安排（循环）、编辑排期、首页显示（展开 / 一行 / 不显示）、归档、删除（二次确认，写明条数）。循环组显示「连续 N 次」。
- 卡片内每行：圆圈打勾、优先级、文字（点按 → 首页同款编辑卡片）、时间标签、「▶ 进行中」切换；已完成且有感想的行显示完成日。左滑删除；长按菜单（移到 / 写感想 / 删除）。
- 每张卡片末尾「＋ 加一项」：点开成输入框，回车后保持打开以便接着输；规则同 Mac `InlineAdd`（`GroupCard.swift:243-294`）。
- 底部：零散待办卡片；再下方「已归档 N」折叠区，可恢复 / 删除。
- 底部输入条：加到零散待办，不自动落到某天（`defaultToViewingDay: false`）。

- [ ] **Step 1: 写失败测试**（演示数据）
  - `testCollapseCard`：点「读书」卡片头 → 其中「人类简史」不可见；再点 → 可见。
  - `testInlineAddStaysOpen`：在一张卡片点「＋ 加一项」，输入「球状闪电\n」「流浪地球\n」→ 两条都出现在该卡片。
  - `testNewGroupFlow`：「＋」→ 名称「晨练」→ 类型选循环 → 保存 → 出现「晨练」卡片。
  - `testArchiveAndRestore`：卡片「…」→ 归档 → 卡片消失、「已归档 1」出现 → 展开点「恢复」→ 卡片回来。
  - `testBottomInputAddsLoose`：底部输入「买电池\n」→ 出现在「零散待办」。
- [ ] **Step 2:** 跑 `TideMobileUITests/PlanningUITests` → 失败（找不到元素）。
- [ ] **Step 3:** 按上述界面实现，`RootTabs` 的「规划」换成 `PlanningScreen`。
- [ ] **Step 4:** 跑 `TideMobileUITests` 全部 → 通过。
- [ ] **Step 5:** Commit `feat(mobile): planning board`。

### Task 3: 日程（竖屏单天 / 横屏一周）

**Files:**
- Create: `Sources/Mobile/Schedule/ScheduleScreen.swift`、`DayTimeline.swift`、`WeekStrip.swift`、`TrayPanel.swift`、`ScheduleEditScreen.swift`
- Modify: `Sources/Mobile/RootTabs.swift`
- Test: `Tests/MobileUITests/ScheduleUITests.swift`

**Interfaces:**
- Consumes: Task 1 `trayItems`、`scheduleIsPast`、`clock`；`CreCore` `ScheduleData.layout(on:)`、`add`、`move`、`update`、`delete`、`snapMinute`、`minutesInTitle`。

界面：
- 竖屏：`PageTitleRow`「日程」+ 右侧「今天」；下方一周日期条（周一至周日，选中天高亮、今天蓝字），左右滑日期条换周、左右滑时间轴换天。
- 时间轴：每小时一格，块按 `layout(on:)` 分列；块颜色规则见 Global Constraints；跨整点的块不被分割线割开，块与块、块与整点线之间留 2pt 间隙（同 Mac 飞书样式）。打开时滚到当前时刻附近。
- 点空白时段 → 新建（默认 1 小时，标题含时长则按时长）；点块 → 编辑页（标题、日期、起止、重复、删除）。重复项的保存 / 删除先问「只改这一次 / 改全部」。
- 长按块拖动改时间（15 分钟吸附），拖下边缘改时长；重复项松手后同样先问范围。
- 右下「待办」按钮拉出底部待办卡片（同一视图内的浮层，不是弹窗，以便拖动）：当天未完成待办，已排的显示开始时间并用块的颜色；可长按拖到时间轴，或点选（高亮）后点时段放入；提示文案「拖到时间表，或点卡片再点时段」/「点一个时段放入」。
- 横屏：七天周视图（同 Mac `WeekGrid` 交互），隐藏日期条；转回竖屏保持所看的那天。

- [ ] **Step 1: 写失败测试**（演示数据）
  - `testTapSlotCreates`：点时间轴 14:00 附近 → 编辑页标题输入「开会」→ 保存 → 时间轴出现「开会」。
  - `testDragRepeatingAsksScope`：长按演示数据中每周重复的「健身」块（一三五 19:00）向下拖 → 出现「只改这一次」「改全部」；选「只改这一次」→ 翻到下一周同一天，该块仍在原时间。
  - `testTrayTapThenSlot`：点「待办」→ 点「交周报」卡片 → 点 16:00 → 时间轴出现「交周报」，卡片显示「16:00」。
  - `testRotationKeepsDay`：切到后天 → `XCUIDevice.shared.orientation = .landscapeLeft` → 再转回 `.portrait` → 日期条选中的仍是后天。
- [ ] **Step 2:** 跑 `TideMobileUITests/ScheduleUITests` → 失败。
- [ ] **Step 3:** 按上述界面实现。
- [ ] **Step 4:** 跑 `TideMobileUITests` 全部 → 通过。
- [ ] **Step 5:** Commit `feat(mobile): schedule board, portrait day and landscape week`。

### Task 4: 记账（主页面、表单、统计、分类与起始余额）

**Files:**
- Create: `Sources/Mobile/Ledger/LedgerScreen.swift`、`LedgerFormScreen.swift`、`LedgerStatsView.swift`、`CategoryScreen.swift`、`OpeningScreen.swift`
- Modify: `Sources/Mobile/RootTabs.swift`
- Test: `Tests/MobileUITests/LedgerUITests.swift`

**Interfaces:**
- Consumes: Task 1 `MobileState.ledger`、`CategoryIcon`；`CreCore` `parseLedger`、`monthTotals`、`dayGroups`、`categoryShare`、`monthlyTrend`、`balance(asOf:)`、`money`。
- Produces: `struct LedgerFormScreen: View`（`state, entry: LedgerEntry?, prefill: LedgerEntry?, position: String?, onClose: () -> Void`），Task 5 的截图草稿复用它。

界面（对应 Mac `LedgerView`，按已定的 Mac 视觉：布局 A、余额靠右绿色、收入 / 支出 / 净收入黑色、字号一致）：
- `PageTitleRow`「记账」，右侧「…」：分类管理、起始余额。
- 顶部：‹ 2026年10月 ›（点月份选日 → 只看那天，「本月」回到整月）；一行收入 / 支出 / 净收入 / 余额。
- 「流水 / 统计」分段。流水：按天分组（天标题带当天收支），行 = 分类图标 + 分类 + 备注 + 金额；点行编辑，左滑删除。统计：支出 / 收入分类占比（环形图 + 列表）与近 6 个月趋势（柱状）。
- 底部输入条，占位文字「午饭 35」（同 Mac），旁边相机按钮（Task 5 接入菜单，本任务先放按钮占位为禁用）。识别不了的输入 → 打开表单并带上文字为备注。
- 表单：金额、收入 / 支出、分类（图标网格）、备注、日期（不能选未来）；编辑时顶部右侧「保存」，底部「删除」。

- [ ] **Step 1: 写失败测试**（演示数据）
  - `testTypeLineAddsEntry`：输入「午饭 32\n」→ 流水今天出现「午饭」「-32」，支出合计增加 32。
  - `testEditEntry`：点一条流水 → 金额改为 40 → 保存 → 行显示「-40」。
  - `testSwipeDeleteEntry`：左滑一条 → 删除 → 消失。
  - `testStatsTab`：切「统计」→ 出现「餐饮」占比行。
  - `testOpeningBalance`：「…」→ 起始余额 → 1000 → 保存 → 顶部余额行出现且为绿色文字所在元素（按 identifier `balance` 存在即可）。
- [ ] **Step 2:** 跑 `TideMobileUITests/LedgerUITests` → 失败。
- [ ] **Step 3:** 按上述界面实现。
- [ ] **Step 4:** 跑 `TideMobileUITests` 全部 → 通过。
- [ ] **Step 5:** Commit `feat(mobile): ledger board`。

### Task 5: 记账的四种截图入口

**Files:**
- Create: `Sources/Mobile/Ledger/ScreenshotIntake.swift`（相册多选、拍照、粘贴、草稿队列）、`Sources/Mobile/Ledger/LatestScreenshot.swift`、`Sources/ShareExtension/ShareViewController.swift`
- Modify: `apps/Cre/project.yml`（相册 / 相机用途说明；分享扩展 target `TideShare`，`com.lty.cre.mobile.share`，同一 App Group）、`LedgerScreen.swift`
- Test: `Tests/CreCoreTests/DraftQueueTests.swift`、`Tests/MobileUITests/LedgerUITests.swift`

**Interfaces:**
- Consumes: Task 1 `draftEntry(from:ledger:today:)`；Task 4 `LedgerFormScreen(position:)`。
- Produces: `CreCore` `public struct DraftQueue<T> { public init(_ items: [T]); public var current: T?; public var position: String? /* "2/3"，单张为 nil */; public mutating func advance() }`。

- [ ] **Step 1:** 分享扩展：接收图片，写进 App Group 容器的 `inbox/<uuid>.png` 后结束（扩展里不做识别）；主 App 回到前台时读取 `inbox/`，逐张走草稿队列，处理完删除文件。（App Group 免费签名可用已于 2026-10-10 验证。）
- [ ] **Step 2: 写失败测试**
  - `DraftQueueTests.draftQueueAdvancesOnCancel`：三项 → `position == "1/3"`，`advance()` 两次后 `"3/3"`，再 `advance()` 后 `current == nil`；单项时 `position == nil`。
  - `LedgerUITests.testScreenshotWithoutAmountNeedsInput`：演示模式下用启动参数 `-demoScreenshot noAmount` 注入一张无金额图片走同一流程 → 表单出现、金额为空、「保存」禁用，填 20 后可保存。
- [ ] **Step 3:** 跑 `swift test --filter DraftQueueTests` 与该 UI 用例 → 失败。
- [ ] **Step 4: 实现**
  - 相机按钮菜单：拍照（`UIImagePickerController`，无相机时隐藏）、从相册选（`PhotosPicker`，多选，不需权限）、粘贴（`UIPasteboard.general.images`，无图时禁用）。选中的图片按 `DraftQueue` 逐张识别并弹 `LedgerFormScreen`，标题带「1/3」。
  - 最新截图：首次进入记账时请求相册读取权限（只问一次）；之后每次 App 回到前台且在记账页，取最近 10 分钟内、未处理过的一张截图（`PHAssetMediaSubtype.photoScreenshot`），顶部出现「记录这张？」条，点按进入同一流程，「×」忽略；处理过的资源 id 记在 `UserDefaults`。无权限时不显示、不再请求。
- [ ] **Step 5:** 跑 `swift test` 与 `TideMobileUITests` 全部 → 通过；手动核对：模拟器拒绝相册权限后进记账，无提示条、相册多选仍可用。
- [ ] **Step 6:** Commit `feat(mobile): screenshot ledger — album, camera, paste, latest screenshot, share`。

### Task 6: 总结 + 首页长按菜单补齐

**Files:**
- Create: `Sources/Mobile/Summary/SummaryScreen.swift`、`DailySummaryScreen.swift`、`ReportScreen.swift`、`ReflectionScreen.swift`、`NewSummaryScreen.swift`
- Modify: `Sources/Mobile/RootTabs.swift`、`Sources/Mobile/Home/HomeScreen.swift`（「总结今天」改为推入 `DailySummaryScreen`）、`Sources/Mobile/Home/HomeRow.swift`（长按菜单用 `PlanItemMenu`）
- Test: `Tests/MobileUITests/SummaryUITests.swift`

**Interfaces:**
- Consumes: Task 2 `PlanItemMenu`；`CreCore` `generateSummary`、`deleteSummary`、`addTemplate`、`generate(templateID:)`、`makeReport`、`deleteReport`、`deleteTemplate`、`saveReflection`、`saveFreeReflection`、`deleteReflection`、`reflectionChoices`、`defaultReflectionTarget`、`reflectionTitle`。

界面（对应 Mac `SummaryView` / `CustomSummaryViews` / `ReflectionEditor`，两层：列表 → 详情）：
- 列表：`PageTitleRow`「总结」，右侧「新建」菜单（总结 / 感想）；分组「每日总结」（今天、有总结或随笔的日子，带完成率或「未生成」）、「模板」（点按生成一份报告并打开）、「感想」（标题 + 完成日）、各报告组。左滑删除（总结、模板、报告各自二次确认，文案同 Mac）。
- 每日总结详情：大标题日期 + ‹ › + 日历（不超过今天）；完成 x/y · z% 与进度条；已完成 / 未完成列表；「生成总结」/「重新生成」；随笔输入框停顿 0.6 秒自动保存、离开页面保存。
- 新建总结：看什么 / 看多久（含日历自选范围）/ 统计什么 / 存为模板，同 Mac 字段。
- 感想：选清单 → 选条目（已完成 / 未打勾 / 已写过，同 Mac 规则）或「其他」自填标题；完成日；正文。保存未打勾项时顺手打勾（同 Mac）。
- 首页与规划的行长按菜单统一为「移到」「写感想 / 查看感想」「删除」，写的感想出现在总结的「感想」里。

- [ ] **Step 1: 写失败测试**（演示数据）
  - `testDailyNoteAutosaves`：进今天的每日总结 → 随笔输入「状态不错」→ 返回 → 再进 → 文字仍在。
  - `testTemplateGeneratesReport`：新建总结 → 勾「存为模板」名「周报」→ 生成 → 返回列表，「模板」下有「周报」，点它打开一份报告。
  - `testReflectionFromPlanningShowsInSummary`：规划里长按「人类简史」→ 写感想「很好看」→ 保存 → 总结列表「感想」下出现「人类简史」。
  - `testHomeLongPressMenu`：首页长按「交周报」→ 菜单有「移到」「写感想」「删除」。
  - `testSwipeDeleteSummaryAsks`：左滑一条每日总结 → 删除 → 出现确认「随笔会保留。」。
- [ ] **Step 2:** 跑 `TideMobileUITests/SummaryUITests` → 失败。
- [ ] **Step 3:** 按上述界面实现。
- [ ] **Step 4:** 跑 `TideMobileUITests` 全部 → 通过。
- [ ] **Step 5:** Commit `feat(mobile): summary board; shared row menu with reflections`。

### Task 7: 与 Mac 同步

**Files:**
- Create: `Sources/CreCore/Merge.swift`、`Sources/CreCore/SyncProtocol.swift`、`Sources/CreCore/SyncServer.swift`、`Sources/CreCore/SyncClient.swift`、`Sources/Cre/SyncHost.swift`（Mac：服务、配对码窗口、备份）、`Sources/Mobile/Sync/SyncCoordinator.swift`、`Sources/Mobile/Sync/PairScreen.swift`
- Modify: `Sources/CreCore/Stamps.swift`（模块组「收起」不算内容修改）、`Sources/CreCore/WidgetSupport.swift`（`day-start.json` 加修改时间）、`Sources/Cre/AppState.swift`（收到合并结果走 `applyingExternal`）、`Sources/Cre/Placeholders.swift`（Mac 设置里「手机」：已配对设备、取消配对）、`MobileState.swift`（同样的外部写入不打时间戳、不进撤销）、`project.yml`（手机 `NSLocalNetworkUsageDescription`「与 Mac 上的朝夕同步」、`NSBonjourServices` `_tide._tcp`）
- Test: `Tests/CreCoreTests/MergeTests.swift`、`Tests/CreCoreTests/SyncLoopbackTests.swift`

**Interfaces:**
- Produces:
  - `extension PlanData { public func merged(with other: PlanData) -> PlanData }`，`LedgerData`、`ScheduleData` 同名。规则：按键对比；`modifiedAt` 较晚者胜（nil 视为最早）；某键有删除记号且记号晚于对方该记录的 `modifiedAt` → 删除，否则记录复活并去掉记号；删除记号取两边并集（同键取较晚）；`notes` / `pulledTags` 按各自 stamps 逐天取较晚；记账分类与起始余额按 `settingsModifiedAt`；模块组 `collapsed` 保留本机值。
  - `public func pruneDeletions(_ d: inout [String: Date], olderThan days: Int, now: Date)`，同步成功后清掉 30 天前的记号。
  - `public struct DayStartSetting: Codable, Equatable { public var hour: Int; public var modifiedAt: Date? }`；`day-start.json` 读旧格式（纯数字）照常。
  - `public struct SyncPayload: Codable { plan: PlanData; ledger: LedgerData; schedule: ScheduleData; dayStart: DayStartSetting }`；请求 `enum SyncRequest: Codable { case pair(deviceName: String), confirm(code: String, deviceName: String), sync(token: String, payload: SyncPayload) }`；回应 `enum SyncResponse: Codable { case codeShown, paired(token: String), badCode, unpaired, synced(SyncPayload) }`；帧格式：4 字节大端长度 + JSON。
  - `public final class SyncServer`（`NWListener`，Bonjour `_tide._tcp`，回调 `onPairRequest(deviceName) -> code`、`onSync(payload) -> SyncPayload`、`isTokenValid`）；`public final class SyncClient`（`NWBrowser` 发现，或直连 `host:port` 供测试），`func send(_ r: SyncRequest) async throws -> SyncResponse`。

- [ ] **Step 1: 写失败测试**（`MergeTests`）
  - `laterEditWins`：同一待办 A 侧 10:00 改为「甲」、B 侧 11:00 改为「乙」→ 两个方向合并都是「乙」。
  - `editAfterDeleteRevives`：A 9:00 删除（记号 9:00），B 10:00 改了它 → 合并后在，记号去掉。
  - `deleteAfterEditRemoves`：B 9:00 改，A 10:00 删 → 合并后不在，记号保留。
  - `emptyPhoneDoesNotEraseMac`：空 `PlanData()` 与有 5 条待办、3 笔账、2 条日程的数据合并 → 全部保留。
  - `mergedIsNotRestamped`：合并结果再经 `stamped(since: 合并前本机, now:)` 时，来自对方的记录保持对方的 `modifiedAt`（本机保存路径须走「外部写入」）。用 `MobileState`/`AppState` 无法在包测试里构造，故测纯函数：`merged` 输出的每条记录 `modifiedAt` 等于胜出一方的值。
  - `collapsedIsLocal`：仅 `collapsed` 不同 → `stamped` 不改 `modifiedAt`，合并保留本机 `collapsed`。
  - `notesMergePerDay`、`ledgerSettingsByStamp`、`pruneDropsOldMarks`（31 天前的记号被清、29 天的保留）、`dayStartOldFormatLoads`。
- [ ] **Step 2:** `swift test --filter MergeTests` → 失败。
- [ ] **Step 3:** 实现 `Merge.swift`、`Stamps.swift` 改动、`DayStartSetting`。
- [ ] **Step 4:** `swift test --filter MergeTests` → 通过。
- [ ] **Step 5: 写失败测试**（`SyncLoopbackTests`，本机回环，不用 Bonjour）
  - `pairThenSync`：起 `SyncServer`（端口 0），客户端 `pair` → `codeShown`；`confirm` 错码 → `badCode`；正确码 → `paired(token)`；带 token `sync` → `synced`，返回的是双方合并结果。
  - `unknownTokenIsRejected`：随便的 token → `unpaired`。
- [ ] **Step 6:** 实现协议、服务端、客户端 → `swift test` 全部通过。
- [ ] **Step 7: Mac 端**（`SyncHost`）：App 启动即开服务；收到配对请求时弹一个置顶小窗显示 4 位数字（1 分钟有效）；与某台手机首次同步前，把 `data.json`、`ledger.json`、`schedule.json`、`day-start.json` 复制到 `~/Documents/朝夕备份/<yyyy-MM-dd HHmm>/`；合并后经 `applyingExternal` 写入并保存；已配对设备（名称、token、上次同步）存 App Group 下 `sync-devices.json`。Mac 设置加「手机」一节：列出设备与上次同步时间，「取消配对」。
- [ ] **Step 8: 手机端**（`SyncCoordinator`）：有 token 时在 App 回到前台、改动后 3 秒、前台每 30 秒各同步一次；发现不到 Mac 就静默跳过，下次补；收到结果与本机当前数据再合并一次后按外部写入保存（不打时间戳、不进撤销）；成功后清理 30 天前的删除记号。设置页加「同步」一节：状态（「已连接 <Mac 名> · 上次同步 22:10」/「未连接」）、「连接 Mac」（`PairScreen`：搜索 → 选 Mac → 输入 4 位数字）、「断开」。
- [ ] **Step 9: 联调**（不碰真实数据）：Mac 版以 `CRE_DEMO=1` 启动（演示临时文件），手机模拟器同样 `CRE_DEMO=1`；配对、各改一条、等 30 秒 → 两边一致；确认 `~/Documents/朝夕备份/` 生成了备份目录（演示模式下备份目录名加「演示」前缀，联调后删掉）。
- [ ] **Step 10:** `progress/iphone.md` 勾掉三条计划 4 遗留问题。Commit `feat: Wi-Fi sync between Mac and iPhone`。

### Task 8: 主屏幕与锁屏小组件

**Files:**
- Create: `Sources/MobileWidget/`（`TideMobileWidget.swift` 入口、`TodayWidget.swift`、`LockWidgets.swift`）
- Modify: `project.yml`（新 target `TideMobileWidget`，`com.lty.cre.mobile.widget`，同一 App Group；与 Mac 小组件共用的视图 / `ToggleTodoIntent` 拆到 `Sources/WidgetShared/` 两端都编）、`Sources/CreWidget/CreWidget.swift`
- Test: `Tests/CreCoreTests/WidgetFilterTests.swift`（补用例）

- [ ] **Step 1: 写失败测试**：`lockLineShowsNextOpen`：`lockScreenSummary(agenda:)` 返回「完成 2/5」与第一条未完成的文字；全部完成时下一条为 nil（新纯函数放 `CreCore/WidgetSupport.swift`）。
- [ ] **Step 2:** `swift test --filter WidgetFilterTests` → 失败；实现函数 → 通过。
- [ ] **Step 3:** 主屏幕小 / 中 / 大：同 Mac 桌面小组件——今天的待办、点圆圈打勾（`ToggleTodoIntent`，写回 App Group 数据并打时间戳）、按标签筛选（小组件编辑里选标签，`AppIntentConfiguration`）。锁屏：矩形「完成 2/5 · 下一条」、圆形完成环；点按打开 App。App 每次保存后 `WidgetCenter.shared.reloadAllTimelines()`。
- [ ] **Step 4:** Mac `xcodebuild -scheme Cre build` 与手机 `TideMobile` 构建都成功；模拟器加小组件截图核对三种尺寸与锁屏。
- [ ] **Step 5:** Commit `feat(mobile): home and lock screen widgets`。

### Task 9: 快速记一条、每晚提醒、设置页补齐

**Files:**
- Create: `Sources/Mobile/QuickAdd/QuickAddIntent.swift`、`Sources/Mobile/QuickAdd/QuickAddSheet.swift`、`Sources/MobileWidget/QuickAddControl.swift`、`Sources/Mobile/Reminder/NightlyReminder.swift`
- Modify: `TideMobileApp.swift`（`tide://quickadd` 打开快速记一条；通知点按打开今天的每日总结）、`HomeScreen.swift` 的 `MobileSettingsSheet`
- Test: `Tests/MobileUITests/QuickAddUITests.swift`

- [ ] **Step 1: 写失败测试**
  - `testQuickAddURLOpensSheet`：以 `tide://quickadd` 启动 → 出现只有一行输入的「记一条」弹层；输入「明天 买牛奶\n」→ 弹层关闭，翻到明天能看到「买牛奶」。
  - `testReminderDefaultsOff`：设置页「每晚提醒」开关为关。
- [ ] **Step 2:** 跑 → 失败。
- [ ] **Step 3: 实现**
  - `QuickAddIntent`（App Intent，参数「内容」，`requestValueDialog`「记什么？」），直接在 App Group 数据上 `addLine` 并打时间戳，不打开 App；`AppShortcutsProvider` 提供「用朝夕记一条」，可绑侧边操作按钮 / 快捷指令。
  - 控制中心按钮 `QuickAddControl`（iOS 18 `ControlWidgetButton`，`@available(iOS 18, *)`）：打开 `tide://quickadd`。
  - 每晚提醒：设置里开关（默认关）+ 时间（默认 22:00，同 Mac）；打开时请求通知权限，排每日重复通知「朝夕 / 总结一下今天？」；关闭即取消。
  - 设置页最终顺序：新的一天、同步（Task 7）、每晚提醒。
- [ ] **Step 4:** 跑 `TideMobileUITests` 全部 → 通过。
- [ ] **Step 5:** Commit `feat(mobile): quick add, nightly reminder, settings`。

### Task 10: 整体自查（功能 + 视觉）

**Files:** 按发现修改上述各屏。

- [ ] **Step 1:** 临时截图测试（不提交）逐屏截：规划（含展开 / 归档区）、新建模块组、日程竖屏 / 横屏 / 待办卡片 / 编辑页、记账流水 / 统计 / 表单 / 「记录这张？」、总结列表 / 每日总结 / 新建 / 感想、设置（同步 / 提醒）、配对、记一条、小组件；浅色与深色各一遍。
- [ ] **Step 2:** 用 `~/.claude/skills/redesign-skill` 清单对照首页已定风格逐屏检查：标题位置与留白、边距对齐、单一强调色、空状态居中、按钮位置（取消 / 保存顶部两侧）、深色模式可读。问题直接修，修后再截一次确认。
- [ ] **Step 3:** 跑 `swift test` 与 `TideMobileUITests` 全部 → 通过；Mac `xcodebuild -scheme Cre build` 成功。
- [ ] **Step 4:** 功能自查：按方案第二至四节逐条对照，列出「已做 / 与方案不同之处 / 建议改进」清单，写进 `progress/iphone.md`，在最终汇报里给用户。
- [ ] **Step 5:** Commit `fix(mobile): visual and functional pass across boards`。

### Task 11: 装到手机与 Mac + 进度记录

- [ ] **Step 1:** 用户 iPhone 已连接时运行 `apps/Cre/install-phone.sh`，确认输出「已装到 iPhone」。
- [ ] **Step 2:** 先确认用户没在用 Mac 版朝夕（看前台应用），再运行 `apps/Cre/build.sh` 重装 Mac 版（带同步服务）；数据文件不动。
- [ ] **Step 3:** 更新 `docs/开发过程/progress/iphone.md`：计划 2 完成范围、测试数、留给后续计划的问题（含 Task 5 探路结论）。
- [ ] **Step 4:** Commit `docs: iPhone plan 2 progress`。
