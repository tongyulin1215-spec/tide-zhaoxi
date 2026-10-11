# Cre · 计划 2+3：记账与总结 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans.

**Goal:** 补齐第一版：记账板块（一句话记账、表单、流水、本月收支结余、分类、统计页、日历只看过去）与总结板块（每日总结、首页"总结一下今天"、随笔/感想、历史回看）。

**Architecture:** CreCore 新增 `Ledger`（模型、一句话解析、分类猜测、月度统计、趋势）与 `Summary`（由 PlanData 生成每日总结快照）。记账存独立文件 `ledger.json`（同一 App Group 目录，与总结完全隔离）；总结报告与随笔存入 PlanData（`summaries`、`notes`，解码缺省为空）。界面沿用 A 加强版风格；统计图用 Swift Charts。

**Spec:** `docs/开发过程/specs/2026-10-03-product-form-design.md` 第 4、5、6 节（第一版范围）。

## Global Constraints
- 金额以"分"为整数存储；显示 `¥35`、`¥12,000`、`¥23.50`。
- 预设分类——支出：餐饮、交通、购物、居住、娱乐、医疗、其他；收入：工资、奖金、其他。可增删改。
- 一句话记账：默认今天、支出；`+金额` 或含"收入/工资/奖金"为收入；可带 今天/昨天/前天/M月D日；按关键词猜分类，学习同一备注上次用的分类。
- 记账日历只能选今天及以前。
- 总结不含记账数据。v1 只有"每日总结"一种；自定义总结、模板、提醒属于第二批。
- App 内文字精炼。

## Review Focus
1. 金额解析：`23.5`、`1,200`、`+12000`、文字里其他数字（"买 2 杯咖啡 30"取最后一个数为金额）。→ `ledgerAmountIsLastNumber`
2. 跨月：本月统计只算本月；趋势跨年。→ `monthTotalsOnlyThisMonth`、`trendAcrossYear`
3. 删除分类后旧流水仍显示原分类名。→ `deletingCategoryKeepsEntries`
4. 总结快照：重新生成会覆盖当天旧快照，但不动随笔。→ `regenerateKeepsNote`

## Tasks
- L1 记账模型与存储（LedgerData、LedgerStore 复用 PlanStore 的读写与损坏备份）
- L2 一句话记账解析与分类猜测
- L3 月度统计、按日分组、分类占比、近 6 个月趋势
- S1 每日总结快照、随笔、历史
- U1 记账界面（流水、表单、编辑、日历、分类管理、统计页）
- U2 总结界面（历史列表、报告、随笔；首页按钮）
- B 构建安装、截图核对、整体审查
