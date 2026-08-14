# LoopForge

中文文档 | [English](README.md)

> **一个人扛着好几个没测试、没文档的老项目，还被 TDD卡死？** 【LoopForge】一条命令给出 「AI 协作成熟度」体检报告 + 行动计划，生成 Claude Code / Codex 的结构化协作框架--让 spec 驱动开发在屎山上也能跑起来，而不是被 TDD 铁律拦死。

---

## 概述

LoopForge 的出发点很简单：一个人维护多个已上线的老项目 —— 没有 spec 文档，没有测试，一堆屎山代码。怎么推进 AI 的 loop 开发模式才能不被卡死？

最初尝试了优秀的规格驱动框架 spec-superflow，但它预设项目从零开始或已有测试基线，在实际使用中对无测试的老代码会拦截每一次改动。LoopForge 在向 spec-superflow 学习后，选择了不同的路线：用更轻量的生成器方式（shell + Python），先审计缺什么，再在不破坏现有代码的前提下重构，在严格 TDD 会卡死的环节用特征化测试与债务登记安全降级。

LoopForge 围绕工业级三层范式 **OpenSpec + Superpowers + Harness**构建，以 AI 协作优化 Skill 的形式提供两个并列版本 —— 各版本内置独立的 `scaffold.sh`（CC 版创建 `.claude/`，Codex 版创建 `.codex/`）：

| 版本 | Skill | AI 工具 | 活入口文件 | 纪律(HOW) | Loop 驱动方式 |
|:--|:--|:--|:--|:--|:--|
| Claude Code | `loopforge-cc` | Claude Code | `CLAUDE.md` | `.claude/skills/` 里的 Superpowers 技能 | `/opsx:` 斜杠命令 |
| Codex | `loopforge-codex` | Codex | `AGENTS.md` | 作为指令写进 `AGENTS.md` | `openspec` CLI + 自然语言 |

两个版本都对项目的 AI 协作结构进行**脚手架生成、审计、重构**,符合 OSH 标准。每个版本三种模式:

| 模式 | 用途 |
|:--|:--|
| **scaffold(脚手架)** | 通过 `scaffold.sh` 从零生成完整框架 |
| **audit(审计)** | 30 项检查的成熟度评分(E1–E4、O1–O8、S1–S9、H1–H8) |
| **restructure(重构)** | 将单体 `CLAUDE.md` / `AGENTS.md` 拆分为按技术栈分离的 Agent + 优化 |

**核心理念:**
- **OpenSpec** 定义方向(WHAT)
- **Superpowers** 强制纪律(HOW)
- **Harness** 编排协作(WHO)

**主要应用场景：一个人接手多个前后端分离、已上线的老项目。** Skill 集提供:

- **30 项审计**诊断每个老项目缺什么(spec?测试?Agent 分离?构建验证?)
- **重构模式**将单体 `CLAUDE.md`/`AGENTS.md` 拆分为按栈分离的 Agent,不破坏现有代码
- **Legacy 感知 TDD**(特征化测试 + 债务登记)让你安全修改无测试代码,不用卡死
- **跨栈协调**(LoopForge coordination docs + workset + OpenSpec `--goal` tags)让一人团队也能编排前后端跨仓库变更
- **SDD(子代理驱动开发)**逐任务分派 implementer/reviewer 子代理,防止同时处理多项目时上下文膨胀
- **编译门禁验证**通过 `openspec/verify.config.yaml`--本地 `/opsx:verify` 的 L1 构建检查确认每个栈编译通过后再 push;三层验证产出 `verify.md` 凭证作为归档门禁

## 定位

LoopForge 和 spec-superflow 的差异在于**场景适配**：

| 维度 | spec-superflow | LoopForge |
|:--|:--|:--|
| 技术流派 | 运行时（npm + Node.js hooks，常驻） | 生成器（`scaffold.sh` -> 静态文件，零运行时依赖） |
| 门禁强制力 | Node.js 代码 + 单元测试（可测试、稳健） | shell + Python（轻量、易读；无单测覆盖） |
| 状态机 | 8 命名状态 + 单测 | 4 相位（关键路径已对齐，精细度不及） |
| 平台覆盖 | 17 | 2（Claude Code + Codex） |
| 自包含 | ✅ 源码级融合 | ❌ 依赖 OpenSpec CLI（CC 版还依赖 Superpowers） |
| Token 效率 | 系统化基线（-60.3%） | 逐文件预算门禁 |
| 老项目迁移 | ❌ 无 | ✅ 审计 -> 重构 -> 特征化测试 -> 债务登记 |
| 跨栈编排 | ❌ 无 | ✅ per-stack agents + coordination docs |
| 编译门禁验证 | ❌ 无 | ✅ verify.config L1 build 检查 + verify.md |

