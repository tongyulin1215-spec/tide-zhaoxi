# 朝夕 iPhone 版 · 计划 1：数据改造 + 手机骨架与首页 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给所有记录加上「最后修改时间 / 删除记号」（Mac 版先用上），并做出能装到 iPhone 上用的朝夕：底部图标栏 + 完整首页 + 一键重装脚本。

**Architecture:** `CreCore`（纯 Foundation）同时编译给 macOS 和 iOS；改动打时间戳用「新旧对比」一次算出（`stamped(since:now:)`），不改散落各处的修改方法。两端共用的 SwiftUI 小部件移到 `Sources/Shared`，同时编进 Mac 与手机两个 target；手机界面在 `Sources/Mobile`，状态对象 `MobileState` 只做手机需要的部分，增删改的规则统一放进 `CreCore`。

**Tech Stack:** Swift 6.4、SwiftUI（iOS 17 / macOS 14）、xcodegen、Swift Testing、`xcrun devicectl`（真机安装）。

**Spec:** `docs/开发过程/specs/2026-10-09-iphone-design.md`

**范围：** 方案「开发顺序」第 1、2 步。第 3 步（其余板块）、第 4 步（同步）、第 5 步（快捷入口）、第 6 步（自查）各自另写计划。

## Global Constraints

- iOS 17 起；macOS 14 起不变。
- 免费签名（团队 XZLHB3F367），真机 7 天重装；不使用 iCloud。
- 手机数据格式与 Mac 完全相同（`data.json` / `ledger.json` / `schedule.json`）；新字段一律可缺省，旧文件照常读。
- Mac 版现有行为、数据、界面不变（除了内部多存时间戳）。
- 手机：底部图标栏「首页、规划、日程、记账、总结」，设置在首页右上齿轮；输入条在底部。
- 手势：点圆圈打勾；点一行出底部编辑卡片（含改名）；左滑删除；长按菜单；摇一摇撤销。
- 界面文字精炼，沿用 Mac 版已有文案（如「记录想法或安排」「DDL 10月8日」「拖了 N 天」）。
- 不碰用户真实数据：开发验证只用模拟器或 `CRE_DEMO=1`。

## Review Focus

1. 旧数据文件（没有任何时间戳字段）在新版 Mac 上打开、改一条、保存 → 其他记录不应被误标为「刚改过」。→ Task 2 `untouchedRecordsKeepNoStamp`
2. 只改了一条待办的文字 → 只有这一条的修改时间变，模块组、其他待办不变。→ Task 2 `onlyTheEditedTodoIsStamped`
3. 删除后撤销（⌘Z / 摇一摇）→ 记录回来，删除记号要清掉，否则日后同步会把它再删掉。→ Task 2 `restoringRemovesDeletionMark`
4. 小组件写回的改动（Mac `applyingExternal`）→ 不应被重新打成 Mac 的时间。→ Task 3 手动核对步骤
5. 手机在非公历/12 小时制系统设置下 → 日期仍按 `DayKey` 显示「10月9日 周五」。→ Task 6 模拟器切换地区核对

---

### Task 1: CreCore 支持 iOS

**Files:**
- Modify: `apps/Cre/Package.swift`（platforms 加 `.iOS(.v17)`）

- [ ] **Step 1:** 改 platforms 为 `[.macOS(.v14), .iOS(.v17)]`。
- [ ] **Step 2:** 验证：`cd apps/Cre && xcodebuild -scheme CreCore -destination 'generic/platform=iOS Simulator' -quiet build` 成功；`swift test` 全部通过（当前 211）。
- [ ] **Step 3:** Commit `build: CreCore builds for iOS`。

### Task 2: 修改时间与删除记号

**Files:**
- Create: `apps/Cre/Sources/CreCore/Stamps.swift`
- Modify: `Models.swift`（`Todo`、`TodoGroup`）、`Summary.swift`（`DailySummary`）、`CustomSummary.swift`（`SummaryTemplate`、`SummaryReport`）、`Reflection.swift`、`Ledger.swift`（`LedgerEntry`、`LedgerData`）、`Schedule.swift`（`ScheduleItem`、`ScheduleData`）、`PlanData.swift`
- Test: `apps/Cre/Tests/CreCoreTests/StampTests.swift`

**Interfaces:**
- Produces:
  - 上列每个记录类型新增 `public var modifiedAt: Date?`（可缺省解码，编码时为 nil 不写出）。
  - `PlanData` 新增 `deletions: [String: Date]`、`noteStamps: [DayKey: Date]`、`pulledTagStamps: [DayKey: Date]`；`LedgerData` / `ScheduleData` 新增 `deletions: [String: Date]`、`settingsModifiedAt: Date?`（记账分类与起始余额共用）。删除记号的键：`"todo:<uuid>"`、`"group:<uuid>"`、`"summary:<yyyy-MM-dd>"`、`"template:<uuid>"`、`"report:<uuid>"`、`"reflection:<uuid>"`、`"entry:<uuid>"`、`"schedule:<uuid>"`。
  - `extension PlanData { public func stamped(since old: PlanData, now: Date) -> PlanData }`，`LedgerData`、`ScheduleData` 同名同签名。
  - 规则：按 id 对比新旧；内容（忽略 `modifiedAt`）不同 → `modifiedAt = now`；旧有新无 → 写删除记号；新出现且有删除记号 → 去掉记号（撤销 / 恢复）；`notes`、`pulledTags` 按天对比写各自 stamps。

