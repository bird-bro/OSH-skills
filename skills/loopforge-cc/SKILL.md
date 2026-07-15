---
name: loopforge-cc
description: Loop工程框架（LoopForge）- 为已有代码项目接入 OpenSpec + Superpowers + Harness 工程范式。当用户说"接入 loop 工程"、"搭 loop 脚手架"、"loop 工程框架"、"审计项目结构"、"拆分 CLAUDE.md"时触发。三种模式：scaffold（为已有代码无 CLAUDE.md 的项目生成框架）、audit（30 项成熟度审计）、restructure（拆分单体 CLAUDE.md 为按栈 agent 文件）。English: Loop Engineering - scaffold, audit, and restructure an AI-collaboration project against the OpenSpec + Superpowers + Harness (LoopForge) paradigm. Use when the user asks to "set up loop engineering", "scaffold a LoopForge project", "audit project structure", "split CLAUDE.md", or "optimize AI collaboration structure".
---

# Loop Engineering - Scaffold · Audit · Restructure

**OpenSpec defines direction (WHAT), Superpowers enforces discipline (HOW), Harness orchestrates collaboration (WHO).**

## Core Paradigm

| Layer | Tool | Responsibility |
|:--|:--|:--|
| Spec | OpenSpec / `openspec/` | WHAT - shared truth |
| Discipline | Superpowers / `.claude/` | HOW - TDD, review, quality gates |
| Harness | CLAUDE.md + agents | WHO - roles, boundaries |

> **Multi-tool harness:** `CLAUDE.md` and `AGENTS.md` are parallel **live** entry files - Claude Code reads `CLAUDE.md`, Codex reads `AGENTS.md`. Both are first-class, never "dead". Keep nav-hub content in sync. Per-stack dirs may carry both (`<stack>/CLAUDE.md` + `<stack>/AGENTS.md`); different tools load them, so mirroring is not duplication.

Key principles: Spec as Code. TDD enforced (not a slogan). Skills on-demand. No cross-domain. Single source of truth. English for auto-loaded files (saves 30-50% tokens vs Chinese).

## Three Modes

| Mode | When to use | How |
|:--|:--|:--|
| **scaffold** | Existing code, no CLAUDE.md / openspec/ | Run `scaffold.sh` → complete framework |
| **audit** | Existing project, check health | Run 30 checks, score maturity, report gaps |
| **restructure** | Monolithic CLAUDE.md or low audit score | Split into per-stack agents + apply Phase 5 order |

## Execution Instructions

1. Determine mode from user intent (scaffold / audit / restructure).
2. Run the matching section below.
3. Always finish with the Verification Checklist.

## CLI Subcommands (`scaffold.sh`)

The generator ships with ten subcommands (run directly, or ask the AI to run them):

| Subcommand | Purpose |
|:--|:--|
| `scaffold.sh <name> [opts]` | Generate the framework (default) |
| `scaffold.sh list [opts]` | Preview the file manifest without writing anything |
| `scaffold.sh check [project]` | Self-check (env + script) + LoopForge compliance audit; no arg = self-check only |
| `scaffold.sh tokens [project]` | Token audit of auto-loaded files - per-file tokens + CJK% (O7 overhead); no arg = cwd |
| `scaffold.sh validate <change-dir>` | Validate a change's artifact structure (proposal/spec/design/tasks) |
| `scaffold.sh changes [project]` | List all changes and their phase/status |
| `scaffold.sh doctor [project]` | Health check: deps, scaffold, guard, verify config |
| `scaffold.sh version` | Print LoopForge version + environment |
| `scaffold.sh contract [--force] <change-dir>` | Auto-generate `execution-contract.md` from planning artifacts |
| `scaffold.sh restructure [project]` | Analyze a monolithic entry file and plan a per-stack split |

