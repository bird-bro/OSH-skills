# loopforge-codex 对话剧本 · Codex 版操作手册

> 本手册以「**用户说 → AI 做**」的对话形式,说明在 Codex 中如何用 `loopforge-codex` skill 接入 Loop 工程（首次接入 / 老项目重构）(OpenSpec + Superpowers + Harness)。
>
> 它是 [USAGE-PLAYBOOK.md](../loopforge-cc/USAGE-PLAYBOOK.md)(Claude Code 版)的 Codex 对应版。两者骨架一致,差异在于入口文件与命令形态:`openspec init --tools codex` 为 Codex 生成项目内 `.codex/skills/openspec-*` 技能,用 `$skill-name` 调用(如 `$openspec-propose` / `$openspec-apply-change` / `$openspec-archive-change`)+ `openspec` CLI + 自然语言;Superpowers 纪律则写进 `AGENTS.md` 作为指令。
>
> 关键心法不变:**OpenSpec 定方向(WHAT)、Superpowers 强纪律(HOW)、Harness 编协作(WHO)**;每个功能走闭环 `propose → apply → verify → archive`(页面/UI 开发时,apply 前先 `design` HTML 原型),这就是 "Loop"。
>
> 剧本约定:**用户** = 看本手册并下指令的人;**AI** = 执行指令的 Codex(即 loopforge-codex skill 的承载者)。

---

## Codex 与 Claude 版差异速查

| 维度 | Claude Code 版 | Codex 版(本手册) |
|:--|:--|:--|
| 触发 skill | `/loopforge-cc` 斜杠命令 或 自然语言 | `$loopforge-codex` 显式调用 或 按 `description` 自动触发 |
| 入口文件 | `CLAUDE.md` | `AGENTS.md`(`CLAUDE.md` 是镜像,Codex 不读) |
| 提案/应用/验证/归档 | `/opsx:propose` / `apply` / `verify` / `archive` 斜杠命令 | 用 `$openspec-propose` / `$openspec-apply-change` / `$openspec-verify` / `$openspec-archive-change`(`$` 技能)或 `openspec` CLI |
| 纪律(Superpowers) | `.claude/skills/` 里五个技能,由斜杠命令自动触发 | 纪律写进 `AGENTS.md` 作为指令(不依赖插件),AI 按上下文遵循 |
| 会话续接 | `/resume` `/branch` `/rewind` | Codex 自身 goal/plan + 自然对话续接 |
| openspec init | `--tools claude`(默认) | `--tools codex`(默认) |
| 工具目录 | `.claude/`(rules / skills / agents / settings) | `.codex/`(skills / openspec-*) |

> scaffold.sh **总会**同时生成 `CLAUDE.md` 与 `AGENTS.md`(内容镜像)。纯 Codex 项目里 `CLAUDE.md` 是死文件,可留着备用或删;编辑只动 `AGENTS.md`。
>
> Codex 版 scaffold **只创建 `.codex/`**(openspec 技能 + verify skill + trigger 注入),不创建 `.claude/` 目录。两版 scaffold 各管各的工具目录,不交叉创建。
>
> `openspec init` 不含 verify——loopforge 脚手架额外创建 `$openspec-verify` 技能(三层验证)并注入到 apply/archive 的触发链,使闭环 `propose → apply → verify → archive` 自动衔接。

---

## 三种模式速查

| 用户想做的事 | CLI 命令 | 或对 AI 说 |
|:--|:--|:--|
| 预览会生成哪些文件 | `./scaffold.sh list` | "预览脚手架会生成什么" |
| 生成完整框架(Codex 入口) | `./scaffold.sh myapp --tools codex` | "给 myapp 搭 loop 脚手架,Codex 优先" |
| 自检环境 | `./scaffold.sh check` | "自检 loopforge-codex 环境" |
| 审计项目合规度 | `./scaffold.sh check ./myapp` | "审计 ./myapp 的 OSH 合规度" |
| 拆分单体入口文件 | skill restructure 模式 | "把 AGENTS.md 拆成按栈的 agent" |
| 全量 30 项审计 | skill audit 模式 | "对项目做完整 30 项审计" |

> **如何触发:** 把 `loopforge-codex/` 放进 `~/.codex/skills/loopforge-codex/` 后重启 Codex,skill 会按 `description` 自动激活。也可用 `$loopforge-codex` 显式调用,或直接说"用 loopforge-codex 给 X 搭脚手架",AI 会选对应模式或 CLI 执行。

---

## 场景一:已有代码项目接入 Loop 工程（首次接入 / 重构）

> 项目已有代码目录（如 ops_sev/、ops_web/、ops_wechat/），分两种起点：
> - **起点 A（最常见）**：还没有 AGENTS.md、openspec/ 或 .codex/ -> 从 scaffold 生成框架
> - **起点 B**：已有单体 AGENTS.md（或 CLAUDE.md，之前手写过）-> 审计现状 + restructure 拆分
> AI 通常一次性完成对话 1-3，无需用户分步指令。

### 对话 1 · 判断起点并生成/重构框架

**起点 A：无 AGENTS.md -> 生成框架**

**用户**:
`$loopforge-codex`
>
> 项目在 `./myproject`，后端目录 `ops_sev`（Java/Spring），前端目录 `ops_web`（Vue3），移动端目录 `ops_wechat`（微信小程序），没有 AGENTS.md 也没有 openspec/，帮我接入 loop 工程。

**AI**:
1. **确认环境与目录**：检查 openspec/node 版本，`ls` 项目根确认实际目录和栈数量。
2. **读取项目文件**：读 `pom.xml`/`package.json` 确认技术栈（框架版本、构建工具、测试框架）。
3. **构建命令**（根据实际栈数量动态决定 flag）：

| 目录 | 栈类型 | flag |
|:--|:--|:--|
| `ops_sev` | backend | `--backend-dir ops_sev` |
| `ops_web` | frontend | `--frontend-dir ops_web` |
| `ops_wechat` | frontend-mobile | `--mobile-dir ops_wechat` |