**spec-superflow（通用方案）：** 全新项目、多人协作、多平台工具链、已有测试基线的项目，以及任何需要严格"规划→执行"一致性的场合。它的工程化质量 —— 类型化 Schema、有单测的门禁、可独立测试的 skill —— 确实出色，我们无意声称能比肩。

**LoopForge（个人工具）：** 一人团队接手无文档、无测试的老代码库——即上方概述中列出的六项能力。spec-superflow 的 TDD“铁律”会*正确地*在一个无测试的 5 年老项目上拦截真实代码修改——LoopForge 增加了一条特征化测试 + 债务登记的降级路径，让你能安全推进而不至于卡死。

> spec-superflow 是打磨成熟、通用性强的方案；LoopForge 是向它学习后、针对特定场景的个人工具。如果你的项目已经规范化，请用 spec-superflow；如果你一个人在抢救老代码，LoopForge 正为此而生。

## 安装

### Claude Code -- `loopforge-cc`

把 skill 复制进项目(Claude Code 从 `.claude/skills/` 自动加载):

```bash
cp -r skills/loopforge-cc /path/to/project/.claude/skills/loopforge-cc
```

通过 `/loopforge-cc` 斜杠命令触发,或直接用自然语言描述任务。

### Codex -- `loopforge-codex`

全局安装进 Codex 的 skills 目录,然后重启 Codex:

```bash
cp -R skills/loopforge-codex ~/.codex/skills/loopforge-codex
```

`scaffold.sh` 已是 skill 目录内的实体文件,普通拷贝即可。重启后 skill 按 `description` 自动触发,也可用 `$loopforge-codex` 显式调用;`openspec init --tools codex` 还会为 Codex 生成 `/opsx:` 斜杠命令(`/opsx:propose`、`/opsx:apply`、`/opsx:archive`、`/opsx:explore`、`/opsx:sync`)。

> 若你之前把旧版拷进了 `~/.codex/skills/loop-eng`,先删掉以免两个 skill 抢同一意图:`rm -rf ~/.codex/skills/loop-eng`。

## 脚手架生成新项目

每个版本有自己的 `scaffold.sh`。CC 版创建 `.claude/`;Codex 版创建 `.codex/`。两者都生成 `CLAUDE.md` + `AGENTS.md` 镜像:

```bash
# Claude Code(创建 .claude/)
./skills/loopforge-cc/scaffold.sh myapp

# Codex(创建 .codex/)
./skills/loopforge-codex/scaffold.sh myapp --tools codex

# 三栈(web + mobile)
./skills/loopforge-codex/scaffold.sh myapp --stacks backend,frontend,frontend-mobile --tools codex

# 自定义目标目录 + 跳过 init
./skills/loopforge-cc/scaffold.sh myapp --dir ./projects/myapp --no-init
```

选项:`--stacks`、`--dir`、`--backend-dir`、`--frontend-dir`、`--mobile-dir`、`--tools`(CC 版默认 `claude`,Codex 版默认 `codex`;仅影响 `openspec init`)、`--no-init`。

### `scaffold.sh` CLI 子命令

除默认的脚手架生成外,`scaffold.sh` 还提供九个子命令(可直接运行,或让 AI 代跑):

| 子命令 | 用途 |
|:--|:--|
| `list [opts]` | 预览会生成哪些文件,不落地写入 |
| `check [project]` | 自检(环境+脚本)+ LoopForge 合规审计;不带参数仅自检 |
| `tokens [project]` | 自动加载文件的 token 审计--逐文件 token 数 + CJK 占比(O7 开销) |
| `validate <change-dir>` | 校验变更的产物结构(proposal/spec/design/tasks) |
| `changes [project]` | 列出所有变更及其相位/状态 |
| `doctor [project]` | 健康检查:依赖、脚手架、门禁、verify 配置 |
| `version` | 打印 LoopForge 版本 + 环境 |
| `contract [--force] <change-dir>` | 从规划产物自动生成 `execution-contract.md` |
| `restructure [project]` | 分析单体入口文件,规划按技术栈拆分 |