`check` prints PASS / PARTIAL / FAIL per check plus a maturity score (an automatable subset of the 30; use audit mode for the full set). It also auto-measures **O7** - CJK char ratio in auto-loaded files, threshold via the `CJK_THRESHOLD` env var (default 10). For per-file token counts and CJK breakdown, run `scaffold.sh tokens`. See `USAGE-PLAYBOOK.md` for dialogue-style usage.

---

## Mode: Scaffold

Generate a complete Loop Engineering framework from scratch.

### Parameters

| Parameter | Default | Description |
|:--|:--|:--|
| `<project-name>` | (required) | Project name (used for dir, workset, placeholders) |
| `--dir <path>` | `./<project-name>` | Target dir. **Use `--dir .` to scaffold into current project root** |
| `--stacks <list>` | `backend,frontend` | Stack types: `backend`, `frontend`, `frontend-mobile` |
| `--backend-dir <name>` | `backend` | Backend code dir name (must match real dir) |
| `--frontend-dir <name>` | `frontend-web` | Frontend code dir name (must match real dir) |
| `--mobile-dir <name>` | `frontend-mobile` | Mobile code dir name |
| `--tools <list>` | `claude` | openspec init tool type |
| `--no-init` | (off) | Skip `openspec init`, generate LoopForge layer only |

> For existing projects: `ls` the project root first, then pass `--*-dir` flags matching real directory names. The number of `--*-dir` flags depends on how many stacks the project has.

### Prerequisites
- OpenSpec CLI: `openspec --version` (install: `npm i -g @fission-ai/openspec@latest`)
- Node/npm available

### Steps
1. Run the generator - it creates `openspec/`, `.claude/`, per-stack `CLAUDE.md` (+ `AGENTS.md` for Codex), and the root nav hub (`CLAUDE.md` + `AGENTS.md`):
   ```bash
   ./scaffold.sh <project-name> --stacks backend,frontend[,frontend-mobile]
   ```
   `scaffold.sh` calls `openspec init` automatically (use `--no-init` to skip), then layers LoopForge templates on top. It is **non-destructive**: existing files are skipped.
2. Install on-demand components (referenced by audit but NOT generated - they are separate skills/agents):
   - Superpowers skills: brainstorm, writing-plans, executing-plans, code-review, verification-before-completion
   - `frontend-design` skill (frontend projects only)
3. Fill `[BRACKETS]` placeholders in `openspec/project.md`, `openspec/specs/*`, and per-stack `CLAUDE.md`.
4. Run **Mode: Audit** to verify maturity.

> All file templates live in `scaffold.sh` (single source of truth). Do not duplicate them here.

---

## Mode: Audit

### Phase 0: Environment Check (E1-E4)

| # | Check | Criteria | Fix |
|:--|:--|:--|:--|
| E1 | OpenSpec CLI installed | `openspec --version` returns valid version | `npm i -g @fission-ai/openspec@latest` |
| E2 | Project initialized | `openspec/` exists with `specs/`, `changes/`, `archive/` | `openspec init` |
| E3 | Slash commands generated | `.claude/commands/opsx:propose`, `opsx:apply`, `opsx:archive`, `opsx:verify` (loopforge) exist | `openspec init` + scaffold |
| E4 | frontend-design skill available | `.claude/skills/frontend-design/SKILL.md` exists (frontend only) | Install `frontend-design` skill |

Environment score = E_yes / 4. 0/4 → STOP; 1-3/4 → WARNING; 4/4 → PASS.

### Phase 1: 30 Checks

#### 1.1 OpenSpec - "Define Direction" (O1-O8)

