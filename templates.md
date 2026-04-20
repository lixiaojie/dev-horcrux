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

## Skill 候选

<!-- 仅当检测到可提炼信号时出现。medium/high 置信度的候选同时写入 insights/skill-candidates.jsonl 做跨日追踪。 -->
<!-- low 置信度仅写入 insights 供浏览，不写入 JSONL。无信号时整个维度省略。 -->

### [名称 — 简洁描述这个潜在 skill 做什么]

- 信号类型: repetition | workflow | user_intent | process_improvement | cross_session
- 来源: Session N, [具体上下文]
- 输入 → 输出: [什么触发] → [产出什么]
- 步骤概要: [3-5 步]
- 置信度: high / medium / low
- 现有覆盖: [最接近的现有 skill，或"无"]
- 跨日状态: 首次发现 | 二次出现(观察中) | ≥3次(强推荐)
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

## Skill 候选聚合

> 数据源：`{DEV_HORCRUX_DIR}/insights/skill-candidates.jsonl`，取本周条目（status=pending）。

| 候选 | 出现天数 | 累计信号 | 最高置信度 | 信号类型分布 | 建议 |
|------|---------|---------|-----------|------------|------|
| [名称] | N/7 | N | high/med | repetition×2, workflow×1 | 强推荐 / 观察 / 放弃 |

**判定规则**：
- 3+ 天出现 → **强推荐**（类比 Discovery Pipeline 的 high_confidence）
- 2 天出现 → **观察**，带入下周继续追踪
- 1 天出现且置信度非 high → **放弃**（标记 status=dismissed）
- 1 天出现但置信度 high → **观察**（强信号给一周观察期）

**强推荐的候选**：直接向用户提议，附带完整的 skill spec 草案（输入/输出/步骤/触发词）。

## 遗留积压

| 来源日期 | 事项 | 已 defer 天数 |
|---|---|---|
| MM-DD | ... | N |

## 行为推断

### 观察
- 时间分配: [项目A] N% → [项目B] N%（上周: ...）
- Skill 使用: [高频 skill] N次, [未使用 skill]
- 工作模式: [观察到的模式变化]

### 建议更新
- `global-user.md` [section]: [当前] → [建议]
  - 理由: [数据支撑]

### 暂不更新
- [观察到但可能只是本周偶发的模式]

## 下周建议
- [ ] ...
```