```bash
cd ./myproject
./scaffold.sh myproject --dir . --stacks backend,frontend,frontend-mobile \
  --backend-dir ops_sev --frontend-dir ops_web --mobile-dir ops_wechat --tools codex
```
- `--dir .`：在当前目录原地生成，不创建嵌套子目录
- `--stacks` 和 `--*-dir`：**根据项目实际栈数量决定**。只有后端就只传 `--backend-dir`；有移动端才加 `--mobile-dir`
- 自动跑 `openspec init --tools codex`，生成 `openspec/`、`.codex/skills/`、根 `AGENTS.md`（含 `[fill]` 占位符）、各栈 `AGENTS.md` + `CLAUDE.md`

4. **创建 workset**（多栈项目）：`openspec workset create <kebab-case-name> --member backend=./ops_sev --member frontend=./ops_web --member frontend-mobile=./ops_wechat`（项目名自动转 kebab-case）。
5. **自动安装 Superpowers 技能**：从用户级插件缓存（`~/.claude/plugins/cache/.../superpowers/`）复制 brainstorming / writing-plans / executing-plans / requesting-code-review / verification-before-completion / test-driven-development / systematic-debugging 到 `.claude/skills/`。若插件未安装则提示用户安装。

> 如果项目已有 `openspec/`，加 `--no-init` 跳过初始化。
> 详细的参数说明和排错见下方「scaffold.sh 参数与排错指南」。

**起点 B：有单体 AGENTS.md -> 审计 + 拆分**

**用户**:
> 老项目在 `./legacy`，有个单体 `AGENTS.md`，想接入 loop 工程。先看现状。

**AI**:
1. **审计现状**：① `./scaffold.sh check`（环境自检）；② `./scaffold.sh check ./legacy`（结构合规度）；③ 进 skill audit 模式做全量 30 项审计。产出：诊断表 + 成熟度 + Top 问题 + 行动计划（按 Phase 5 顺序）。
2. **拆分单体入口**（skill **restructure** 模式）：
   - 读单体 `AGENTS.md`，按栈分类段落（Java 段落->backend、Vue 段落->frontend、API 路径->`openspec/specs/`、构建命令按工具分流）；
   - 跟用户确认技术栈与目录映射；
   - 生成各栈 `AGENTS.md`（含 Role / `NEVER` 跨域禁令 / Superpowers 五步纪律 / TDD / Build）；
   - 重写根 `AGENTS.md` 为导航中心（≤120 行）；
   - 删重复、校验无内容丢失、无死文件。

> **`check` 是 Codex-aware 的**：E3 探测根 `AGENTS.md`、E4 探测前端 `AGENTS.md` 的设计指引、S6 探测 `AGENTS.md` 里的 sandbox/approval + 危险命令拦截关键词；S4/S5/S8 同理--`.claude/` 路径（`settings.json`/`rules`/`skills`/`agents`）只是 Claude 的可选加分项。纯 Codex 项目只要 `AGENTS.md` 写到位，这些项都能 PASS，不存在 `.claude` 误报，分数如实看即可。
> 纯 Codex：以 `AGENTS.md` 为主拆分对象；若同时用 Claude，再镜像出对应 `CLAUDE.md`。

### 对话 2 · 填充内容 + 为已有代码补 spec（AI 主动执行）

> AI 在框架生成/重构完成后主动执行，无需用户单独指令。

**AI**:
1. **读取真实技术栈**：从 `pom.xml`（Java 版本、Spring Boot 版本、模块列表、数据库驱动）、`package.json`（框架、UI 库、构建/测试命令）提取信息。
2. **批量填充占位符**：用脚本替换 `openspec/project.md`、各栈 `AGENTS.md` + `CLAUDE.md`（两者须镜像一致）、根 `AGENTS.md` 中的 `[fill]`、`[e.g. ...]`、`[one-line business description]` 等占位符。
3. **修正 verify.config.yaml**：根据实际技术栈调整 build/test 命令。例如：
   - ops_wechat 有 vitest -> `test: pnpm test:run`（非 `null`）
   - ops_wechat 构建目标是微信小程序 -> `build: pnpm build:mp`（非 `pnpm build`）
4. **修正 workset 名称**：根 `AGENTS.md` 中的 `openspec workset open` 命令使用 kebab-case 项目名。
5. **为已有代码反向补 spec**：读现有模块代码与接口（如 user 模块），抽取为 `openspec/specs/api/spec.md`、`data/spec.md`、`errors/spec.md`（补 WHEN/THEN 场景），让 spec 成为前后端共同真相。后续改动一律走 `openspec new change` 增量，不再裸改代码。

### 对话 3 · 审计校验（AI 主动执行）

> AI 在填充完成后主动执行审计。

