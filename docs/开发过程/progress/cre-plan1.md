# 计划 1 进度（断点续做用）

- 计划：`docs/开发过程/plans/2026-10-03-cre-todo-core.md`
- 产品文档：`docs/开发过程/specs/2026-10-03-product-form-design.md`
- 执行方式：Native（同一会话按顺序做完 13 步，最后整体审查）
- 代码目录：`apps/Cre`（在 worktree `skill-搜索` 分支上）

## 续做方法

1. 读本文件"当前状态"和"已完成"。
2. `git log --oneline` 核对最后一次提交与本文件一致。
3. `cd apps/Cre && swift test` 确认已完成部分全部通过。
4. 从"下一步"开始；做完一步：测试通过 → 提交 → 更新本文件（追加一行到"已完成"，改"当前状态"和"下一步"）→ 再提交本文件。

## 当前状态

Mac 版完整产品完成：第一版 + 第二批 + 连续打卡。162 个测试通过，三轮独立审查的重要问题均已修复，已安装 ~/Applications/Planner.app。代码在 skill-搜索 分支，暂不合并。iPhone 端用户决定暂不做。

## 下一步

用户试用完整 Mac 版；10 月 11 日确认签名到期影响；之后按反馈迭代。

## 已完成

| Task | 提交 | 备注 |
|---|---|---|
| 1 | c15ed36 | feat(cre): package skeleton and DayKey |
| 2 | 42edec9 | feat(cre): domain models |
| 3 | ced6379 | feat(cre): PlanData mutations and JSON store |
| 4 | d7aa179 | feat(cre): agenda for a day |
| 5 | 75e5d9f | feat(cre): completion, backfill, whole-row check |
| 6 | a7185cd | feat(cre): day plans, rotation and ongoing detail |
| 7 | 8df16de | feat(cre): Friday triage |
| 8 | cc7be82 | feat(cre): one-line time parsing |
| 9 | e569eea | feat(cre): app shell, sidebar, app state |
| 10a | c53045b | feat(cre): priority and sort modes |
| 10b | d04ea78 | feat(cre): group kinds, anchors, cycle period and gap |
| 10 | 7b26ac9 | feat(cre): day view per approved sketch |
| 11 | 98a998b | feat(cre): planning section with group kinds |
| 12 | 5bb47ee | feat(cre): widget panel, pin, global hotkey |
| 13 | 09f3eec | feat(cre): Friday triage sheet and packaging |

## 偏离计划的决定

- 模型 `Group` 改名为 `TodoGroup`（避免与 SwiftUI.Group 冲突）。
- swift-tools-version 用 5.10（Swift 5 语言模式），与 CreTodo 原型一致。
- PlanData 解码对每个字段用默认值，新增字段不破坏旧文件。
- 详细执行记录（ledger）在 `.superpowers/sdd/2026-10-03-cre-todo-core/progress.md`（不入库）。