| # | Check | Criteria |
|:--|:--|:--|
| O1 | Shared spec docs | `openspec/specs/` has `api/spec.md` + `data/spec.md` + `errors/spec.md` |
| O2 | API contract authoritative | All agents reference it; frontend mocks from it; backend implements to it |
| O3 | Delta proposal templates | `openspec/changes/_template/` with `proposal.md` + `specs/<capability>/spec.md` (## ADDED Requirements) |
| O4 | Change archive | `openspec/archive/` for completed proposals |
| O5 | Project overview | `openspec/project.md`: tech stack, module map, architecture - no coding conventions |
| O6 | Boundary clear | `openspec/README.md` explains structure: `specs/` inside `openspec/`, unified entry |
| O7 | Language efficient | Auto-loaded files (root + per-stack `CLAUDE.md`/`AGENTS.md`, `.claude/rules/*.md`) in English. Auto-measured by `check` (CJK char ratio; `CJK_THRESHOLD` env, default 10%). `specs/`/`openspec/` assessed in full audit mode |
| O8 | WHEN/THEN scenarios | Every spec in `openspec/changes/` contains WHEN/THEN verification scenarios |

#### 1.2 Superpowers - "Enforce Discipline" (S1-S9)

| # | Check | Criteria |
|:--|:--|:--|
| S1 | Agent role declared | Each CLAUDE.md starts with "You are a [Stack] [Role] Agent. Your scope: [...]" |
| S2 | Cross-domain prohibition | Each agent states MUST NOT / "NEVER generate [opposite-domain] code" |
| S3 | Superpowers workflow | 5 steps: brainstorm → writing-plans → executing-plans → code-review → verification. Auto-triggered by `/opsx:propose`, `/opsx:apply`, `/opsx:verify` - no slash command needed |
| S4 | Project rules with globs | `.claude/rules/` auto-loaded by file-path matching |
| S5 | Domain skills | `.claude/skills/` with YAML frontmatter; max 300 lines each |
| S6 | Permissions & dangerous-command gating | `.claude/settings.json` with allow/deny lists; `rm -rf`, `git push --force`, `git reset --hard` in deny list (absorbs former H9) |
| S7 | Hooks configured | SessionStart, PreToolUse, Stop hooks |
| S8 | Custom agents | Reviewer (Read+Bash only) + Coordinator + Implementer (SDD dispatch) |
| S8b | SDD artifacts | `openspec/sdd/` has `implementer-prompt.md` + `reviewer-prompt.md` + `progress.md` (subagent-driven development templates) |
| S9 | Context budget | Agent CLAUDE.md < 3K tokens; details in `skills/` for on-demand load |

#### 1.3 Harness - "Orchestrate Collaboration" (H1-H8)

| # | Check | Criteria |
|:--|:--|:--|
| H1 | Workspace separation | One subdirectory per tech stack, each with its own CLAUDE.md (+ AGENTS.md for Codex) |
| H2 | Shared spec accessible | All agents reference `../openspec/specs/` |
| H3 | Mock-first frontend | Frontend mocks APIs from contract (MSW/mockjs/etc); mini-program: direct real-backend is valid (see H3 notes) |
| H4 | Git worktree isolation | Features developed in isolated worktrees |
| H5 | Root CLAUDE.md is nav hub | ≤ 120 lines; project map + build + session commands |
| H6 | Session management | `/resume`, `/branch`, `/rewind` keep continuity |
| H7 | No dead files | Every `.md` has a clear load/trigger path (CLAUDE.md→Claude Code, AGENTS.md→Codex, specs→all). AGENTS.md is NOT dead |
| H8 | Zero duplication | No rule in two files the SAME tool loads. CLAUDE.md & AGENTS.md are different tools - mirroring is allowed |

### Scoring

```
Environment     = E_yes / 4
OpenSpec        = O_yes / 8
Superpowers     = S_yes / 9
Harness         = H_yes / 8
Overall         = (E + O + S + H) / 29
```

| Score | Level |
|:--|:--|
| < 33% | Pre-build |
| 33-66% | Basic |
| 66-90% | Quality |
| > 90% | Industrial |

Context-efficiency target: reduction ratio > 3x; per-agent context < 150 lines (~3K tokens).

---

## Mode: Restructure

Use when a monolithic CLAUDE.md exists or the audit score is low.

### Phase 1: Discover
Read the root CLAUDE.md completely and classify every section per stack:

| Content type | Belongs in |
|:--|:--|
| Business context | Root CLAUDE.md (nav) + `openspec/project.md` |
| Build commands (mvn/gradle) | Backend Agent CLAUDE.md |
| Build commands (pnpm/npm/yarn) | Frontend Agent CLAUDE.md |
| Backend patterns (Java/Spring/MyBatis) | Backend Agent CLAUDE.md |
| Frontend patterns (Vue/React/Element Plus) | Frontend Agent CLAUDE.md |
| API paths | `openspec/specs/api/spec.md` (NOT agent files) |
| Shared naming conventions | `.claude/rules/` or `specs/` |

Present findings to the user and confirm stacks before generating files.

### Phase 2: Generate Agent CLAUDE.md (per stack)
Each agent file must contain: Role, Project Overview, Before You Code, Module Structure, Coding Standards, Superpowers Workflow, TDD, Build Commands. Explicit cross-domain prohibition in every file.

> For new files, reuse `scaffold.sh` templates (they already match this structure). For splitting an existing monolith, follow the Content Extraction Rules below.

**Content Extraction Rules:**
1. Code examples stay with their stack (Java → backend, Vue/SCSS → frontend).
2. API paths go to `openspec/specs/api/spec.md`, never agent files.
3. Response format / error codes are shared - minimal reference in both agents, authoritative definition in `specs/`.
4. Build commands split by tool (`mvn*` → backend, `pnpm*`/`npm*` → frontend).
5. Universal conventions → `.claude/rules/` or `specs/`; domain-specific → one agent only.
6. Business context → root CLAUDE.md only; each agent gets a one-line "System".

**Edge cases:** single stack → don't split, just add Role + NEVER + Superpowers + TDD. Already split → verify all sections present, add missing ones. Mobile + desktop frontends → separate files (different UI paradigms).

### Phase 3: Rewrite Root CLAUDE.md (nav hub, ≤120 lines)
Project map + business context (1-3 sentences) + tech-stack table + development workflow + AI coding rules + session commands + minimal build & test. If it exceeds 120 lines, move content to `openspec/project.md` or agent files.

### Phase 4: Verify
1. No content lost - every example/convention/command is in exactly one file.
2. No duplication - no rule in two auto-loaded files.
3. All required sections present in each agent file.
4. Cross-domain prohibition explicit in every agent file.
5. Path references correct (`../openspec/specs/` relative to each agent's dir).
6. Root CLAUDE.md is a hub (≤120 lines, no agent instructions, no coding standards).

### Phase 5: Execute Restructuring (do not reorder)
```
1. CREATE openspec/         ← unified entry (specs/ inside)
2. CREATE .claude/          ← rules + skills + settings.json + agents
3. CREATE agent CLAUDE.md   ← one per tech stack, inside its code dir
4. REWRITE root CLAUDE.md   ← nav hub only, after all pieces exist
5. DELETE dead files        ← duplicates & orphaned docs ONLY. Never delete AGENTS.md - it is the Codex harness entry (≡ CLAUDE.md for Claude Code); keep in sync
6. VERIFY no duplication    ← re-read every auto-loaded file
```

---

## Output Format (Audit)

1. **Diagnostic table** - all 30 checks with YES / PARTIAL / NO + per-layer scores
2. **Maturity grade** - overall % + level label
3. **Before/after metrics** - context-efficiency ratio (target > 3x)
4. **Top 3 issues** - root cause + Fix reference + impact estimate
5. **Target structure** - directory tree
6. **Action plan** - ordered per Phase 5

## Anti-Pattern Quick Reference

| Anti-pattern | Fix |
|:--|:--|
| AGENTS.md deleted / treated as dead | Keep it - Codex harness entry (≡ CLAUDE.md); mirror nav hub, keep in sync |
| Monolith CLAUDE.md (250+ lines, multi-stack) | Split into per-directory CLAUDE.md |
| Specs inline in CLAUDE.md | Extract to `openspec/specs/` |
| API paths in agent files | Move to `openspec/specs/api/spec.md` |
| Duplicate rules in CLAUDE.md + rules/ | Keep in `rules/` only |
| No role declaration | "## Role: You are a [X] Agent" |
| No cross-domain ban | Add "NEVER generate [X] code" |
| TDD as plain text | Add Superpowers 5-step workflow (auto-triggered) |
| Reviewer can edit code | Reviewer tools = `["Read", "Bash"]` only |
| Specs in Chinese (auto-loaded) | English - saves 30-50% tokens |
| Root CLAUDE has agent rules | Root = nav hub; rules in sub-CLAUDE.md |
| No dangerous-command deny | Add `rm -rf`, `git push --force` to permissions.deny |
| specs/ at root level | Move to `openspec/specs/` (unified entry) |


## Audit Check Notes (30-check full audit)

> The CLI `check` (24 items) is automatable. The full 30-check audit is AI-driven
> (SKILL.md audit mode). These notes guide the AI's judgment on nuanced checks.

### H4: Git worktree isolation
- **Multi-repo workspace** (root is NOT a git repo, but each stack subdir is its own repo):
  This is a **valid pattern**, not a failure. Report as **WARN** (not FAIL):
  "Multi-repo workspace: worktree isolation operates per-stack (inside each subdir),
  not at workspace root. ensure-branch.sh handles this gracefully (exits 0 with warning)."
- **Single repo**: PASS if `git rev-parse --is-inside-work-tree` succeeds.
- **No git at all**: WARN (not FAIL) - "No git repo: version control recommended but
  not blocking for scaffold/audit phase."

### S7: Hooks
- The scaffold generates **echo stubs** by design in `.claude/settings.json`:
  `SessionStart`, `PreToolUse` (Edit|Write), `Stop`. These are the **recommended
  default** - lifecycle observability without per-edit latency.
- Report as **PASS**: "Hooks configured (echo stubs). Optional: replace with real
  lint/build gates when ready for CI enforcement."
- Quality enforcement is already covered by `/opsx:verify` (L1 build / L3 tests)
  and Superpowers `verification-before-completion`. Real PreToolUse gates (e.g.
  `pnpm lint` on every edit) are an **advanced, opt-in** choice with known tradeoffs:
  per-edit latency, blocked edits when legacy lint errors exist, and complex
  per-stack routing. Mention as a brief optional tip, not an action item.
- Only report FAIL if `.claude/settings.json` has no hooks section at all.

### H3: Mock-first practice
- The scaffold template mentions MSW (Mock Service Worker) as one option.
- **Any mock solution counts as PASS**: MSW, mockjs, vite-plugin-mock-dev-server,
  axios-mock-adapter, nock, etc.
- Check for mock usage in frontend `package.json` dependencies or source code.
- Report FAIL only if no mock mechanism exists AND no real API calls are wired.
- **Environment-specific judgment** - mock-first value depends on the frontend
  runtime environment, not all frontends benefit equally:
  - **Browser-based web** (vite/webpack dev server): mock plugins intercept
    requests at zero cost, no HTTPS/domain restrictions, localhost is the
    terminal form -> mock covers the entire dev phase. Mock-first is the
    expected practice; absence is a real gap.
  - **Mini-program** (WeChat/Alipay/etc.): delivery chain is dev-tools ->
    real-device preview -> experience version -> review -> online. Mock only
    covers the first station; later stages require a real backend. Production
    enforces HTTPS domain whitelists (localhost is a temporary dev exemption),
    and WeChat ecosystem capabilities (openid login, authorization, payment,
    sharing, subscribe messages) cannot be meaningfully mocked. Hand-written
    JS interception has a short coverage window and low ROI vs web.
- **Mini-program exception**: direct connection to a real test backend is a
  **valid engineering choice** driven by the delivery chain, not an omission.
  Report **PASS** for mini-program frontends that wire real API calls to a
  test backend, even without a mock layer. Early real-backend integration
  surfaces openid binding, domain whitelist, and real-device network issues
  that mock cannot catch.
- When a project has both web and mini-program frontends, evaluate H3
  **per-stack** - web frontend needs mock; mini-program frontend does not.
  A mixed result (web PASS + mini-program PASS-without-mock) is an overall
  **PASS**, not a partial/warning.

## Verification Checklist

- [ ] Auto-loaded files are English
- [ ] Root CLAUDE.md ≤ 120 lines, nav hub only
- [ ] AGENTS.md mirrors CLAUDE.md as the Codex entry (live, in sync) - not deleted
- [ ] Each sub-CLAUDE.md has Role + Overview + Before You Code + Standards + Superpowers + TDD + Build
- [ ] Cross-domain prohibition explicit in every sub-CLAUDE.md
- [ ] `openspec/specs/api/spec.md` authoritative for all agents
- [ ] `openspec/changes/_template/` has `proposal.md` + `specs/<capability>/spec.md`
- [ ] `.claude/settings.json` has permissions + hooks
- [ ] Reviewer tools = `["Read", "Bash"]` only
- [ ] Rules use globs; skills ≤ 300 lines each
- [ ] Zero duplication across auto-loaded files
- [ ] Each sub-CLAUDE.md < 3K tokens

## Multi-Stack Coordination (Cross-Stack Features)

When a feature spans >=2 stacks (e.g. frontend + backend in separate repos), a single-stack `spec-driven` change is insufficient: the agent correctly excludes the other stack via the cross-domain ban, but the "declared dependency" then has no home and is silently lost (nobody creates the sibling change). OpenSpec 1.6.0 removed the native `workspace`/`context-store`/`initiative` layer, so LoopForge replaces it with a managed convention that scaffold.sh auto-sets up for >=2 stacks:

- **`openspec/coordination/<feature>.md`** - the **parent**: a shared doc (design / decisions / tasks + a per-stack change registry) tracking the whole cross-stack feature. CLI-safe: `openspec list`/`validate`/`context` do not parse it.
- **`openspec new change <name> --goal "<feature>"`** - each stack's **child** change, soft-tagged to the feature via the `--goal` metadata (1.6.0 has no native parent/child link; track linkage in the coordination doc's registry).
- **`openspec workset`** - groups all stack dirs so you can open them together.

Stable pattern (CLI-driven; works in Codex and Claude Code):
```
1. (once) scaffold created openspec/coordination/ + a workset <project>
2. Parent : cp openspec/coordination/_template.md openspec/coordination/<feature>.md ; fill shared design/decisions
3. Per stack (parallel), each soft-tagged to the feature:
     openspec new change <name> --goal "<feature>"
4. Implement each in its own stack (cross-domain ban unchanged; frontend mocks first (web frontends; mini-program may connect to real test backend per H3 notes)).
   Cross-stack handoffs/sequencing live in openspec/coordination/<feature>.md (design/decisions).
5. Gate: feature done = ALL registered changes verify PASS (openspec/verify.config.yaml) -> archive each.
   Open all stacks: openspec workset open <project> --tool code  (IDE; 1.6.0 temporarily disables agent open -
   for a coordinator agent session, launch codex/claude manually in the project root).
```

> Separate repos (each stack its own OpenSpec root): register and address them with stores -
> `openspec store register --id <project>-<stack> <repo>` then `openspec new change <name> --goal "<feature>" --store <project>-<stack>`.

## Subagent-Driven Development (SDD)

When a change has many tasks or cross-module dependencies, the apply phase can dispatch
**subagents** instead of implementing everything in-context. This prevents context bloat
and enforces per-task accountability.

### Execution Modes (selected during propose phase)

| Mode | When | How |
|:--|:--|:--|
| **Inline** | <=3 tasks, no cross-module deps | Implement directly in-context (no subagent) |
| **Batch Inline** | >3 tasks, same module, no risk indicators | Implement sequentially in-context (no subagent dispatch) |
| **SDD** | Cross-module deps, >3 tasks, risk indicators | Dispatch implementer subagent per task, then reviewer subagent |

### SDD Workflow (when execution_mode: SDD)

```
For each task batch (from execution-contract.md):
  1. Dispatch Implementer subagent
     - CC: Task tool with openspec/sdd/implementer-prompt.md template
     - Codex: role-switch to Implementer role
     - Fill: [task name], [BRIEF_FILE], [directory], [REPORT_FILE], [MODEL]
  2. Implementer does: TDD (RED->GREEN->REFACTOR) or characterization/debt
     -> commit -> self-review -> report DONE|BLOCKED|NEEDS_CONTEXT
  3. On DONE: dispatch Reviewer subagent
     - CC: Task tool with openspec/sdd/reviewer-prompt.md template
     - Codex: role-switch to Reviewer role
     - Reviewer checks: spec compliance + code quality + tests -> Approved|Needs fixes
  4. Update openspec/sdd/progress.md (status, commits, review verdict)
  5. On BLOCKED/NEEDS_CONTEXT: escalate to user (retry cap 2b applies)
  6. On "Needs fixes": re-dispatch Implementer with reviewer feedback
```

### Frontend-Backend Subagent Coordination

For cross-stack features (e.g. frontend + backend), SDD works alongside the multi-stack
coordination layer:

- **Each stack dispatches its own implementer subagents** (cross-domain ban unchanged).
- The **execution-contract.md** defines task batches per stack and inter-stack dependencies.
- **Frontend implementer** mocks APIs from `openspec/specs/api/spec.md` (MSW) before
  backend is ready (web frontends; mini-program may connect to real test backend per H3 notes); **backend implementer** implements to the same spec.
- The **Coordinator** (root AGENTS.md role) tracks both stacks' progress via
  `openspec/sdd/progress.md` and the coordination doc registry (`openspec/coordination/<feature>.md`).
- **Cross-stack gate**: feature is done only when ALL registered changes verify PASS
  (not just one stack's tasks).

### SDD Artifacts (generated by scaffold)

| File | Purpose |
|:--|:--|
| `openspec/sdd/implementer-prompt.md` | Template for dispatching implementer subagents |
| `openspec/sdd/reviewer-prompt.md` | Template for dispatching reviewer subagents |
| `openspec/sdd/progress.md` | Per-task progress ledger (status, commits, review verdict) |

## OpenSpec ⇄ Superpowers Trigger

`openspec init` generates command files that pre-wire the Superpowers trigger:

```
/opsx:propose add-feature
  → Harness reads .claude/commands/opsx:propose
  → command file says "activate Superpowers brainstorming"
  → Superpowers brainstorm skill auto-triggers
  → AI asks clarifying questions (TDD flow begins)
```

For UI/page work on new pages, insert a `design` step before `/opsx:apply`: build an HTML prototype first (existing-page edits skip). Two paths - ① code-first: write HTML/CSS (or React+Tailwind/shadcn) directly → render in `browser` → `screenshot` self-check (fastest for simple pages/prototypes); ② `frontend-app-builder` skill: Claude as senior frontend designer → Image Gen visual concept → user confirms → faithful code impl → `browser` + `view_image` compare to 10/10 (no Figma). Main stack: `build-web-apps` (`frontend-app-builder` + `shadcn-best-practices`) + `browser` + `screenshot`; default HTML/CSS for static/single-file, React+Vite only for complex apps.

This is the integration protocol between OpenSpec and Superpowers - the "loop" in Loop Engineering: propose → plan → design(UI) → execute → review → verify → archive.