- [ ] **Step 1: 写失败测试**（`StampTests.swift`）
  - `onlyTheEditedTodoIsStamped`：两条待办 + 一个模块组，改其中一条文字后 `stamped(since:now:)` → 该条 `modifiedAt == now`，另一条与模块组为 nil。
  - `untouchedRecordsKeepNoStamp`：解码一份不含任何新字段的旧 JSON，只勾选一条 → 仅此条有时间。
  - `deletingWritesAMark` / `restoringRemovesDeletionMark`：删一条 → `deletions["todo:<id>"] == now`；再以旧数据为新值 stamp → 记号消失。
  - `noteChangeStampsThatDay`：改 10/5 随笔 → `noteStamps[d(10,5)] == now`，其他天无。
  - `ledgerAndScheduleStampLikewise`：账目改金额、日程拖动、删除各一 → 对应时间 / 记号。
  - `stampsSurviveSaveAndOldFilesLoad`：编码再解码相等；旧文件解码后新字段为空。
- [ ] **Step 2:** `swift test --filter Stamp` → 编译失败（`stamped` 未定义）。
- [ ] **Step 3:** 实现字段与三个 `stamped(since:now:)`；比较时先把双方 `modifiedAt` 置 nil 再判等。
- [ ] **Step 4:** `swift test` 全部通过。
- [ ] **Step 5:** Commit `feat(core): per-record modified time and deletion marks`。

### Task 3: Mac 保存时打时间戳

**Files:**
- Modify: `apps/Cre/Sources/Cre/AppState.swift`（`data` / `ledger` / `schedule` 的 didSet）

**Interfaces:**
- Consumes: Task 2 的 `stamped(since:now:)`。

- [ ] **Step 1:** 在三个 didSet 里、保存之前，非外部载入时：`let s = new.stamped(since: oldValue, now: Date())`，若与当前值不同则在 `stamping` 标志保护下回写（避免递归、避免重复登记撤销）。外部载入（`applyingExternal`）不打戳。
- [ ] **Step 2:** `./build.sh` 成功；`swift test` 全部通过。
- [ ] **Step 3: 手动核对（演示数据，`CRE_DEMO=1`）**：勾一条待办 → 演示数据文件里只有该条出现 `modifiedAt`；删除一条后 ⌘Z → 记录回来且 `deletions` 为空；桌面小组件里勾一条 → Mac 端该条时间不被改写。
- [ ] **Step 4:** Commit `feat(mac): stamp changes before saving`。

### Task 4: 增改规则移进 CreCore

**Files:**
- Modify: `apps/Cre/Sources/CreCore/PlanData.swift`、`apps/Cre/Sources/Cre/AppState.swift`
- Test: `apps/Cre/Tests/CreCoreTests/AddLineTests.swift`

**Interfaces:**
- Produces（`extension PlanData`）：
  - `@discardableResult mutating func addLine(_ raw: String, override: TimeChoice?, groupID: UUID?, viewingDay: DayKey?, today: DayKey, now: Date) -> UUID?` —— 现 `AppState.add` 的逻辑；`viewingDay` 为 nil 表示不设时间时保持不设。
  - `mutating func rename(_ id: UUID, _ text: String)`（空白不改）、`mutating func setTime(_ id: UUID, _ choice: TimeChoice)`。
  - `TimeChoice` 若在 Mac target 中，移到 CreCore。
- [ ] **Step 1: 失败测试**：`addLineParsesAndFallsBackToViewingDay`（"交周报 p1" + viewingDay 10/7 → `.day(10/7)`、P1）、`addLineKeepsUndatedInGroups`（viewingDay nil → `.none`）、`renameIgnoresBlank`、`setTimeKeepsTagsWhenNil`。
- [ ] **Step 2:** 运行 → 失败。
- [ ] **Step 3:** 实现并让 `AppState.add / editText / setTime` 改为调用它们。
- [ ] **Step 4:** `swift test` 通过；`./build.sh` 成功。
- [ ] **Step 5:** Commit `refactor: add/rename/setTime live in CreCore`。

### Task 5: 共用界面部件 + 手机 App 骨架

**Files:**
- Create: `apps/Cre/Sources/Shared/`（从 Mac target 移入：`Theme.swift` 的颜色与 `Fmt`、`Tag`、`PriorityChip`、`Ring`、`MonthCalendar.swift`、`SoftSegments`、`ToolbarIcon`），AppKit 专用处用 `#if os(macOS)` 包住。
- Create: `apps/Cre/Sources/Mobile/TideMobileApp.swift`、`MobileState.swift`、`RootTabs.swift`、`Resources/{zh-Hans,en}.lproj/InfoPlist.strings`
- Modify: `apps/Cre/project.yml`