> `check` 跑可自动判定的子集(24 项 = 3 环境自检 + 21 结构合规),输出 PASS/PARTIAL/FAIL + 成熟度分;完整 30 项语义审计请让 skill 进 audit 模式。`tokens` 逐文件测量 O7 的 CJK 开销(`CJK_THRESHOLD` 环境变量,默认 10%)。

### `scaffold.sh` 生成内容

```
myapp/
├── CLAUDE.md                 ← 导航中心(≤120 行)-- Claude Code 入口
├── AGENTS.md                 ← Codex 导航中心(与 CLAUDE.md 镜像)
├── openspec/                 ← WHAT:README、project.md、specs/{api,data,errors}、changes/_template、archive
│   ├── sdd/                  ← SDD:implementer-prompt.md、reviewer-prompt.md、progress.md
│   ├── guard.sh              ← 相位门禁:proposing->applying->verifying->archived
│   ├── ensure-branch.sh      ← Worktree 隔离(legacy git 容错)
│   ├── ensure-contract-fresh.sh ← 执行契约新鲜度检查
│   ├── loop-state.yaml       ← 相位状态机(phase/change/retry_count/execution_mode)
│   └── verify.config.yaml    ← 各栈 build/test 命令(供 /opsx:verify L1/L3 用)
├── .claude/  (CC 版)         ← HOW:settings.json(权限+钩子)、rules/、agents/{reviewer,coordinator,implementer}
├── .codex/   (Codex 版)      ← HOW:skills/openspec-*(propose/apply/verify/archive + trigger 注入)
├── backend/{CLAUDE,AGENTS}.md   ← Backend Agent(Claude Code / Codex)
└── frontend-web/{CLAUDE,AGENTS}.md ← Frontend Agent(Claude Code / Codex)
```

`CLAUDE.md` 与 `AGENTS.md` 总是一起生成(内容镜像),同一项目可在两种工具中使用。CC 版创建 `.claude/`;Codex 版创建 `.codex/` -- 各自只创建自己工具的目录,不交叉创建。非破坏性:已存在的文件会被跳过,可安全重跑。

### 需另外安装的组件(按版本)

**两者皆需:** OpenSpec CLI -- `npm i -g @fission-ai/openspec@latest`(脚手架会自动跑 `openspec init`)。

**仅 Claude Code:** Superpowers 技能集(`brainstorm`、`writing-plans`、`executing-plans`、`code-review`、`verification-before-completion`)与 `frontend-design`(仅前端项目)。它们位于 `.claude/skills/`,由 `/opsx:` 命令自动触发。

**Codex:** 无需额外安装 -- Superpowers 五步纪律已作为指令写进生成的 `AGENTS.md`,Loop 由 `openspec` CLI 驱动。

随后填写 `openspec/project.md`、`openspec/specs/*` 及各栈 `CLAUDE.md` / `AGENTS.md` 中的 `[方括号]` 占位符。

## 审计现有项目

触发 skill(如"审计我的项目结构")。它会执行 Phase 0(环境 E1–E4)+ Phase 1(30 项检查),输出诊断表、成熟度等级、Top 问题与行动计划。

> Codex 注意:`scaffold.sh check` 是双源的 -- 先查 `AGENTS.md`,再查 `.claude/` 作为回退。纯 Codex 项目(无 `.claude/`)通过 `AGENTS.md` 通过 E3/E4/S4/S5/S6/S8/S8b/H9,不会误报 PARTIAL/FAIL。

### 成熟度评分

```
环境 = E/4 · OpenSpec = O/8 · Superpowers = S/9 · Harness = H/8
总体 = (E + O + S + H) / 29
```

| 得分 | 等级 |
|:--|:--|
| < 33% | 基础建设前 |
| 33–66% | 基础级 |
| 66–90% | 质量级 |
| > 90% | 工业级 |

## 重构单体项目

当单个 `CLAUDE.md`(Claude)或 `AGENTS.md`(Codex)混合多个技术栈,或审计分数偏低时:触发 skill 把它拆分为按栈分离的 Agent 文件,根文件重写为导航中心,并按 Phase 5 顺序执行重构。

## 许可证

见 [LICENSE](LICENSE)。

> 对话剧本(操作手册):Claude Code 版 [USAGE-PLAYBOOK.md](skills/loopforge-cc/USAGE-PLAYBOOK.md) · Codex 版 [USAGE-PLAYBOOK-CODEX.md](skills/loopforge-codex/USAGE-PLAYBOOK-CODEX.md)
