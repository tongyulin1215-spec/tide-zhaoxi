# Cre · 计划 1b：系统桌面小组件 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 用真正的 macOS WidgetKit 小组件取代自制小窗口；快捷键与菜单栏图标改为唤起完整 App。

**Architecture:** 用 xcodegen 生成 Xcode 项目（`apps/Cre/project.yml`），三个部分：本地 Swift 包 `CreCore`（新增 library 产品）、App 目标 `Cre`、小组件扩展 `CreWidget`。App 与小组件通过 App Group 容器共享 `data.json`；小组件用 AppIntent 按钮勾选（写同一文件并刷新时间线），App 监听文件变化重新载入。

**Tech Stack:** Swift 6.4、SwiftUI、WidgetKit、AppIntents、xcodegen 2.46、免费开发团队 XZLHB3F367。

**Spec:** `docs/开发过程/specs/2026-10-03-product-form-design.md`（2.1 节）

## Global Constraints
- App Group：`XZLHB3F367.cre`（macOS 团队前缀格式，免描述文件授权）；Bundle ID：App `com.lty.cre`，小组件 `com.lty.cre.widget`。
- 数据文件：`<group container>/data.json`；首次启动从 `~/Library/Application Support/Cre/data.json` 迁移（复制后原文件改名为 `data.migrated.json`，不删除）。
- 小组件排序固定按优先级；小 2 条、中 4 条、大 6 条未完成。
- App 内文字精炼。

## Review Focus
1. App 打开时小组件勾选：App 内存中的数据不能把小组件的改动覆盖掉。→ Task W3 测试 `externalChangeIsDetected`。
2. 迁移只做一次、绝不覆盖已有的共享数据。→ Task W1 测试 `migrationNeverOverwrites`。
3. 跨过午夜小组件要换天：时间线在次日 0 点刷新。→ Task W4 测试 `timelineRefreshesAtMidnight`。

### Task W1: 共享数据位置与迁移（CreCore）
- `PlanStore.sharedURL(groupID:) -> URL?`；`migrateLegacyData(from:to:) -> Bool`（目标已存在则不动；成功后源文件改名 data.migrated.json）。
- 测试：`migrationCopiesOnce`、`migrationNeverOverwrites`、`migrationWithoutLegacyDoesNothing`。

### Task W2: 小组件内容（CreCore）
- `widgetEntries(today:data:limit:) -> (open: [AgendaEntry], folded: Int, done: [AgendaEntry], progress: Progress)`：按优先级排序，未完成截取前 `limit` 条。
- 测试：`widgetPrefersHighPriority`、`widgetCountsFolded`。

### Task W3: 外部改动检测（CreCore）
- `PlanStore.modificationDate`；`PlanStore.loadIfChanged(since:) -> PlanData?`。
- App：保存后记下修改时间；每 2 秒及激活时检查，文件被小组件改过就重新载入；保存后调用 `WidgetCenter.shared.reloadAllTimelines()`。
- 测试：`externalChangeIsDetected`、`ownSaveIsNotExternal`。

### Task W4: 时间线（CreCore）
- `nextRefresh(after: Date, calendar:) -> Date`（次日 0:00:05）。测试 `timelineRefreshesAtMidnight`。

### Task W5: 小组件扩展与 Xcode 项目
- `project.yml`、`Sources/CreWidget/`（Widget、Provider、三种尺寸视图、`ToggleTodoIntent`）、两份 entitlements。
- 小组件点击行打开 `cre://today`；App 处理该 URL 显示首页。
- 删除 `Widget/WidgetPanel.swift`；`HotKey` 与菜单栏图标改为打开主窗口。
- `build.sh` 改用 `xcodegen` + `xcodebuild -allowProvisioningUpdates`，安装到 `~/Applications/Cre.app`。
- 验证：`swift test` 全过；构建成功；`pluginkit -m -p com.apple.widgetkit-extension` 能看到 `com.lty.cre.widget`；截图小组件预览（若可）。
