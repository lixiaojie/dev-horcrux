# Dev Journal Templates

## Morning Plan Template

```markdown
---
date: YYYY-MM-DD
type: daily-plan
tags: [daily-plan]
---

# YYYY-MM-DD 今日待办

## 优先事项（P0 — 今天必须完成）
- [ ] ...

## 计划事项（P1 — 今天争取完成）
- [ ] ...

## 待跟进（P2 — 不紧急但需要推进）
- [ ] ...

## 上下文备注
> 来自 last-session / inbox 的关键背景
```

## Session Log Template

```markdown
---
date: YYYY-MM-DD
type: dev-log
tags: [dev-log, project-a, project-b]
---

# YYYY-MM-DD 开发日志

## Metrics
sessions: N
conversation_rounds: N
tokens: {input: N, output: N, total: N}
estimated_cost: $N.NN
code_changes:
  files_modified: N
  lines_added: N
  lines_removed: N
  commits: N
tests: {total: N, passed: N, failed: N}
plan_review:
  p0_completed: "N/N"
  p1_completed: "N/N"
  unplanned_items: N

## Session 总览

| # | 项目 | 主题 | 状态 |
|---|---|---|---|
| 1 | project-a | ... | done |

---

## Session 1: project-a — 主题

**目标**: ...

**变更**:
- ...

**验证**:
- ...

---

## 今日关键成果

1. ...

## 待跟进

- [ ] ...

---

> 关联记录: [[project-index]] | [[project-a]]
```

Note: `[[]]` wikilinks only when `WIKILINKS=true` in config. Otherwise use plain text.

## Insights Template

```markdown
---
date: YYYY-MM-DD
type: daily-insights
tags: [insights, ...]
---

# YYYY-MM-DD 工作洞察

## 技术模式

### [Title]
[Description of the pattern discovered]

**模式**: ...
**反模式**: ...

- source: Session N, [specific context]
- confidence: high

## 排障经验

### [Title]
[Root cause → fix path, especially non-intuitive ones]

**诊断方法**: ...

- source: Session N, [bug ID or description]
- confidence: high

## 工具 / API 发现

### [Title]
[New tool behavior, API boundaries, limitations]

- source: Session N
- confidence: medium

## 决策记录

### [Title]
[What was decided, why, what alternatives were rejected]

**决策依据**: ...

- source: Session N
- confidence: high

## 流程改进

### [Title]
[Efficiency improvement or process change suggestion]

**待封装**: ... (if applicable)

- source: Session N
- confidence: medium
```

Only include dimensions that have real content. Empty dimensions are omitted entirely.

## Weekly Review Template

```markdown
---
date: YYYY-MM-DD
type: weekly-review
week: YYYY-WNN
tags: [weekly-review]
---

# YYYY-WNN 周回顾 (MM-DD ~ MM-DD)

## 产出总览

| 指标 | 本周 | 上周 | 变化 |
|---|---|---|---|
| Sessions | N | N | +N |
| Commits | N | N | |
| Tests (net new) | N | N | |
| Lines +/- | +N/-N | | |
| Token 消耗 | N M | N M | |
| 估算成本 | $N | $N | |

## 时间分配

| 项目 | Sessions | 占比 |
|---|---|---|
| project-a | N | N% |

## 计划准确率

| 日期 | P0 完成 | P1 完成 | 计划外 |
|---|---|---|---|
| Mon | 2/2 | 1/3 | +1 |

平均: P0 N%, P1 N%, 计划外 N 项/天

## 洞察聚合

### 本周重复出现的主题
- [theme] — 出现 N 次，见 [dates]

### 晋升候选（多次出现 + high confidence）
- [insight] → 建议写入 global-memory / 封装 skill

## 遗留积压

| 来源日期 | 事项 | 已 defer 天数 |
|---|---|---|
| MM-DD | ... | N |

## 下周建议
- [ ] ...
```
