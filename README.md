# dev-horcrux

Split your session's soul before it dies — auto-generate morning plans, evening session logs with git/token metrics, and quality-gated insights for Claude Code.

在 session 死亡前分裂灵魂——为 Claude Code 自动生成晨间待办、带 git/token 指标的 session 日志、以及有质量门控的工作洞察。

> **Every session you close is a death. This skill teaches you to split your soul first.**
>
> **每一次关闭终端都是一场死亡。这个 skill 教你在死前分裂灵魂。**

---

## The Problem / 问题

You spend hours in Claude Code every day. When you close the terminal, the code survives in git. Everything else dies:

- **The decisions you made** — why you chose approach A over B — gone.
- **The bugs you traced** — the 30-minute debugging path that found a one-line fix — gone.
- **The patterns you noticed** — "this is the third time symbol normalization bit me" — gone.
- **The cost you paid** — how many tokens, how much money, how much time — you have no idea.

你每天在 Claude Code 里工作数小时。关闭终端后，代码活在 git 里。其他一切都死了：做过的决策、追踪过的 bug、发现的规律、花费的 token——全部灰飞烟灭。你甚至不知道上周二做了什么，不知道那个坑三天前已经踩过一次了。

**Git remembers what you changed. Nothing remembers what you learned.**

**Git 记住了你改了什么。但没有任何东西记住你学到了什么。**

---

## The Solution / 解法

**dev-horcrux** splits your session's soul into persistent artifacts before it dies.

Every day, automatically:

| Artifact / 魂器 | What it captures / 封存了什么 |
|---|---|
| **Morning Plan** | Prioritized todos extracted from yesterday's unfinished business / 从昨天的未竟之事中提炼的分级待办 |
| **Session Log** (The Horcrux) | Every session's goal, changes, results — with auto-collected git stats, token count, and cost / 每个 session 的完整记录 + 自动采集的 git 统计、token 消耗、费用 |
| **Insights** (The Essence) | Distilled patterns, debugging lessons, architectural decisions — only on days with real substance / 提炼出的技术模式、排障经验、架构决策——只在有实质工作的日子生成 |

**The safety net**: if you close the terminal without saving, the hook detects it and prompts you to resurrect yesterday's soul on the next session start.

**安全网**：如果你直接关了终端，hook 会在下次启动时检测到，并提示你复活昨天的灵魂。

---

## The Compound Effect / 复利

**Day 1**: A structured log. Better than nothing.
**Week 1**: A weekly review with plan accuracy trends. You discover 40% of your work was unplanned.
**Month 1**: Patterns emerge — which projects eat the most tokens, which bugs keep recurring, which insights show up three times (time to automate them into a skill).

**第 1 天**：一份结构化日志。
**第 1 周**：一份周回顾，附带计划准确率。你发现 40% 的工作是计划外的。
**第 1 个月**：规律浮现——哪些项目最烧 token，哪些 bug 反复出现，哪些洞察出现了三次（是时候把它封装成 skill 了）。

**A horcrux isn't a note. It's a feedback loop. The more you create, the harder your knowledge is to kill.**

**魂器不是笔记。它是一个反馈回路。你创造得越多，你的知识就越难被杀死。**

---

## Features / 功能

### Morning Plan / 晨间计划
Auto-generates a prioritized daily plan (P0/P1/P2) from previous session's pending items, inbox, and project context. You start each day knowing exactly what matters.

自动从昨天未完成事项 + 收件箱 + 项目上下文生成分级待办。每天一开工就知道什么最重要。

### Session Log with Metrics / 带指标的 Session 日志
Creates a structured log for all sessions of the day, including:
- Per-session goal, changes, and verification results
- **Auto-collected metrics**: git diff stats, token usage, estimated cost (from session JSONL)
- **Plan review**: what was completed, deferred, or unplanned vs morning plan

结构化记录当天所有 session，自动采集 git 统计、token 消耗、费用，并与晨间计划对照回顾。

### Quality-Gated Insights / 有质量门控的洞察提炼
Not every day deserves insights. The quality gate ensures signal over noise:
- **Threshold**: only generates when ≥2 sessions, or bugfix, or architecture decision
- **Source link**: every insight traces back to a specific session
- **Confidence**: high / medium / low — low-confidence items excluded from weekly aggregation

不是每天都值得提炼洞察。质量门控确保信噪比：设有阈值、强制关联来源、标注置信度。

### Auto-Backfill / 自动复活
Forgot to log? Closed terminal in a hurry? The SessionStart hook detects missing horcruxes and injects a backfill prompt.

忘了写日志？急着关了终端？下次启动时 hook 自动检测并提示补写。

### Weekly Review / 周回顾
Aggregates daily horcruxes into a weekly summary: output stats, time allocation, plan accuracy trend, recurring insight themes, and deferred item tracking.

将每日魂器聚合为周回顾：产出统计、时间分配、计划准确率、洞察主题聚合、积压追踪。

---

## Setup / 安装

```bash
bash ~/.claude/skills/dev-horcrux/scripts/setup.sh [output-directory]
```

Default output: `~/dev-log`. The setup script / 安装脚本会：
1. Create output directories / 创建输出目录 (`dev-log/`, `insights/`, `weekly/`)
2. Write config / 写入配置 (`~/.claude/dev-horcrux.conf`)
3. Install hooks / 安装 hooks (`Stop` + `SessionStart` → `~/.claude/ft-settings.json`)

## Usage / 使用

| Trigger / 触发 | Action / 动作 |
|---|---|
| "开工" / "morning" | Generate today's plan / 生成今日待办 |
| "收工" / "wrap up" / "写日志" | Split soul: session log + insights / 灵魂分裂：生成日志 + 洞察 |
| "周回顾" / "weekly review" | Generate weekly summary / 生成周回顾 |
| Close terminal / 直接关终端 | Auto-detected, resurrect on next start / 下次自动复活 |

## File Structure / 文件结构

```
dev-horcrux/
├── SKILL.md              # Main skill instructions / 主文档
├── templates.md          # Output templates (plan/log/insights/weekly) / 模板
├── README.md             # This file / 本文件
└── scripts/
    ├── setup.sh          # One-click installation / 一键安装
    ├── stop-hook.sh      # Stop hook (timestamp + cwd) / 活跃标记
    ├── session-start-hook.sh  # Missing horcrux detection / 缺失检测
    └── collect-metrics.sh     # Git + token metrics / 指标采集
```

## Requirements / 依赖

- Claude Code (or compatible AI coding assistant)
- `jq` (for hook installation / 安装 hook 用)
- `python3` (for token extraction from session JSONL / 解析 token 数据)
- `git` (optional, for code change metrics / 可选，代码统计用)

## License

MIT