**AI**:
1. 跑 `./scaffold.sh check .`（快速审计）。
2. 跑 `./scaffold.sh tokens .`（token 审计：确认自动加载文件全英文、单文件 ≤3000 tokens）。
3. 输出已知问题清单 + 优先级建议，例如：
   - Superpowers 纪律已写入 AGENTS.md 但技能未安装 -> brainstorm/plan/review 靠 AI 遵循指令
   - 项目根非 git 仓库 -> worktree 隔离不可用
   - specs/*.md 为模板骨架 -> 随首个 `$openspec-propose` 逐步填充
4. **起点 B 额外**：重构后重跑 `./scaffold.sh check ./legacy` + 全量审计，对比前后成熟度，确认：无重复、无死文件、各 agent 含必备 8 段、跨域禁令显式、根 `AGENTS.md` ≤120 行。

### 进入 Loop 前

接入（生成/重构 + 填充 + 补 spec + 审计）完成后：
1. 先做「框架盘点」-- 盘点已有 common/framework 等横切约定（统一返回、日志切面、共有方法、错误码），写进 `openspec/specs/` 与各栈 `AGENTS.md`。
2. 再进「场景二：日常 Loop 循环」开始第一个功能（`openspec new change` -> propose -> apply -> verify -> archive）。

## scaffold.sh 参数与排错指南

> 上方场景中的 scaffold 命令完整参数说明与常见问题排查。首次接入和老项目重构都会用到。

### 命令格式

```bash
./scaffold.sh <项目名> [选项]
```

**项目名是必填位置参数**，即使使用了 `--dir .`。用于默认目录名、context-store 命名、`@@PROJECT_NAME@@` 占位符替换。

### 全部参数

| 参数 | 默认值 | 说明 |
|:--|:--|:--|
| `<项目名>` | （必填）| 项目名称 |
| `--dir <路径>` | `./<项目名>` | 目标目录。**`--dir .` = 在当前目录原地生成** |
| `--stacks <列表>` | `backend,frontend` | 栈类型：`backend`、`frontend`、`frontend-mobile` |
| `--backend-dir <名>` | `backend` | 后端目录名。**必须与真实目录名一致** |
| `--frontend-dir <名>` | `frontend-web` | 前端 Web 目录名。**必须与真实目录名一致** |
| `--mobile-dir <名>` | `frontend-mobile` | 移动端目录名 |
| `--tools <列表>` | `codex` | openspec init 工具类型 |
| `--no-init` | （关闭）| 跳过 `openspec init`，仅生成 LoopForge 增强层 |

### 选对命令：scaffold vs restructure

| 场景 | 命令 | 原因 |
|:--|:--|:--|
| 已有代码 + 无 AGENTS.md | `scaffold <name> --dir . --backend-dir <真实名> --frontend-dir <真实名>` | 原地生成框架，AGENTS.md 用模板（含 `[fill]` 占位） |
| 已有代码 + 已有 AGENTS.md | `restructure <dir>` 先分析 | scaffold 会创建占位目录；restructure 只分析不写 |
| 已有代码 + 无 openspec/ | `scaffold <name> --dir . --backend-dir <真实名> --frontend-dir <真实名>` | 原地生成，不创建嵌套子目录 |
| 已有 openspec/ + 缺 .codex/ | `scaffold <name> --dir . --no-init` | write_if_absent 跳过已有，只补缺失 |

### 关键用法：在已有项目根目录原地生成

```bash
cd /path/to/myproject
./scaffold.sh myproject --dir . --stacks <实际栈类型> --backend-dir <后端目录名> --frontend-dir <前端目录名> --tools codex
# 有移动端则追加: --mobile-dir <移动端目录名>
```

要点：
- **`--dir .`**：不加则创建 `./myproject/` 子目录（嵌套），把框架文件放到子目录而非项目根
- **`--stacks` 和 `--*-dir`**：根据项目实际目录确认。不加 `--*-dir` 则用默认名 `backend`/`frontend-web`，会创建空占位目录。**先 `ls` 看项目有哪些目录，再决定传几个 flag**
- **`--no-init`**：已有 openspec/ 时跳过 init，避免重复初始化

### 生成后的检查清单

| 检查项 | 命令 | 预期 |
|:--|:--|:--|
| 无多余占位目录 | `ls` | 不应有 `backend/`、`frontend-web/` 等不匹配的空目录 |
| verify.config.yaml 栈名 | `cat openspec/verify.config.yaml` | 与 `--backend-dir`/`--frontend-dir` 一致 |
| verify.config.yaml 命令 | 同上 | build/test 命令符合实际技术栈 |
| 已有文件未被覆盖 | `head AGENTS.md` | 内容应与原来一致 |
| 审计通过 | `./scaffold.sh check .` | ≥ 90% 工业级 |

### 常见问题排查

#### Q1: `Error: project name required`

```
# ❌ 只传了 --dir .，缺项目名
./scaffold.sh --dir .

# ✅ 项目名是必填位置参数
./scaffold.sh OPS --dir .
```

#### Q2: 创建了嵌套子目录（`OPS/OPS/`）

在项目目录内运行 `scaffold.sh OPS`，默认目标 `./OPS` 指向子目录而非当前目录。

```
# ❌ 在 /project/OPS/ 内运行 -> 创建 /project/OPS/OPS/
cd /project/OPS && ./scaffold.sh OPS

# ✅ 用 --dir . 指向当前目录
cd /project/OPS && ./scaffold.sh OPS --dir . --backend-dir ops_sev --frontend-dir ops_web

# ✅ 或从父目录运行
cd /project && ./scaffold.sh OPS --dir ./OPS --backend-dir ops_sev --frontend-dir ops_web
```

#### Q3: 生成了 `backend/` 和 `frontend-web/` 空占位目录

没传 `--backend-dir`/`--frontend-dir`，用了默认目录名。

```
# ❌ 默认名 backend/frontend-web 不匹配真实目录
./scaffold.sh OPS --dir .

# ✅ 传入真实目录名
./scaffold.sh OPS --dir . --backend-dir ops_sev --frontend-dir ops_web

# 🔧 已生成的占位目录直接删除
rm -rf backend frontend-web
```

#### Q4: `warn: context-store setup failed` / `warn: workspace setup failed`

openspec 1.6.0 移除了 `context-store` 和 `workspace` 子命令。**可安全忽略**——不影响 openspec/、.codex/、verify.config.yaml 的生成。多栈协调改用 openspec 1.6.0 的 `workset` 替代（见 SKILL.md "Cross-Stack Feature"）。

#### Q5: 已有 AGENTS.md 会被覆盖吗？

**不会**。scaffold 使用 `write_if_absent`，已存在的文件输出 `skip (exists)` 并跳过，只有不存在的文件才会被创建。

#### Q6: 第 4 个栈（如 WeChat 小程序）没被覆盖

scaffold 最多支持 3 种栈类型（`backend`、`frontend`、`frontend-mobile`）。第 4 个栈需手动处理：
1. 在 `openspec/verify.config.yaml` 补该栈的 build/test 配置
2. 如需 agent 文件，从已有栈的 AGENTS.md 复制改造

#### Q7: verify.config.yaml 的 build/test 命令不对

scaffold 按栈类型给默认值（backend → `mvn compile -q`，frontend → `pnpm build`）。如果技术栈不同（如 Python/Go 后端、npm 前端），**生成后手动编辑** `openspec/verify.config.yaml`。

---

## 框架盘点:进入 Loop 循环前的项目分析(老项目必做)

> 时机:项目接入(场景一)完成后、**第一个功能(进入 propose -> apply -> verify -> archive 循环)之前**。
> 目的:把现有项目的框架约定"盘点"进 `openspec/specs/` 与各栈 `AGENTS.md`,让后续每个功能的 spec 都**对齐现状**,避免 AI 重复造轮子或违反既有约定(如自造返回封装、绕过统一日志)。
> 这个盘点**不产生代码变更**,只产出 spec / 约定文档。

### 为什么要先盘点

直接让 AI 做第一个功能,它看不到项目里已有的 `common`/`framework` 基础设施,容易:

- 自造一个 `Result` 返回封装,而项目早有统一的 `ApiResponse<T>`;
- 用 `print`/`System.out` 打日志,而项目有统一的 AOP 日志切面;
- 重复写工具方法,而 `common/utils` 里已有;
- 错误码各搞各的,而项目有统一的错误码表。

先盘点 -> 这些约定进 spec -> AI 做功能时读 spec 就会遵守。

### 对话 · 框架盘点

**用户**:
> 开始做功能前,先盘点现有项目框架,把约定写进 openspec/specs/ 和各栈 AGENTS.md。后台重点看 common、framework 这些模块。

**AI**:
1. **扫结构**:读后端模块划分(`common`、`framework`、`web`、`service`...),列出模块及职责。
2. **抽横切约定**(重点):
   - **统一返回封装**:`ApiResponse<T>` / `Result<T>` 的结构、成功/失败约定、分页包装 -> `openspec/specs/errors/spec.md`(统一响应 + 错误码体系)
   - **日志切面**:AOP 日志注解(如 `@Log`)、日志级别/格式约定、链路追踪 ID -> 各栈 `AGENTS.md` Coding Standards
   - **共有方法/工具类**:`common/utils`、基类(`BaseController`/`BaseService`/`BaseEntity`)、通用 Mapper -> 各栈 `AGENTS.md`(标注"用现有 X,不要自造")
   - **异常处理**:全局异常处理器、业务异常基类、错误码枚举 -> `openspec/specs/errors/spec.md`
   - **鉴权/拦截器**:登录校验、权限注解、拦截器链 -> `openspec/specs/api/spec.md`
   - **数据访问约定**:Mapper/Repository 基类、分页插件、ORM 约定 -> `openspec/specs/data/spec.md`
3. **写文档**(落到对应 md):

   | 盘点项 | 写入位置 |
   |:--|:--|
   | 模块图 / 架构 | `openspec/project.md` |
   | 统一返回 + 错误码 | `openspec/specs/errors/spec.md` |
   | 接口约定 / 鉴权 | `openspec/specs/api/spec.md` |
   | 数据访问约定 | `openspec/specs/data/spec.md` |
   | 共有方法 / 日志切面 / 基类 | 各栈 `AGENTS.md` 的 Coding Standards |
   | 跨切面约定汇总(可选) | `openspec/specs/conventions/spec.md`(新建) |

4. **报告**:产出"框架盘点表"(模块 -> 职责 -> 约定 -> 对应 md),请用户校对。
5. **门禁**:用户确认盘点准确后,才进入第一个功能的 `openspec new change <name>`。

> 关键纪律:盘点只写 spec/约定,**不动代码**。后续功能开发时,AI 读这些 spec 就会复用 `common` 工具、走统一返回、挂 AOP 日志,而不是另起炉灶。
> 本 skill 面向"已有代码、但缺 CLAUDE.md/AGENTS.md"的项目(见场景一),故框架盘点在接入完成后、第一个功能前必做,不存在"从零搭建"可跳过的场景。

## 场景二:日常 Loop 循环

每个功能都走闭环。Codex 版用 `$` 技能(`$openspec-propose`/`$openspec-apply-change`/`$openspec-verify`/`$openspec-archive-change`)或 `openspec` CLI 驱动,纪律由 AGENTS.md 承载:

| 阶段 | 用户输入 | AI 做 |
|:--|:--|:--|
| 提案 | "提一个 X 变更" | 澄清需求 → `openspec new change <name>` → 填 proposal + spec(WHEN/THEN) |
| 设计 | "页面要做成什么样" | (仅页面/UI 开发,apply 前)先做 HTML 原型,两条路:① 纯代码优先 — 直接写 HTML/CSS(或 React+Tailwind/shadcn)→ `browser` 渲染 → `screenshot` 自检(简单页/快速原型最快);② `frontend-app-builder` skill — Codex 当资深前端设计师 → Image Gen 出视觉概念稿 → 用户确认 → 忠实实现成代码 → `browser` + `view_image` 对比到 10/10 还原(全程不碰 Figma)。主力栈:`build-web-apps`(`frontend-app-builder` + `shadcn-best-practices`)+ `browser` + `screenshot`;静态/单文件默认 HTML/CSS,复杂 app 才上 React+Vite |
| 实现 | "实现这个变更" | 按 tasks 用 TDD:红→绿→重构,前后端跨域隔离、mock 优先 |
| 验证 | "验证 <name>" | `$openspec-verify`(三层:L1 构建 + L2 spec 对齐 + L3 测试)→ 写 `verify.md` 凭证 |
| 归档 | "归档 <name>" | 查 `verify.md` 门禁(`overall: PASS`)→ `openspec archive <name>` |

常用 CLI 辅助:
```bash
openspec list                       # 列出活跃 changes
openspec show <name>                # 查看某个 change
openspec status --change <name>     # 看完成度
openspec validate --all             # 全量校验 changes + specs
openspec instructions --change <n>  # 取该 artifact 富化指引
```

> 会话续接:Codex 没有 `/resume` `/branch` `/rewind`。用 Codex 自身的 goal/plan 体系跟踪多步任务,普通对话天然续接;要"回到某状态"就开新会话并让 AI 先读 `openspec/` 与 `AGENTS.md` 恢复上下文。

---

## 场景三:跨栈功能协调(前后端联动)

当一个功能跨多个栈(如前端小程序 + 后端 Java,分属独立 git 仓库),单栈 change 不够:前端 agent 按跨域禁令正确排除后端,但"声明的后端依赖"没有归属,会被静默丢失(没人创建对应的兄弟 change)。scaffold.sh 对 ≥2 栈已自动建好协调层(`openspec/coordination/` + workset),用 LoopForge 约定的 **协调文档(父级)+ per-stack change(子级,`--goal` 软标签)** 模式解决(OpenSpec 1.6.0 已移除原生 initiative/workspace)。

### 对话 · 跨栈功能

**用户**:
> 技师任务详情页:前端小程序(ops_wechat)要调后端(ops_sev)的新接口。前端先做,后端另开提案。

**AI**:
1. **建父级协调文档**(跨栈持久意图,= "子流程"的父):
   ```bash
   cp openspec/coordination/_template.md openspec/coordination/task-flow.md
   # 填 shared design/decisions + change 登记表;这是跨栈"父级",CLI 不解析
   ```
2. **前端 change**(ops_wechat 仓库内,软标签挂到父级):
   ```bash
   cd ops_wechat
   openspec new change wechat-task-detail --goal "task-flow"
   # proposal.md "后端依赖"节声明所需接口(POST /api/wechat/task/detail 等)
   # Scope Out: 后端接口实现(由 Backend Agent 另行提案)
   ```
3. **后端 change**(ops_sev 仓库内,兄弟提案,同一 --goal):
   ```bash
   cd ops_sev
   openspec new change sev-task-detail-api --goal "task-flow"
   # proposal.md 实现前端声明的接口
   ```
4. **各自实现**(跨域禁令不变;前端 mock 优先)-> 各自 `$openspec-verify` -> 各自 `$openspec-archive-change`
5. **完成门禁**:在 `openspec/coordination/task-flow.md` 登记表里确认两个 change 都 verify PASS -> 功能才算完

> 协调会话(中立地,不写领域代码):`openspec workset open <项目> --tool code` 打开所有栈;1.6.0 暂时禁用 agent 直接打开,需手动在项目根启动 codex。
> 跨栈的接口契约/设计决策放在 `openspec/coordination/task-flow.md` 的 `design`/`decisions` 里,双方共享。

---

### 子代理协作详解

跨栈功能不是"两个 agent 各干各的",而是一套 **三角色协作体系**:

| 角色 | 文件 | 职责 | 关键禁令 |
|:--|:--|:--|:--|
| **Coordinator(协调者)** | `.claude/agents/coordinator.md`(CC)/ `AGENTS.md` 指令(Codex) | 路由提案、跟踪 `openspec/changes/`、将 review 委派给 reviewer | **绝不写领域代码** |
| **Reviewer(审查者)** | `.claude/agents/reviewer.md`(CC)/ `AGENTS.md` 指令(Codex) | 对照 `openspec/specs/` 的 WHEN/THEN 做只读审计,报 `file:line` + 严重级别 | **绝不编辑文件**(只读) |
| **Implementer(执行者)** | `.claude/agents/implementer.md`(CC)/ `AGENTS.md` 指令(Codex) | 实现 execution-contract 中的单个任务,TDD -> 提交 -> 自审 -> 报告 | **绝不超出任务范围** |
| **Backend Agent** | `backend/AGENTS.md` | 服务端逻辑、API、数据访问 | **绝不生成前端代码** |
| **Frontend Agent** | `frontend-web/AGENTS.md`(或 mobile) | UI、组件、状态、API 集成 | **绝不生成后端代码** |

> 所有 agent 都遵守:**绝不修改 `openspec/specs/`**(spec 是共享真相,只读)。
> Codex 注意:Coordinator、Reviewer 和 Implementer 在 CC 版是 `.claude/agents/` 下的独立 agent 文件;在 Codex 版,这三个角色的职责编码在根 `AGENTS.md` 的指令中,AI 按上下文切换角色。

#### 协作时序(以"技师任务详情页"为例)

```
用户:"技师任务详情页,前端调后端新接口"
  │
  ├─ 1. Coordinator 建父级协调文档(task-flow.md)
  │     -> 跨栈持久意图,记录在 openspec/coordination/
  │
  ├─ 2. 前端会话(ops_wechat 仓库)
  │     ├─ Frontend Agent 提案 wechat-task-detail(--goal "task-flow")
  │     │   proposal.md "后端依赖"节声明:POST /api/wechat/task/detail
  │     ├─ Frontend Agent 实现(mock 优先):
  │     │   - 先用 mock 数据跑通页面逻辑(不阻塞等后端)
  │     │   - mock 接口签名 = proposal 声明的接口契约
  │     │   - 后端就绪后,删 mock 换真实调用(一行 diff)
  │     └─ $openspec-verify -> reviewer 审计前端实现 vs spec WHEN/THEN
  │
  ├─ 3. 后端会话(ops_sev 仓库)
  │     ├─ Backend Agent 提案 sev-task-detail-api(兄弟提案,--goal "task-flow")
  │     │   实现前端声明的接口,签名必须与 proposal 一致
  │     ├─ Backend Agent TDD:Red(失败测试)-> Green(最小实现)-> Refactor
  │     │   (无测试运行器时:特征化测试 或 debt.md 登记)
  │     └─ $openspec-verify -> reviewer 审计后端实现 vs spec WHEN/THEN
  │
  ├─ 4. 集成验证
  │     ├─ 前端删 mock -> 接真实后端
  │     ├─ Coordinator 检查:task-flow.md 登记表里两个 change 都 verify PASS
  │     └─ 全部 verify PASS -> 功能才算完
  │
  └─ 5. 归档
        各自 $openspec-archive-change -> 移入 openspec/archive/
```

#### 接口契约共享

跨栈的接口契约和设计决策放在 `openspec/coordination/<feature>.md` 的 `design` / `decisions` 里,双方共享:

- **前端先声明** -> `proposal.md` 的"后端依赖"节写明接口路径、方法、请求/响应结构
- **后端照此实现** -> 兄弟提案的 spec.md 中 WHEN/THEN 对齐前端声明
- **有分歧时** -> Coordinator 开协调会话(`openspec workset open <项目> --tool code`,手动启动 codex),讨论后更新协调文档的 `decisions`,双方各自 rewind 修改提案

#### Mock 优先原则

前端永远先 mock,不阻塞等后端:

1. Frontend Agent 根据 proposal 声明的接口签名,在本地建 mock(`src/api/mock/` 或 MSW handler)
2. 页面逻辑基于 mock 跑通,前端 `$openspec-verify` 可以独立 PASS
3. 后端就绪后,Frontend Agent 做一个"切换" change:删 mock 路径,接真实 API base URL
4. 这个"切换"本身也走 propose → apply → verify → archive(因为改了行为)

> **小程序例外**：微信/支付宝等小程序的交付链路（开发者工具->真机预览->体验版->审核->线上）使 mock 仅在第一站有效；线上强制 HTTPS 域名白名单（localhost 仅临时豁免），且强绑定微信生态能力（openid 登录、授权、支付、分享、订阅消息），mock 无法真实验证。手写 JS 拦截覆盖期短、性价比远低于 web。**小程序前端直连真实测试后端是合理的工程选择**，不适用 mock-first 原则--尽早连真环境反而能更早暴露 openid 绑定、域名白名单、真机网络等 mock 验不了的问题。

> 跨域禁令保证:Backend Agent 的 `AGENTS.md` 写了 `NEVER generate frontend code`,Frontend Agent 的 `AGENTS.md` 写了 `NEVER generate backend code`。各自只在自己的目录里工作,scaffold 生成时已预置。
> Codex 会话续接:跨栈协作中如果会话中断,新会话让 AI 先读 `openspec/` + 根 `AGENTS.md` 恢复上下文,Codex 自身的 goal/plan 体系会跟踪多步任务进度。

---

### SDD:子代理驱动开发(Subagent-Driven Development)

当变更任务多或有跨模块依赖时,apply 阶段可以**分派子代理**逐任务实现,而不是全部在主上下文里做。这防止上下文膨胀,并强制每个任务有独立的责任和审查。

#### 三种执行模式(propose 阶段选定)

| 模式 | 条件 | 方式 |
|:--|:--|:--|
| **Inline** | <=3 个任务,无跨模块依赖 | 直接在主上下文实现(不分派子代理) |
| **Batch Inline** | >3 个任务,同模块,无风险指标 | 在主上下文逐任务实现(不分派) |
| **SDD** | 有跨模块依赖 / >3 个任务 / 有风险指标 | 逐任务分派 implementer 子代理,完成后分派 reviewer 子代理 |

#### SDD 工作流(当 execution_mode: SDD)

```
对 execution-contract.md 中的每个任务批次:
  1. 分派 Implementer 子代理
     - CC: Task 工具; Codex: role-switch 到 Implementer 角色
     - 使用 openspec/sdd/implementer-prompt.md 模板
     - 填入: [task name], [BRIEF_FILE], [directory], [REPORT_FILE], [MODEL]
  2. Implementer 执行: TDD(RED->GREEN->REFACTOR)或特征化/debt
     -> 提交 -> 自审 -> 报告 DONE|BLOCKED|NEEDS_CONTEXT
  3. DONE 后分派 Reviewer 子代理
     - CC: Task 工具; Codex: role-switch 到 Reviewer 角色
     - 使用 openspec/sdd/reviewer-prompt.md 模板
     - 审查: spec 合规 + 代码质量 + 测试 -> Approved|Needs fixes
  4. 更新 openspec/sdd/progress.md(状态、提交、审查结论)
  5. BLOCKED/NEEDS_CONTEXT: 升级给用户(重试上限 2b 适用)
  6. Needs fixes: 带 reviewer 反馈重新分派 Implementer
```

#### SDD 与前后端协作的结合

跨栈功能(如前端+后端)时,SDD 与多栈协调层协同工作:

- **每个栈分派自己的 implementer 子代理**(跨域禁令不变)
- **execution-contract.md** 定义每个栈的任务批次和栈间依赖
- **前端 implementer** 先 mock API(`openspec/specs/api/spec.md`),不阻塞等后端
- **后端 implementer** 按同一 spec 实现
- **Coordinator** 通过 `openspec/sdd/progress.md` 和协调文档登记表(`openspec/coordination/<feature>.md`)跟踪两个栈的进度
- **跨栈门禁**:所有登记的 change 都 verify PASS,功能才算完成

> Codex 角色切换:在 Codex 中,implementer/reviewer 子代理通过 `AGENTS.md` 中的角色指令实现。AI 在执行 SDD 任务时,按 `openspec/sdd/implementer-prompt.md` 模板的内容约束自己的行为,完成后再切换到 reviewer 角色按 `reviewer-prompt.md` 模板审查。

#### 实操演练:一人团队用 SDD 做跨栈功能(前后端分离)

**场景**:你一个人维护一个前后端分离的老项目(后端 Java/Spring Boot + 前端 Vue3),现在要加"工单导出 PDF"功能--后端生成 PDF,前端加导出按钮。

**第一步:propose(在项目根目录)**

```
你: "加工单导出 PDF 功能,后端生成 PDF,前端加导出按钮"
AI: (brainstorming) "确认几个问题:导出范围?权限控制?PDF 格式?"
你: "当前工单列表的全部,仅管理员,标准 A4"
AI: (writing-plans) -> proposal.md + spec.md (WHEN/THEN) + design.md + tasks.md
    -> execution-contract.md(任务批次:后端 3 任务 + 前端 2 任务,有跨栈依赖 -> SDD 模式)
    -> "执行契约已就绪,execution_mode: SDD,共 5 个任务分 2 个批次。
        后端批次:① PDF 生成服务 ② 导出 API ③ 权限校验
        前端批次:④ 导出按钮组件 ⑤ 调用导出 API(依赖 ②)
        是否批准开始实施?"
你: "批准"
```

**第二步:apply -- 后端批次(Codex 会话在后端目录)**

```
你: cd backend && codex
你: "实施工单导出 PDF 的后端任务(execution_mode: SDD)"

AI: (role-switch -> Implementer, 读 openspec/sdd/implementer-prompt.md)
    "任务 ① PDF 生成服务
     先写测试(Red): ExportPdfServiceTest...
     ✓ Red 确认
     实现 ExportPdfService...
     ✓ Green
     提交: feat(export): PDF generation service
     自审: 通过
     报告: DONE"

AI: (role-switch -> Reviewer, 读 openspec/sdd/reviewer-prompt.md)
    "审查任务 ①...
     spec 合规: 通过
     代码质量: 通过
     测试: Red+Green 证据完整
     评定: Approved"

AI: (role-switch -> Implementer) "任务 ② 导出 API..."
    (重复 Red->Green->commit->self-review->report)
AI: (role-switch -> Reviewer) "审查任务 ②... Approved"
AI: (role-switch -> Implementer) "任务 ③ 权限校验..."
AI: (role-switch -> Reviewer) "审查任务 ③... Approved"

AI: "后端批次完成。更新 openspec/sdd/progress.md:
     任务 ①②③ 全部 Complete + Approved。
     建议跑后端构建验证 L1。"

你: "跑构建"
AI: (读 openspec/verify.config.yaml -> backend.build = mvn compile -q)
    "✓ 构建检查通过(mvn compile)"
```

**第三步:apply -- 前端批次(Codex 会话在前端目录,可并行)**

```
你: cd frontend-web && codex
你: "实施工单导出 PDF 的前端任务(execution_mode: SDD)"

AI: (role-switch -> Implementer)
    "任务 ④ 导出按钮组件
     先 mock API(从 openspec/specs/api/spec.md 读接口签名):
       POST /api/tickets/export -> 返回 PDF blob
     写测试(Red): ExportButton.test.ts...
     ✓ Red 确认
     实现 ExportButton.vue...
     ✓ Green
     提交: feat(export): export button component
     报告: DONE"

AI: (role-switch -> Reviewer) "审查任务 ④... Approved"

AI: (role-switch -> Implementer) "任务 ⑤ 调用导出 API
     (后端 API 已就绪,删 mock 接真实接口)
     写测试(Red): 集成测试调用真实 /api/tickets/export...
     ✓ Red 确认
     实现 API 调用逻辑...
     ✓ Green
     提交: feat(export): wire to real API
     报告: DONE"

AI: (role-switch -> Reviewer) "审查任务 ⑤... Approved"

AI: "前端批次完成。更新 progress.md: ④⑤ Complete + Approved。
     建议跑前端构建验证 L1。"
你: "跑构建"
AI: "✓ 构建检查通过(pnpm build)"
```

**第四步:verify(三层验证)**

```
你: "验证工单导出功能"
AI: (openspec-verify skill)
    "L1 构建:
       backend: mvn compile -> PASS
       frontend: pnpm build -> PASS
     L2 规格对齐:
       场景 1 '管理员导出工单列表 PDF' -> 已实现(ExportButton.vue:42 + ExportController.java:28)
       场景 2 '非管理员点击导出' -> 已实现(权限校验拦截,返回 403)
     L3 测试:
       backend: mvn test -> 8/8 PASS
       frontend: pnpm test -> 5/5 PASS
     总体: PASS
     verify.md 已写入。"
```

**第五步:archive**

```
你: "归档"
AI: (检查 verify.md -> overall: PASS)
    "门禁通过,归档到 openspec/archive/"
```

> **一人团队心法**:你不需要同时开两个会话。先后端会话做完 3 个任务(可能 20 分钟),再切到前端会话做 2 个任务(可能 10 分钟)。SDD 的 progress.md 记录了每一步状态,即使中途打断,新会话读 progress.md 就能恢复。

---

## 场景四:运维与诊断子命令

脚手架生成后,`scaffold.sh` 还提供一组运维 / 诊断子命令,日常排查、token 优化、变更管理都用得上。可直跑 CLI,也可让 Codex 代劳(子命令在 CC 版与 Codex 版完全一致)。

### 对话 1 · token 占用与中文开销

**用户**:
> `./myapp` 的自动加载文件 token 占用怎么样?有没有中文超标的?

**AI**:
```bash
./scaffold.sh tokens ./myapp
```
逐文件列出 `AGENTS.md` / `CLAUDE.md` / 各栈入口 / `.claude/rules/*.md` 的 token 数与 CJK 占比;标 `!! Chinese` 的文件(CJK > `CJK_THRESHOLD`,默认 10%)是 O7 开销,翻译成英文即可回收 30–50% token。标 `!! over budget` 的超过 `TOKEN_THRESHOLD=3000`(S9 检查)。

### 对话 2 · 项目健康检查

**用户**:
> `./myapp` 健康吗?依赖和脚手架都全吗?

**AI**:
```bash
./scaffold.sh doctor ./myapp
```
检查 node / python3 / git / ripgrep / openspec 依赖、`openspec/` 内脚手架文件(guard.sh、build-contract.sh、validate-artifacts.py、verify.config.yaml、sdd/ 等)、入口文件(`CLAUDE.md` + `AGENTS.md`)、以及脚本语法,输出 `N pass, N warn, N fail` + `Healthy` / `Issues found`。

### 对话 3 · 变更状态总览

**用户**:
> 现在有哪些变更,各到什么阶段了?

**AI**:
```bash
./scaffold.sh changes ./myapp
```
列出 `openspec/changes/` 下所有变更及其相位(`proposing -> applying -> verifying -> archived | abandoned`)与任务进度(`done/total`)。

### 对话 4 · 生成执行契约

**用户**:
> 给 `add-login` 变更生成执行契约。

**AI**:
```bash
./scaffold.sh contract ./myapp/openspec/changes/add-login
```
从规划产物(proposal / spec / design / tasks)自动生成 `execution-contract.md`(含 Intent Lock、已批准行为、设计决策、任务批次)。已有契约时拒绝覆盖,加 `--force` 才覆盖。生成后跑 `bash openspec/ensure-contract-fresh.sh --update <change-dir>` 刷新哈希,apply 阶段的 guard.sh 会检查契约新鲜度。

### 对话 5 · 校验产物结构

**用户**:
> 这个变更的 proposal / spec 写得合不合格?

**AI**:
```bash
./scaffold.sh validate ./myapp/openspec/changes/add-login
```
调用 `openspec/validate-artifacts.py` 校验 proposal(## What Changes)、spec(ADDED/MODIFIED/REMOVED 段)、design、tasks 的结构完整性,列出错误。

### 对话 6 · CLI 重构分析(快速版)

**用户**:
> `./legacy` 的单体 `AGENTS.md` 有 280 行,该不该拆?怎么拆?

**AI**:
```bash
./scaffold.sh restructure ./legacy
```
CLI 版做关键词扫描:自动检测技术栈(backend / frontend / mobile)、逐段落(`##` 标题)分类去向(root / specs / rules / 各栈 agent)、评估复杂度(行数是否 > 120)、给出迁移计划。**注意**:CLI 版只做结构分析(不动文件);真正拆分内容、生成 agent 文件、重写根入口是 skill **restructure 模式**的语义工作(见场景一对话 1 · 起点 B)。

> 版本查询:`./scaffold.sh version` 打印 LoopForge 版本、bash 版本、openspec / node 版本,排查环境问题时有用。

---

## 速查:可直接复制的命令

```bash
# 新建(Codex 优先,默认 backend+frontend,自动 openspec init)
./scaffold.sh <name> --dir ./<name> --tools codex

# 三栈(web + mobile)
./scaffold.sh <name> --stacks backend,frontend,frontend-mobile --tools codex

# 双工具(openspec init 生成 .codex/ + .claude/ 指令文件;LoopForge 增强只注入 .codex/)
./scaffold.sh <name> --tools codex,claude

# 预览不落地
./scaffold.sh list --stacks backend,frontend

# 自检环境
./scaffold.sh check

# 审计项目
./scaffold.sh check ./<project>

# 跳过 init(稍后手动 openspec init)
./scaffold.sh <name> --no-init

# 诊断与运维子命令
./scaffold.sh tokens ./<project>        # 逐文件 token + CJK 占比(O7 开销)
./scaffold.sh doctor ./<project>        # 健康检查:依赖 / 脚手架 / 门禁 / verify 配置
./scaffold.sh version                   # 打印 LoopForge 版本 + 环境
./scaffold.sh changes ./<project>       # 列出所有变更及相位/状态

# 变更工作流子命令
./scaffold.sh validate ./<project>/openspec/changes/<change>   # 校验产物结构
./scaffold.sh contract ./<project>/openspec/changes/<change>   # 生成 execution-contract.md
./scaffold.sh contract --force ./<project>/openspec/changes/<change>  # 覆盖已有契约
./scaffold.sh restructure ./<project>   # 分析单体入口文件,规划按栈拆分

# 日常 loop($ 技能方式;或用 openspec CLI 对应命令)
$openspec-propose                    # 提案:澄清需求 → 写 proposal + spec
$openspec-apply-change               # 实现:按 tasks TDD
$openspec-verify                     # 三层验证(L1 构建/L2 spec 对齐/L3 测试)→ 写 verify.md
$openspec-archive-change             # verify.md overall=PASS → 归档
```

**在 Codex 中调用**:输入 `$loopforge-codex` 激活 skill，然后描述任务（"给 X 搭脚手架" / "审计 X" / "拆分 AGENTS.md"），AI 会选对应模式或 CLI 执行。也可直接跑 `scaffold.sh` CLI。

---

## 成熟度评分参考

`check` 输出 `通过/总数 (百分比)`,对应等级:

| 百分比 | 等级 |
|:--|:--|
| < 33% | 基础建设前 |
| 33–66% | 基础级 |
| 66–90% | 质量级 |
| > 90% | 工业级 |

> `check` 是 CLI 快照(含 O7 CJK 扫描、S5 Superpowers 检测、O4 归档错位检测等可自动判定项);完整 30 项审计(含 S3 工作流、H4 工作树等需语义判断的项)请让 AI 进 skill audit 模式。
>
> Codex 提示:`check` 是 Codex-aware 的——E3/E4/S6 经 `AGENTS.md` 判定(非 `.claude` 误报),S5 也优先看各栈 `AGENTS.md` 的深度指引(`.claude/skills/` 仅 Claude 加分项)。纯 Codex 项目无需扣项,分数如实反映 `AGENTS.md` 是否写到位。

---

## 附:把 skill 装进 Codex

```bash
cp -R skills/loopforge-codex ~/.codex/skills/loopforge-codex
```
`scaffold.sh` 已是 skill 目录内的实体文件,普通拷贝即可。重启 Codex 即可按 `description` 自动触发,或用 `$loopforge-codex` 显式调用。`loopforge-codex/` 目录里有 `SKILL.md`(必需,frontmatter `name`+`description`)+ `scaffold.sh`(CLI)。可选补 `agents/openai.yaml` 拿到界面显示名,不影响触发。