**Interfaces:**
- Produces:
  - target `TideMobile`：iOS 17，bundle id `com.lty.cre.mobile`，显示名 zh「朝夕」/ en「Tide」，图标复用 `AppIcon`，sources 为 `Sources/Mobile` + `Sources/Shared`，依赖 `CreCore`；Mac target sources 加 `Sources/Shared`。
  - `@MainActor final class MobileState: ObservableObject`：`@Published var data: PlanData`（存 App 的 Documents/`data.json`，用 `PlanStore`，didSet 内打戳并保存）、`today`、`viewingDay`、`dayStartHour`（`UserDefaults`）、`add(_:)`、`toggle(_ entry: AgendaEntry)`、`rename`、`setTime`、`delete(_ id:)`、`weak var undoManager`；`CRE_DEMO=1` 时用演示数据（复用 Mac 的 `DemoData` 移到 Shared）。
  - `RootTabs`：`TabView`，五个页签与 Mac 侧边栏同图标同名；除首页外先放占位「即将推出」。
- [ ] **Step 1:** 移文件、改 project.yml，`xcodegen generate`。
- [ ] **Step 2:** 验证：`xcodebuild -scheme TideMobile -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build` 成功；`./build.sh`（Mac）成功；`swift test` 通过。
- [ ] **Step 3:** 模拟器启动（`CRE_DEMO=1`）截图：底部五个图标、首页标题可见。
- [ ] **Step 4:** Commit `feat(mobile): app skeleton with shared UI pieces`。

### Task 6: 手机首页

**Files:**
- Create: `apps/Cre/Sources/Mobile/Home/HomeScreen.swift`、`HomeRow.swift`、`BottomInputBar.swift`、`EditSheet.swift`、`HomeMenu.swift`

**Interfaces:**
- Consumes: Task 4 `addLine/rename/setTime`，Task 5 `MobileState`、Shared 部件，CreCore `agenda(for:today:data:sort:)`、`filtered`、`triageCandidates`、`makeDailySummary`。

- [ ] **Step 1: 页面结构**
  - 顶部：「今天 · 10月9日 周五」+ 完成数；‹ › 换天；点日期弹 `MonthCalendar`；右上「…」菜单（筛选、按标签拉入、排序）与齿轮（设置页占位：新的一天开始时间）。
  - 「总结一下今天」「整理拖延（N）」两个小按钮（整理拖延打开底部表单，选项「今天做」「改个日期」）。
  - 列表：未完成 / DDL 待办（N）折叠 / 已完成，文案与规则同 Mac。
  - 底部输入条「记录想法或安排」，在图标栏之上，随键盘上移；右侧日历按钮打开 `EditSheet` 先选时间。
- [ ] **Step 2: 行交互**：点圆圈打勾（完成后移到已完成并变浅）；点行其余处 → `EditSheet`（名称、时间类型、日期 / 起止、重复星期与开始日、标签 + 已有标签选择、优先级）；左滑「删除」；长按菜单「删除」；模块组整行点按展开子项。
- [ ] **Step 3: 撤销**：`MobileState.undoManager` 绑定窗口；摇一摇撤销 / 重做可用。
- [ ] **Step 4: 验证（模拟器 + 演示数据）**：截图核对上述元素；在模拟器里打勾、左滑删除、摇一摇（Device ▸ Shake）撤销、输入「从10.12开始，每天背单词半小时」后 10/12 出现；切到「English (US)、12 小时制」地区后日期仍显示「10月9日 周五」。
- [ ] **Step 5:** Commit `feat(mobile): home screen`。

### Task 7: 一键重装到 iPhone

**Files:**
- Create: `apps/Cre/install-phone.sh`

- [ ] **Step 1:** 脚本：`xcodegen generate` → `xcodebuild -scheme TideMobile -configuration Release -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath build/dd-ios build` → 用 `xcrun devicectl list devices` 找到已连接的 iPhone → `xcrun devicectl device install app --device <id> <Tide.app>`；找不到设备时打印「请用数据线连接 iPhone 并在手机上信任此电脑」。
- [ ] **Step 2:** 让用户插上手机运行一次（首次需在 iPhone「设置 ▸ 隐私与安全性 ▸ 开发者模式」打开，并在「VPN 与设备管理」信任开发者）；确认手机上出现「朝夕」并能打开首页。
- [ ] **Step 3:** Commit `chore: one-step iPhone install script`。

## 本计划完成后需要用户做的
- 插上 iPhone 运行 `apps/Cre/install-phone.sh`（首次按提示开开发者模式、信任开发者）。
- 在手机上试用首页，反馈手感；之后写计划 2（其余板块）。
