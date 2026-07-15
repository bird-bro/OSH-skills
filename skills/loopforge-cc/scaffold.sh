#!/usr/bin/env bash
# loopforge scaffold - complete LoopForge project generator
# OpenSpec (WHAT) + Superpowers (HOW) + Harness (WHO)
#
# Subcommands:
#   scaffold.sh <name> [options]   generate a complete framework (default)
#   scaffold.sh list   [options]   preview the file manifest without writing
#   scaffold.sh check  [project]   self-check (env + script) + LoopForge compliance audit
#   scaffold.sh changes [project]  list all changes and their phase/status
#   scaffold.sh doctor  [project]  health check: deps, scaffold, guard, verify config
#
# Non-destructive: existing files are skipped (safe to re-run).
set -euo pipefail

PROJECT_NAME=""
STACKS="backend,frontend"
TARGET_DIR=""
BACKEND_DIR="backend"
FRONTEND_DIR="frontend-web"
MOBILE_DIR="frontend-mobile"
RUN_INIT=1
TOOLS="claude"
# CJK char ratio (%) above which an auto-loaded .md is flagged Chinese (O7 check + tokens).
# Override per-run: CJK_THRESHOLD=5 ./scaffold.sh check ./myapp
CJK_THRESHOLD="${CJK_THRESHOLD:-10}"
# Token budget threshold per auto-loaded .md (estimated tokens). S9 check flags files above this.
# Override per-run: TOKEN_THRESHOLD=2000 ./scaffold.sh check ./myapp
TOKEN_THRESHOLD="${TOKEN_THRESHOLD:-3000}"
# LoopForge version - written into generated projects for traceability.
LOOPFORGE_VERSION="${LOOPFORGE_VERSION:-2.1.0}"

usage() {
  cat <<'USG'
Usage: scaffold.sh <subcommand|project-name> [options]

Subcommands:
  (default) <project-name>   Generate a complete Loop Engineering framework
  list        [options]      Preview the file manifest without writing anything
  check       [project-dir]  Self-check (env + script) and LoopForge compliance audit
  tokens      [project-dir]  Token audit of auto-loaded files (O7 overhead)
  validate    <change-dir>   Validate artifact structure (proposal/spec/design/tasks)
  changes     [project-dir]  List all changes and their phase/status
  doctor      [project-dir]  Health check: deps, scaffold, guard, verify config
  version                    Print LoopForge version
  contract    <change-dir>   Auto-generate execution-contract.md from artifacts
  restructure [project-dir]  Analyze monolithic CLAUDE.md and plan per-stack split

Generate options:
  --stacks <list>      comma list: backend,frontend,frontend-mobile (default: backend,frontend)
  --dir <path>         target directory (default: ./<project-name>)
  --backend-dir <n>    backend code dir name (default: backend)
  --frontend-dir <n>   web frontend dir name (default: frontend-web)
  --mobile-dir <n>     mobile frontend dir name (default: frontend-mobile)
  --tools <list>       AI tool(s) for openspec init, comma list (default: claude)
  --no-init            do not run `openspec init` (init separately later)
  -h, --help           show this help

Examples:
  scaffold.sh myapp
  scaffold.sh myapp --stacks backend,frontend,frontend-mobile
  scaffold.sh list --stacks backend,frontend
  scaffold.sh check ./myapp
  scaffold.sh check                 # self-check only
  scaffold.sh tokens ./myapp      # token audit of auto-loaded files
  scaffold.sh validate ./myapp/openspec/changes/add-login  # validate change artifacts
  scaffold.sh changes ./myapp     # list all changes and their status
  scaffold.sh doctor ./myapp      # health check
  scaffold.sh version             # print version
  scaffold.sh contract ./myapp/openspec/changes/add-login  # auto-generate execution-contract.md
  scaffold.sh contract --force ./myapp/openspec/changes/add-login  # overwrite existing contract
  scaffold.sh restructure ./myapp  # analyze monolithic CLAUDE.md for per-stack split
USG
}

# ---------------- helpers ----------------
has() { [[ ",$STACKS," == *",$1,"* ]]; }

dir_for() {
  case "$1" in
    backend)          echo "$BACKEND_DIR";;
    frontend)         echo "$FRONTEND_DIR";;
    frontend-mobile)  echo "$MOBILE_DIR";;
  esac
}

label_for() {
  case "$1" in
    backend)          echo "Backend Agent";;
    frontend)         echo "Frontend Web Agent";;
    frontend-mobile)  echo "Frontend Mobile Agent";;
  esac
}

# write_if_absent <path>  - reads body from stdin; skips if file exists
write_if_absent() {
  local f="$1"
  if [[ -f "$f" ]]; then
    cat > /dev/null  # drain stdin so upstream producer (sed/cat) does not SIGPIPE under pipefail
    echo "  skip (exists): $f"
  else
    mkdir -p "$(dirname "$f")"
    cat > "$f"
    echo "  create: $f"
  fi
}

# write_both <path1> <path2> - reads body from stdin; writes to both (skips existing per file)
write_both() {
  local body; body=$(cat)
  printf '%s\n' "$body" | write_if_absent "$1"
  printf '%s\n' "$body" | write_if_absent "$2"
}

# inject_after_frontmatter <file> <marker>  - reads block from stdin; inserts it right after
# the YAML frontmatter closing '---'. Idempotent (skips if <marker> present). No-op if file missing.
inject_after_frontmatter() {
  local file="$1" marker="$2" block
  [[ -f "$file" ]] || { cat >/dev/null; echo "  skip (not generated yet): ${file#./} - run 'openspec init' first"; return 0; }
  grep -qF "$marker" "$file" && { cat >/dev/null; echo "  skip (embedded): ${file#./}"; return 0; }
  block="$(cat)"
  block="$block" awk '
    NR==1 && /^---[[:space:]]*$/ { print; fm=1; next }
    fm && /^---[[:space:]]*$/ { print; print ""; print ENVIRON["block"]; fm=0; done=1; next }
    { print }
    END { if (!done) { print ""; print ENVIRON["block"] } }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  echo "  embed: ${file#./}"
}

# autoloaded_md - print paths of auto-loaded .md in cwd (root + per-stack CLAUDE.md/AGENTS.md + .claude/rules/*.md)
autoloaded_md() {
  [[ -f CLAUDE.md ]] && printf '%s\n' CLAUDE.md
  [[ -f AGENTS.md ]] && printf '%s\n' AGENTS.md
  local d
  for d in */; do
    [[ -f "${d}CLAUDE.md" ]] && printf '%s\n' "${d}CLAUDE.md"
    [[ -f "${d}AGENTS.md" ]] && printf '%s\n' "${d}AGENTS.md"
  done
  find .claude/rules -name '*.md' 2>/dev/null || true
}

subst() { sed -e "s/@@PROJECT_NAME@@/$PROJECT_NAME/g" \
              -e "s/@@BACKEND_DIR@@/$BACKEND_DIR/g" \
              -e "s/@@FRONTEND_DIR@@/$FRONTEND_DIR/g" \
              -e "s/@@MOBILE_DIR@@/$MOBILE_DIR/g" \
              -e "s/@@LOOPFORGE_VERSION@@/$LOOPFORGE_VERSION/g" \
              -e "s/@@WS_NAME@@/$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr '_' '-')/g"; }

# ---------------- generation core (reused by scaffold + list) ----------------
generate_scaffold() {
  echo "==> Loop Engineering scaffold: $PROJECT_NAME"
  echo "    target: $TARGET_DIR"
  echo "    stacks: $STACKS"
  mkdir -p "$TARGET_DIR"
  cd "$TARGET_DIR"

  # ---------- 0. openspec init (generates openspec/, .claude/commands/, base skills) ----------
  if [[ $RUN_INIT -eq 1 ]]; then
    if command -v openspec >/dev/null 2>&1; then
      echo "==> Running: openspec init --tools $TOOLS"
      openspec init --tools "$TOOLS" || echo "  warn: openspec init failed or already initialized"
    else
      echo "  warn: openspec CLI not found."
      echo "        install: npm i -g @fission-ai/openspec@latest"
      echo "        then run 'openspec init' in $TARGET_DIR"
    fi
  fi


  # ---------- 0b. LoopForge runtime enhancements (/opsx:verify command + Superpowers triggers) ----------
  # openspec init ships 5 commands (propose/apply/archive/sync/explore) but NOT /opsx:verify, and the
  # generated propose/apply/archive are plain CLI flows with no Superpowers trigger / verify gate.
  # LoopForge layers these on so the documented loop (propose->apply->verify->archive) is real.
  echo "==> Layering LoopForge runtime enhancements (verify config + report template; Claude commands + Codex skills)"
  # Capture verify body once - shared between Claude slash command and Codex skill.
  # openspec init (v1.6.0) generates propose/apply/archive/explore/sync only - NO verify
  # command/skill in any --tools mode. LoopForge creates it for both Claude and Codex.
  _LOOP_VERIFY_BODY=$(mktemp)
  cat > "$_LOOP_VERIFY_BODY" <<'__LOOPFORGE_VERIFY_BODY__'
Three-layer verification for an OpenSpec change. Confirms the implementation actually satisfies the spec's WHEN/THEN scenarios, then writes a `verify.md` credential into the change directory that `/opsx:archive` checks before archiving.

**The three layers**

| Layer | What it checks | How |
|:--|:--|:--|
| **L1 Build** | Code compiles / builds | Runs each affected stack's build command |
| **L2 Spec alignment** | Code implements the spec's WHEN/THEN scenarios | Reviewer-style audit: per scenario, find code evidence, score IMPLEMENTED / PARTIAL / NOT_IMPLEMENTED |
| **L3 Tests** | Existing test suite passes | Runs each affected stack's test command (SKIP if none) |

**Overall status** (written into `verify.md`, read by `/opsx:archive`)

| Overall | Rule | Archive |
|:--|:--|:--|
| `PASS` | L1 + L3 pass, every scenario IMPLEMENTED | ✅ direct |
| `PASS_WITH_ISSUES` | L1 + L3 pass, ≥1 scenario PARTIAL | ⚠ confirm first |
| `FAIL` | any L1 build failed / any L3 test failed / any scenario NOT_IMPLEMENTED | ❌ fix first |
| `NOT_RUN` | no verify.md yet | ⚠ archive warns |

---

**Input**: Optionally specify a change name (e.g., `/opsx:verify add-auth`). If omitted, check if it can be inferred from conversation context. If vague or ambiguous you MUST prompt for available changes.

**Steps**

1. **Select the change**

   If a name is provided, use it. Otherwise:
   - Infer from conversation context if the user mentioned a change
   - Auto-select if only one active change exists
   - If ambiguous, run `openspec list --json` to get available changes and use the **AskUserQuestion tool** to let the user select

   Always announce: "Using change: <name>" and how to override (e.g., `/opsx:verify <other>`).

2. **Resolve change context**

   ```bash
   openspec status --change "<name>" --json
   ```

   Parse the JSON for:
   - `changeRoot` - where to write `verify.md`
   - `artifactPaths.specs.existingOutputPaths` - delta spec files holding the WHEN/THEN scenarios (the L2 source of truth)
   - `root.path` (or `actionContext.allowedEditRoots[0]`) - project root, to locate `openspec/verify.config.yaml` (see step 4) and per-stack `CLAUDE.md`
   - `actionContext.allowedEditRoots` / stack hints - which stacks are affected

   **Scope guard:** `actionContext.mode` is `repo-local` for normal changes (OpenSpec 1.6.0 removed the `workspace-planning` mode). If a change spans multiple stacks, identify all affected stacks from `allowedEditRoots`, the change's `design.md`, or `tasks.md` stack tags - do not run builds against stacks the change does not touch.

3. **Validate artifacts first (fail fast)**

   ```bash
   openspec validate "<name>" --json
   ```

   If validation reports malformed specs/tasks, STOP and report - there is no point verifying against a broken spec. Suggest `/opsx:propose` to fix the spec.

4. **Load the verify config (build & test commands per stack)**

   Resolution order (use the first that yields commands):
   a. **`openspec/verify.config.yaml`** (project-level, authoritative). Schema:
      ```yaml
      stacks:
        <stack-id>:
          dir: <stack-dir>        # relative to project root
          build: <build-cmd>      # L1
          test: <test-cmd> | null # L3; null or omitted => SKIP
      ```
   b. **Infer from per-stack `CLAUDE.md`** - read each affected stack's `CLAUDE.md`, extract commands from its `## Build Commands` (→ L1) and `## Test` (→ L3) sections.
   c. **Ask once and persist** - use the **AskUserQuestion tool** to ask for the build (and optional test) command per affected stack, then write the answers to `openspec/verify.config.yaml` so future runs are deterministic.

   Identify **affected stacks** from: status JSON `allowedEditRoots`, the change's `design.md`, or `tasks.md` stack tags. If only one stack exists, use it.

5. **L1 - Build check (per affected stack)**

   For each affected stack, run its build command **inside that stack's `dir`**:
   ```bash
   cd "<stack-dir>" && <build-cmd>
   ```
   - Capture exit code and tail of output.
   - Record `L1 = PASS` (exit 0) or `L1 = FAIL` (non-zero) with the failing output.
   - If a stack has no build command, record `L1 = SKIP`.

6. **L2 - Spec alignment (reviewer-style, agent-driven)**

   This is the core layer. It is NOT a CLI call - it is a semantic audit you perform.

   a. **Read every delta spec** from `artifactPaths.specs.existingOutputPaths`. Extract each `## Scenario:` block and its WHEN/THEN clauses. These scenarios ARE the verification cases.
   b. **For each scenario**, search the affected stacks' code for implementation evidence:
      - Use `rg` to find the code path(s) the scenario describes (e.g., a route handler, a component, a service method).
      - Read the matched code to confirm it actually fulfills the WHEN/THEN.
      - **Honor `verify-meta`**: if the scenario carries an HTML comment such as
        `<!-- verify-meta: { "endpoint": "POST /api/repair", "expectedStatus": 201 } -->`,
        use the structured fields for a precise check (does that exact route exist? does it return that status?). Absent `verify-meta`, fall back to semantic matching.
      - **Cross-domain rule**: a backend scenario is checked against backend code only; a frontend scenario against frontend code only. Never cite a frontend file as evidence for a backend scenario, and vice versa.
   c. **Score each scenario**:
      - `✓ IMPLEMENTED` - clear, working evidence found → cite `file:line`
      - `⚠ PARTIAL` - partial / fragile / missing edge case → cite what's there and what's missing
      - `✗ NOT_IMPLEMENTED` - no evidence found → state what the spec requires vs. what exists
   d. Tally: `N/M scenarios implemented`.

7. **L3 - Test execution (per affected stack)**

   For each affected stack with a non-null test command, run it inside that stack's `dir`:
   ```bash
   cd "<stack-dir>" && <test-cmd>
   ```
   - Record `L3 = PASS` (exit 0) with pass/fail counts, or `L3 = FAIL` with the failing test names.
   - Stacks with `test: null` record `L3 = SKIP` (e.g., "仅 stack-a 有 Vitest，其他子项目报 SKIP").

8. **Compute overall status**

   Apply in order (first match wins):
   - `FAIL` if any L1 = FAIL **or** any L3 = FAIL **or** any scenario = NOT_IMPLEMENTED
   - `PASS_WITH_ISSUES` if L1 + L3 all pass/SKIP **and** ≥1 scenario = PARTIAL
   - `PASS` if L1 + L3 all pass/SKIP **and** every scenario = IMPLEMENTED
   - (NOT_RUN is only the pre-verify state; once you run, the result is one of the above three.)

9. **Write `verify.md` to `<changeRoot>/verify.md`**

   This file is the archive credential. Use the template in `openspec/verify-result.template.md`. Its YAML frontmatter MUST be machine-readable because `/opsx:archive` parses `overall` from it:
   ```yaml
   ---
   verify:
     change: <name>
     date: YYYY-MM-DD
     overall: PASS | PASS_WITH_ISSUES | FAIL
     stacks:
       <stack-id>:
         L1: PASS | FAIL | SKIP
         L2: "<implemented>/<total>"
         L3: PASS | FAIL | SKIP
   ---
   ```
   Followed by the human-readable tables (per-stack L1/L2/L3 + scenario alignment detail + issues).

10. **Display the report and suggest the next action**

    Match the report format below. Then:
    - `FAIL` → list blocking issues, suggest `/opsx:apply <name>` to fix
    - `PASS_WITH_ISSUES` → list PARTIALs, ask "要我修复吗?" → if yes, hand off to `/opsx:apply`
    - `PASS` → suggest `/opsx:archive <name>`

**Output (report)**

```
## 验证结果: <change-name>

### <stack-id>
| 层级 | 状态 | 详情 |
|:---|:---|:---|
| L1 构建 | ✓ PASS | <build-cmd> 成功 |
| L2 规格对齐 | 5/6 已实现 | 1 PARTIAL |
| L3 测试 | ✓ PASS | 4/4 测试通过 |

### 场景对齐详情
| 场景 | 状态 | 证据 |
|:---|:---|:---|
| 提交报修单 | ✓ 已实现 | repair.vue:42-58 |
| 提交后刷新列表 | ⚠ PARTIAL | 缺少刷新逻辑 |

总体: PASS_WITH_ISSUES
要我修复那个 PARTIAL 吗?
```

**Guardrails**
- `verify.md` is the single source of truth for verification status - always (over)write it at the end, even on FAIL, so the record is honest.
- Never mark a scenario IMPLEMENTED without a concrete `file:line` evidence citation.
- Never run a build/test command outside its stack's `dir`.
- Never let backend evidence satisfy a frontend scenario or vice versa (cross-domain prohibition).
- L2 is judgment work - if you cannot find evidence, score NOT_IMPLEMENTED and say so; do not guess.
- If `verify.config.yaml` is missing, create it from the first run so subsequent runs are deterministic (do not re-ask).
- Do not modify any source code during verify - verification is read/execute only. Fixes belong to `/opsx:apply`.

**Fluid Workflow Integration**
- Re-runnable any number of times; each run overwrites `verify.md`.
- After a `/opsx:apply` fix, re-run `/opsx:verify` to refresh the credential before archiving.
__LOOPFORGE_VERIFY_BODY__

  mkdir -p .claude/commands/opsx
  { cat <<'__FM_CLAUDE__'
---
name: "OPSX: Verify"
description: Three-layer verification (L1 build / L2 spec alignment / L3 tests) for a change - writes verify.md as the archive credential
category: Workflow
tags: [workflow, verification, experimental]
---

__FM_CLAUDE__
    cat "$_LOOP_VERIFY_BODY"
  } | write_if_absent .claude/commands/opsx/verify.md

  rm -f "$_LOOP_VERIFY_BODY"

  # Generate verify.config.yaml dynamically from configured stacks.
  # Respects --backend-dir / --frontend-dir / --mobile-dir; each enabled stack
  # gets a sensible default build/test command the user can customise later.
  {
    cat <<'__VC_HEADER__'
# OpenSpec verify configuration
# /opsx:verify reads L1 (build) and L3 (test) commands from here.
# Place at: <project>/openspec/verify.config.yaml
#
# - `build` is required for L1; omit/leave null to SKIP L1 for a stack.
# - `test`  is optional for L3; omit/leave null to SKIP L3 (report SKIP, not FAIL).
# - `dir` is the stack directory relative to the project root; builds/tests run there.

stacks:
__VC_HEADER__
    if has backend; then
      cat <<EOF
  ${BACKEND_DIR}:
    dir: ${BACKEND_DIR}
    build: mvn compile -q
    test: mvn test -q
EOF
    fi
    if has frontend; then
      cat <<EOF
  ${FRONTEND_DIR}:
    dir: ${FRONTEND_DIR}
    build: pnpm build
    test: null                 # no test runner -> L3 SKIP (set to pnpm test if Vitest exists)
EOF
    fi
    if has frontend-mobile; then
      cat <<EOF
  ${MOBILE_DIR}:
    dir: ${MOBILE_DIR}
    build: pnpm build
    test: null                 # no test runner -> L3 SKIP
EOF
    fi
  } | write_if_absent openspec/verify.config.yaml

  cat <<'__LOOPFORGE_VERIFY_TPL__' | write_if_absent openspec/verify-result.template.md
<!--
  Written by /opsx:verify. This file is the archive credential - /opsx:archive
  parses the `overall` field below. Do not hand-edit; re-run /opsx:verify to refresh.
-->
---
verify:
  change: CHANGE_NAME
  date: YYYY-MM-DD
  overall: PASS_WITH_ISSUES   # PASS | PASS_WITH_ISSUES | FAIL
  stacks:
    STACK_ID:
      L1: PASS                 # PASS | FAIL | SKIP
      L2: "5/6"                # implemented/total scenarios
      L3: PASS                 # PASS | FAIL | SKIP
---

# 验证结果: CHANGE_NAME

> 生成时间: YYYY-MM-DD · 总体: **PASS_WITH_ISSUES**

## STACK_ID

| 层级 | 状态 | 详情 |
|:---|:---|:---|
| L1 构建 | ✓ PASS | <build-cmd> 成功 |
| L2 规格对齐 | 5/6 已实现 | 1 PARTIAL |
| L3 测试 | ✓ PASS | 4/4 测试通过 |

## 场景对齐详情

| 场景 | 状态 | 证据 |
|:---|:---|:---|
| 提交报修单 | ✓ 已实现 | repair.vue:42-58 |
| 提交后刷新列表 | ⚠ PARTIAL | 缺少刷新逻辑 |

## 发现的问题

⚠ PARTIAL: "提交后刷新列表"
- 期望: 提交报修单后列表自动刷新
- 实际: repair.vue 提交成功后未调用列表刷新
- 建议: 提交回调中 emit 事件或调用 store.refresh()

## 下一步

- PASS → `/opsx:archive CHANGE_NAME`
- PASS_WITH_ISSUES → 确认后归档，或 `/opsx:apply CHANGE_NAME` 修复 PARTIAL
- FAIL → `/opsx:apply CHANGE_NAME` 修复阻断项后重新 `/opsx:verify`
__LOOPFORGE_VERIFY_TPL__

  # ---------- MOD-2': worktree isolation gate (ported from spec-superflow ensure-branch.mjs) ----------
  cat <<'__LOOPFORGE_ENSURE__' | write_if_absent openspec/ensure-branch.sh
#!/usr/bin/env bash
# openspec/ensure-branch.sh - enforce git isolation before editing main/master.
# Ported from spec-superflow ensure-branch.mjs (MIT) + legacy git-state resilience.
# Usage: bash openspec/ensure-branch.sh [change-name] [--force]
set -euo pipefail
change_name="${1:-}"; force=0
for a in "$@"; do [[ "$a" == "--force" ]] && force=1; done

# --- legacy resilience: degrade instead of hard-fail on non-standard states ---
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "ensure-branch: not a git repo - no isolation possible, proceed with caution" >&2; exit 0; }
branch="$(git branch --show-current 2>/dev/null || true)"
if [[ -z "$branch" ]]; then
  echo "ensure-branch: detached HEAD. WARN: switch to a branch before editing (git switch -c <change-name>). Proceeding without isolation." >&2; exit 0; fi

case "$branch" in main|master) ;; *)
  echo "ensure-branch: already on branch '$branch'. Proceed." >&2; exit 0 ;; esac

echo "ensure-branch: on protected branch '$branch'. Creating an isolated context..." >&2
repo_name="$(basename "$PWD")"; name="${change_name:-$repo_name}"; wt_path="../${repo_name}-${name}"
if git worktree add "$wt_path" -b "$name" 2>/dev/null; then
  echo "ensure-branch: created worktree at $wt_path on branch '$name'. Edit there." >&2; exit 0; fi
echo "ensure-branch: worktree failed, trying local branch..." >&2
if git switch -c "$name" 2>/dev/null; then
  echo "ensure-branch: created branch '$name'. Edit there." >&2; exit 0; fi
if [[ $force -eq 1 ]]; then
  echo "ensure-branch: WARNING - editing protected branch in place with --force." >&2; exit 0; fi
echo "ensure-branch: could not isolate and no --force. STOP and ask the user." >&2; exit 1
__LOOPFORGE_ENSURE__
  chmod +x openspec/ensure-branch.sh 2>/dev/null || true

  cat <<'__LOOPFORGE_TRIG__' | inject_after_frontmatter .claude/commands/opsx/propose.md '<!-- LoopForge: superpowers-trigger-propose -->'
<!-- LoopForge: superpowers-trigger-propose -->
## Superpowers Integration (auto-triggered - LoopForge loop start)

Before writing artifacts, ground the spec in real requirements:
1. **Activate `brainstorm`** - clarify goals/scope/edge cases with the user; ask questions; do NOT write the proposal until the user confirms understanding.
2. **Use `writing-plans`** - structure confirmed requirements into proposal/design/tasks/spec; write concrete WHEN/THEN scenarios (these become /opsx:verify L2 cases later).
3. Then proceed to the `openspec new change` / `openspec status` / `openspec instructions` steps below.

> If Superpowers skills are not installed, apply the same discipline manually (loopforge scaffold lists them as separate skills to install).
4. **Build execution-contract.md (file-level bridge - mandatory before apply):** after proposal.md + specs/*/spec.md + design.md + tasks.md are written:
   - **Auto-generate (recommended):** run `bash openspec/build-contract.sh <change-dir>` to scaffold the contract from planning artifacts (extracts Intent Lock from proposal.md, Approved Behavior from specs/ WHEN/THEN, Design Constraints from design.md, Task Batches from tasks.md). Or use `scaffold.sh contract <change-dir>`.
   - **Manual fallback:** copy `openspec/changes/_template/execution-contract.md` to the change directory and fill it yourself.
   - Either way: review AI-marked sections (`<!-- AI: ... -->`), fill Test Obligations from TDD/characterization analysis.
   - Select execution mode: <=3 tasks and no cross-module deps -> Inline; >3 tasks same module and no risk indicators -> Batch Inline; else -> SDD.
   - Run `bash openspec/ensure-contract-fresh.sh --update <change-dir>` to store the artifacts hash.
   - Update `openspec/loop-state.yaml`: set `execution_mode: <mode>`.
   - **DP-3 (Approval Gate):** summarize the contract and ask the user for explicit approval. No implementation without approval.
5. **Phase gate (propose -> apply - programmatic):** run `bash openspec/guard.sh proposing applying <change-dir>`. Non-zero exit -> STOP. This checks: artifacts exist + schema valid + contract fresh. On PASS, update `loop-state.yaml`: set `phase: applying`, `change: <name>`.

## Legacy Characterization (when modifying existing un-specced code)
If the change touches code with NO existing spec in `openspec/specs/`:
1. Before the forward spec, write a CHARACTERIZATION spec: describe what the code
   CURRENTLY does as WHEN/THEN (observed, not desired). These are regression baselines.
2. Mark them `## Scenario (characterization):` so verify L2 treats them as
   regression guards (must still pass) vs `## Scenario:` (new behavior, must be achieved).
3. If existing behavior cannot be safely captured (no test harness), record in
   `openspec/changes/<change>/debt.md` instead - do not guess.
<!-- /LoopForge: superpowers-trigger-propose -->
__LOOPFORGE_TRIG__

  cat <<'__LOOPFORGE_TRIG__' | inject_after_frontmatter .claude/commands/opsx/apply.md '<!-- LoopForge: superpowers-trigger-apply -->'
<!-- LoopForge: superpowers-trigger-apply -->
## Superpowers Integration (auto-triggered - TDD discipline + hard gates)

**Fast-path mode detection (runs before preflight):**
Read `tasks.md` in the change directory. Count tasks and assess scope:
- **tweak** (<=4 tasks, ALL config/doc/.env/.yml/.json/.md files, no source code): skip contract (0a) + TDD (2). Edit directly. L1 build check (4) still applies. Verify = L1 only.
- **hotfix** (<=2 tasks, <=2 source files, no new schema/API/module): contract relaxed (minimal intent lock OK, skip full contract if <change>/execution-contract.md absent). TDD (2) applies, characterization allowed. Full verify.
- **full** (anything larger): normal flow - all steps apply.
If unsure, default to `full`. Persist: set `workflow_mode: <tweak|hotfix|full>` in `loop-state.yaml`. State the mode before proceeding.

0. **Preflight (mandatory, before ANY implementation edit):**
   a. **Contract freshness:** run `bash openspec/ensure-contract-fresh.sh <change-dir>`. Non-zero exit -> STOP (spec changed since contract was generated; re-run propose to regenerate the contract and update the hash).
   b. **Worktree isolation:** run `bash openspec/ensure-branch.sh <change-name>`. Non-zero exit -> STOP, do NOT edit main/master in place; ask the user (re-run with `--force` only after they agree). (Legacy repos: the script warns + proceeds on detached/non-repo states - it will not block you there, but prefer creating a branch.)
1. **Activate `executing-plans`** before coding - tasks in order, smallest scope first.
2. **TDD Iron Law (legacy-aware) - no production code without a failing OR characterization test first.**
   Read the affected stack `test` field in `openspec/verify.config.yaml`:
   - **If `test` is set (test runner exists):** strict RED -> GREEN -> REFACTOR.
     Write a failing test for the task WHEN/THEN; run it; confirm FAIL (`✓ Red 确认`).
     If it passes unexpectedly -> test is wrong or behavior exists; STOP, investigate.
     Then write minimum code; confirm GREEN (`✓ Green`); refactor; keep green.
     Red flags (all = STOP, write test first): "先快速实现回头补测试" / "跳过测试手动验证" /
     "我知道它能跑" / "就这一次不写测试".
   - **If `test` is null (legacy module, no runner):** characterization mode - do ONE of:
     (a) write a characterization test locking CURRENT behavior (run it; snapshot baseline,
         pass or fail either is the record); OR
     (b) append to `openspec/changes/<change>/debt.md`: `- [DEBT] <task>: no harness for
         <stack>; changed <what>; risk <low|med|high>` and mark the task `DEBT` in tasks.md.
     NEVER silently change legacy code with neither a test nor a debt record.
2b. **Retry cap (3-strike) -> debugging side-path:** if a task build/test FAILs, attempt a fix and increment `retry_count` in `openspec/loop-state.yaml`. If `retry_count >= 3` for the SAME task -> enter **debugging phase** (do NOT keep blind-retrying):
   - Update `loop-state.yaml`: set `phase: debugging`, increment `debug_attempts`.
   - **Debug protocol (4 steps):**
     (a) **Reproduce**: write a minimal reproducer (test or script) that reliably triggers the failure. If you cannot reproduce it, you cannot fix it - say so.
     (b) **Root cause**: use `git bisect` or binary-search the change to find what introduced the issue. Read the failing code path end-to-end. State the root cause in one sentence.
     (c) **Minimal fix**: fix ONLY the root cause - no refactoring, no new features. Smallest change that makes the reproducer pass.
     (d) **Regression guard**: add a test covering the root cause scenario (or append to debt.md if legacy). Run full suite to confirm no regressions.
   - After debugging: set `phase: applying`, reset `retry_count: 0`, reset `debug_attempts: 0`. If debugging reveals spec/contract is wrong -> rewind to `proposing` (see 2c).
   - If `debug_attempts >= 2` for the SAME task -> STOP, escalate to user: architecture or spec assumption is likely wrong.
   Reset `retry_count` to 0 when moving to the next task.
2c. **Mandatory Rewind:** if new scope appears, interfaces change materially, or design assumptions fail during implementation -> rewind to `proposing`, update the spec, then resume. Never patch the spec inside `applying` via ad-hoc chat. Update `loop-state.yaml`: set `phase: proposing`.
2d. **SDD Execution (when execution_mode: SDD):** for each task batch:
   - Dispatch an implementer subagent using `openspec/sdd/implementer-prompt.md` template
     (CC: Task tool; Codex: role-switch to Implementer). Fill placeholders: [task name],
     [BRIEF_FILE], [directory], [REPORT_FILE], [MODEL].
   - **Model selection** (choose per role, always specify explicitly):
     | Role | Model tier | When to use |
     |:--|:--|:--|
     | Implementer (mechanical) | cheap/fast | Single-file CRUD, config, boilerplate, formatting |
     | Implementer (integration) | standard | Multi-file, API wiring, cross-module, state changes |
     | Implementer (architecture) | capable | New module, schema design, refactor, algorithmic |
     | Reviewer | match implementer or +1 | Review diff against spec WHEN/THEN |
     | Final review | most capable | Cross-batch coherence, spec drift, architecture check |
     If unsure, default to standard. For legacy characterization tests, mechanical suffices.
   - On DONE: dispatch a reviewer subagent using `openspec/sdd/reviewer-prompt.md`.
   - Update `openspec/sdd/progress.md` after each task (status, commits, review verdict).
   - On BLOCKED/NEEDS_CONTEXT: escalate to user; do not auto-retry (retry cap 2b applies).
   - For Batch Inline mode: implement tasks sequentially in-context (no subagent dispatch).
   - For Inline mode: implement directly (no subagent, no batch).
3. After each task code change: **`code-review`** the diff against the spec WHEN/THEN.
4. **Per-task build check (L1 quick verify):** after the code change, before marking the task done, run the affected stack build command from `openspec/verify.config.yaml` inside that stack dir. On PASS print `✓ 构建检查通过`; on FAIL do NOT mark done - pause and report. (Reuses the same config as /opsx:verify - one source of truth.)
5. On full completion: **`verification-before-completion`**, then suggest `/opsx:verify <change>` (not archive directly).
6. **Phase gate (apply -> verify - programmatic):** run `bash openspec/guard.sh applying verifying <change-dir>`. Non-zero exit -> STOP. This checks: tasks complete + contract fresh. On PASS, update `loop-state.yaml`: set `phase: verifying`.
<!-- /LoopForge: superpowers-trigger-apply -->
__LOOPFORGE_TRIG__

  cat <<'__LOOPFORGE_TRIG__' | inject_after_frontmatter .claude/commands/opsx/archive.md '<!-- LoopForge: verify-gate-archive -->'
<!-- LoopForge: verify-gate-archive -->
## Pre-archive Gate (verify credential - mandatory, runs before the archive move)

Check for `verify.md` in the change root:
- **Missing** -> warn "未找到 verify.md，该 change 尚未验证"; recommend `/opsx:verify "<name>"`; ask 否(推荐)/是; on 否 STOP.
- **overall: FAIL** -> block: print blocking issues, STOP, suggest `/opsx:apply` then `/opsx:verify`.
- **overall: PASS_WITH_ISSUES** -> warn PARTIALs, confirm before proceeding.
- **overall: PASS** -> proceed.

Read `verify.overall` from verify.md YAML frontmatter (written by /opsx:verify). Runs after the spec-sync assessment and before `mv` into archive/.
Phase gate: run `bash openspec/guard.sh verifying archived <change-dir>`. Non-zero exit -> STOP. On PASS, update `openspec/loop-state.yaml`: set `phase: archived`. On FAIL or abandon: set `phase: abandoned`.

## Delta-Spec Sync (after archive move - prevents spec rot)
After the change is moved to `archive/`, sync its delta specs into the main specs:
1. Read each `specs/*.md` (or `spec.md`) in the archived change directory.
2. For each delta spec scenario, merge into the corresponding `openspec/specs/<type>/spec.md`:
   - **New scenarios**: append to the main spec with their WHEN/THEN.
   - **Modified scenarios**: replace the old version, keep the scenario name.
   - **Removed scenarios**: mark `~~deprecated~~` (do not delete - preserve history).
3. Add a `<!-- synced from: <change-name> <date> -->` comment at each merge point.
4. `openspec archive` already updates main specs on archive (OpenSpec 1.6.0); the `openspec-sync-specs` skill can assist with manual merge review. (The standalone `openspec sync` CLI was removed in 1.6.0.)
5. Verify no conflicts: same scenario name with different WHEN/THEN in main spec -> warn user.
This ensures the main specs always reflect what was actually built, not what was planned.
<!-- /LoopForge: verify-gate-archive -->
__LOOPFORGE_TRIG__

  # ---------- 1. openspec/  (WHAT - shared truth) ----------
  echo "==> Creating openspec/ (WHAT)"
  mkdir -p openspec/specs openspec/changes/_template/specs/capability openspec/archive

  cat <<'EOF' | subst | write_if_absent openspec/README.md
# OpenSpec - Shared Truth (WHAT)

> Generated by LoopForge v@@LOOPFORGE_VERSION@@

This directory is the **single source of truth** for WHAT to build.

## Structure
- `specs/` - static contracts (`api/`, `data/`, `errors/`). Authoritative; all agents reference it.
- `changes/` - dynamic delta proposals (active work). Start from `_template/`.
- `archive/` - completed proposals (history).
- `project.md` - tech stack, module map, architecture (no coding conventions).

## Responsibility Separation
| Layer | Location | Role |
|:--|:--|:--|
| Spec (here) | `openspec/` | WHAT - shared truth |
| Discipline | `.claude/` | HOW - TDD, review, quality gates |
| Harness | `CLAUDE.md` + agents | WHO - roles, boundaries |

## Workflow
1. `/opsx:propose <change>` - brainstorm + write proposal (auto-triggers Superpowers)
2. `/opsx:apply` - implement per spec (TDD enforced)
3. `/opsx:archive` - move completed proposal to `archive/`
EOF

  cat <<'EOF' | subst | write_if_absent openspec/project.md
# Project Overview - @@PROJECT_NAME@@

## System
@@PROJECT_NAME@@ - [one-line business description]

## Tech Stack
| Layer | Tech |
|:--|:--|
| Backend | [e.g. Java 17 + Spring Boot 3 + MyBatis] |
| Frontend | [e.g. Vue 3 + Vite + Element Plus] |
| Database | [e.g. MySQL 8] |

## Module Map
[Directory tree of code modules]

## Architecture
[High-level architecture: layers, data flow, external integrations]

> No coding conventions here - those live in `.claude/rules/` and per-stack `CLAUDE.md`.
EOF

  cat <<'EOF' | write_if_absent openspec/specs/README.md
# Specs - Static Contracts

Authoritative contracts all agents must follow.
- `api/spec.md` - API contract (endpoints, request/response). Frontend mocks from it; backend implements to it.
- `data/spec.md` - data models, schemas.
- `errors/spec.md` - error codes, response format.

Every spec must include WHEN/THEN verification scenarios (executable acceptance criteria).
EOF

  cat <<'EOF' | write_if_absent openspec/specs/api/spec.md
# API Contract

## Purpose
Authoritative API contract. Frontend mocks from this; backend implements to this. Defines base URL, response envelope, and endpoint conventions.

## Requirements

### Requirement: API Response Envelope
All API responses MUST use the standard envelope `{ "code": 0, "data": {}, "message": "" }`. Base URL: `/api/v1`.

#### Scenario: Successful response
- **WHEN** a request succeeds
- **THEN** returns `code: 0` with the typed payload in `data`

#### Scenario: Error response
- **WHEN** a request fails
- **THEN** returns a non-zero `code` with an error `message` and `data: null`

### Requirement: Endpoint Documentation
Each endpoint MUST be documented as a Requirement with WHEN/THEN scenarios. Add new Requirements for each resource.

#### Scenario: Resource retrieval
- **WHEN** a client requests `GET /api/v1/[resource]`
- **THEN** returns `code: 0` with `[payload]`
EOF

  cat <<'EOF' | write_if_absent openspec/specs/data/spec.md
# Data Model

## Purpose
Defines data models, entity schemas, and database conventions for all stacks.

## Requirements

### Requirement: Entity Schema Documentation
Each core entity MUST be documented with its fields, types, and constraints.

#### Scenario: Standard entity fields
- **WHEN** a new entity is defined
- **THEN** it includes at minimum `id` (bigint, PK, auto-increment) and `created_at` (datetime, not null, UTC)
EOF

  cat <<'EOF' | write_if_absent openspec/specs/errors/spec.md
# Error Handling

## Purpose
Defines error codes, HTTP status mapping, and error response format for all API responses.

## Requirements

### Requirement: Error Code Scheme
Error codes MUST follow a numeric scheme mapping to HTTP statuses: `0` = success (200), `4xxxx` = client errors (4xx), `5xxxx` = server errors (5xx).

#### Scenario: Success
- **WHEN** a request succeeds
- **THEN** returns `code: 0` (HTTP 200)

#### Scenario: Client error
- **WHEN** a request has invalid parameters
- **THEN** returns `code: 40001` (HTTP 400) with a descriptive message

#### Scenario: Server error
- **WHEN** an internal error occurs
- **THEN** returns `code: 50001` (HTTP 500) with a generic message

### Requirement: Error Response Format
All error responses MUST use the standard envelope with `data: null` and a human-readable `message`.

#### Scenario: Error envelope
- **WHEN** any error occurs
- **THEN** response body is `{ "code": <errorCode>, "data": null, "message": "<description>" }`
EOF

  cat <<'EOF' | write_if_absent openspec/changes/_template/proposal.md
# Proposal: [Change Name]

## Why
[Business reason - what problem this solves]

## What Changes
[Summary of the change]

## Affected Stacks
- [stack names; or "single-stack: <name>"]

## Depends-On
- [linked change ids or cross-stack `--goal` tag; or "none - standalone"]

## Scope
- In scope: [list]
- Out of scope: [list]

## Success Criteria
- [Measurable outcomes]

## Constraints
- [Technical / business constraints]

## Risks
- [Risk] → [Mitigation]
EOF

  cat <<'EOF' | write_if_absent openspec/changes/_template/specs/capability/spec.md
## ADDED Requirements

### Requirement: [requirement name]
<!-- Requirement description with MUST / SHALL keywords -->

#### Scenario: [scenario name]
- **WHEN** [trigger condition]
- **THEN** [expected outcome]
- **AND** [additional assertion, optional]
EOF

  cat <<'EOF' | write_if_absent openspec/changes/_template/debt.md
---
change: CHANGE_NAME
---
# Technical Debt Log
Legacy code changed without a full test harness. Each entry MUST be revisited when a
test runner is added to its stack. Linked from audit H-legacy check.
- [DEBT] <task>: <stack> no test runner; changed <what>; risk <low|med|high>; revisit <when>
EOF

  cat <<'EOF' | write_if_absent openspec/changes/README.md
# Changes - Delta Proposals

Active work lives here. Each proposal is a directory containing:
- `proposal.md` - Why / What / Scope / Success Criteria / Constraints / Risks
- `specs/<capability>/spec.md` - delta spec (## ADDED/MODIFIED/REMOVED Requirements + ### Requirement: + #### Scenario:)

Start from `_template/`. On completion, move the directory to `../archive/` via `/opsx:archive`.
EOF
  touch openspec/archive/.gitkeep

  cat <<'EOF' | write_if_absent openspec/loop-state.yaml
# openspec/loop-state.yaml - LoopForge workflow state machine.
# Phases: proposing -> applying -> verifying -> archived | abandoned (terminal).
#   debugging side-path: applying -> debugging (3-strike) -> applying | proposing (rewind)
# MOD-3: phase gates read this file; MOD-4: retry_count >= 3 -> enter debugging.
# Module-A: artifacts_hash/contract_hash for execution-contract freshness.
# Module-SDD: execution_mode/batches_completed for subagent-driven development.
phase: proposing
change: null
current_task: null
tasks_total: 0
tasks_done: 0
retry_count: 0
debt_count: 0
debug_attempts: 0
workflow_mode: null
artifacts_hash: null
contract_hash: null
execution_mode: null
batches_completed: 0
last_updated: null
EOF

  cat <<'EOF' | write_if_absent openspec/token-baseline.json
{
  "_comment": "Token baseline for auto-loaded files. Re-run: scaffold.sh tokens <project-dir>",
  "threshold": 3000,
  "components": []
}
EOF

  cat <<'__LF_VAPY__' | write_if_absent openspec/validate-artifacts.py
#!/usr/bin/env python3
"""LoopForge artifact validator - validates OpenSpec change artifacts structure.

Validates: proposal.md, specs/*/spec.md, design.md, tasks.md.
Reports ERROR/WARNING/INFO with file:path. Exit 1 on ERROR.
"""
import sys, os, re

MIN_WHY_LENGTH = 20
MAX_DELTAS = 15

def extract_section(content, header_re, level=2):
    """Extract text under a header matching header_re.
    level: the header level (2=##, 3=###, 4=####). Stops at same-or-higher headers."""
    m = re.search(header_re, content, re.MULTILINE)
    if not m:
        return None
    start = m.end()
    rest = content[start:]
    # Build pattern for same-or-higher level headers
    prefixes = '#' * (level)  # e.g. level=3 -> '###'
    # Match headers with level <= current (fewer or equal # signs)
    stop_re = r'^#{2,' + str(level) + r'}\s+'
    nm = re.search(stop_re, rest, re.MULTILINE)
    if nm:
        return rest[:nm.start()].strip()
    return rest.strip()

def validate_proposal(path):
    issues = []
    if not os.path.exists(path):
        return issues
    content = open(path, encoding='utf-8').read()
    why = extract_section(content, r'^##\s+Why\s*$', level=2)
    if why is None:
        issues.append(('ERROR', 'proposal.md:why', 'Missing ## Why section'))
    elif len(why.strip()) < MIN_WHY_LENGTH:
        issues.append(('ERROR', 'proposal.md:why', '## Why too brief (min %d chars)' % MIN_WHY_LENGTH))
    what = extract_section(content, r'^##\s+What Changes\s*$', level=2)
    if what is None:
        issues.append(('ERROR', 'proposal.md:whatChanges', 'Missing ## What Changes section'))
    elif not what.strip():
        issues.append(('ERROR', 'proposal.md:whatChanges', '## What Changes is empty'))
    return issues

def validate_spec(path):
    issues = []
    if not os.path.exists(path):
        return issues
    content = open(path, encoding='utf-8').read()
    delta_ops = ['ADDED', 'MODIFIED', 'REMOVED', 'RENAMED']
    found_ops = [op for op in delta_ops if re.search(r'^##\s+' + op + r'\s+Requirements\s*$', content, re.MULTILINE)]
    if not found_ops:
        issues.append(('ERROR', 'spec.md:deltas', 'No ADDED/MODIFIED/REMOVED/RENAMED section found'))
        return issues
    total = 0
    for op in found_ops:
        section = extract_section(content, r'^##\s+' + op + r'\s+Requirements\s*$', level=2)
        if not section:
            continue
        reqs = re.findall(r'^###\s+Requirement:\s*(.+?)\s*$', section, re.MULTILINE)
        seen = set()
        for name in reqs:
            total += 1
            key = name.strip().lower()
            if key in seen:
                issues.append(('ERROR', 'spec.md:%s.%s' % (op.lower(), key), 'Duplicate: %s' % name))
            seen.add(key)
            block = extract_section(section, r'^###\s+Requirement:\s*' + re.escape(name) + r'\s*$', level=3)
            if block:
                if not re.search(r'\b(SHALL|MUST)\b', block, re.IGNORECASE):
                    issues.append(('ERROR', 'spec.md:%s.%s' % (op.lower(), key), '%s "%s" missing SHALL/MUST' % (op, name)))
                if not re.search(r'(WHEN|Scenario|scenario)', block):
                    issues.append(('ERROR', 'spec.md:%s.%s' % (op.lower(), key), '%s "%s" has no scenario (WHEN/THEN)' % (op, name)))
    if total == 0:
        issues.append(('ERROR', 'spec.md:deltas', 'Delta sections exist but no requirements (### Requirement:) found'))
    elif total > MAX_DELTAS:
        issues.append(('WARNING', 'spec.md:deltas', 'Many deltas (%d > %d) - consider splitting' % (total, MAX_DELTAS)))
    return issues

def validate_design(path):
    issues = []
    if not os.path.exists(path):
        return issues
    content = open(path, encoding='utf-8').read()
    if not extract_section(content, r'^##\s+Decisions\s*$', level=2):
        issues.append(('WARNING', 'design.md:decisions', 'Missing ## Decisions section (recommended)'))
    return issues

def validate_tasks(path):
    issues = []
    if not os.path.exists(path):
        return issues
    content = open(path, encoding='utf-8').read()
    numbered = re.findall(r'^\d+[\.\)]\s+', content, re.MULTILINE)
    checkboxes = re.findall(r'^-\s+\[[ xX]\]\s+', content, re.MULTILINE)
    if not numbered and not checkboxes:
        issues.append(('ERROR', 'tasks.md', 'No numbered or checkbox tasks found'))
    return issues

def main():
    if len(sys.argv) < 2:
        print('Usage: python3 validate-artifacts.py <change-dir>')
        sys.exit(2)
    change_dir = sys.argv[1]
    if not os.path.isdir(change_dir):
        print('Error: %s is not a directory' % change_dir)
        sys.exit(2)
    all_issues = []
    all_issues.extend(validate_proposal(os.path.join(change_dir, 'proposal.md')))
    specs_dir = os.path.join(change_dir, 'specs')
    if os.path.isdir(specs_dir):
        for entry in sorted(os.listdir(specs_dir)):
            sf = os.path.join(specs_dir, entry, 'spec.md')
            if os.path.isfile(sf):
                for level, loc, msg in validate_spec(sf):
                    all_issues.append((level, 'specs/%s/%s' % (entry, loc), msg))
    else:
        sf = os.path.join(change_dir, 'spec.md')
        if os.path.isfile(sf):
            all_issues.extend(validate_spec(sf))
    all_issues.extend(validate_design(os.path.join(change_dir, 'design.md')))
    all_issues.extend(validate_tasks(os.path.join(change_dir, 'tasks.md')))
    icons = {'ERROR': 'X', 'WARNING': '!', 'INFO': 'i'}
    has_err = False
    for level, loc, msg in all_issues:
        print('  [%s] %s: %s' % (level, loc, msg))
        if level == 'ERROR':
            has_err = True
    if not all_issues:
        print('  All artifacts valid')
    elif has_err:
        errs = sum(1 for l, _, _ in all_issues if l == 'ERROR')
        print('\n  Validation FAILED (%d errors)' % errs)
    else:
        warns = sum(1 for l, _, _ in all_issues if l == 'WARNING')
        print('\n  Validation passed (%d warnings)' % warns)
    sys.exit(1 if has_err else 0)

if __name__ == '__main__':
    main()
__LF_VAPY__
  chmod +x openspec/validate-artifacts.py 2>/dev/null || true


  cat <<'__LF_CONTRACT__' | write_if_absent openspec/changes/_template/execution-contract.md
# Execution Contract

> LoopForge workflow bridge. No implementation without an approved contract.
> guard.sh enforces this: proposing->applying transition checks contract existence + freshness.

## Intent Lock

- **Change name**: 
- **Problem to solve**: 
- **In scope**: 
- **Out of scope**: 

## Approved Behavior

- **Approved requirements summary**: 
- **Key scenarios**: 
- **Acceptance checks**: 

## Design Constraints

- **Architecture constraints**: 
- **Interface constraints**: 
- **Dependency constraints**: 
- **Data constraints**: 

## Task Batches

### Batch 1
- **Goal**: 
- **Input**: 
- **Output**: 
- **Completion criteria**: 

## Test Obligations

- **Behaviors requiring failing-test-first**: 
- **Required edge cases**: 
- **Regression-sensitive areas**: 

## Execution Mode

- **Mode**: `Inline` | `Batch Inline` | `SDD`
- **Selection rationale**: 

## Verification Dimensions

| Dimension | Status | Findings |
|:--|:--|:--|
| Completeness | Pending | - |
| Correctness | Pending | - |
| Coherence | Pending | - |

**Overall**: Pending

## Review Gates

- **Mandatory review points**: 
- **Blocking categories**: 

## Escalation Rules

- **When to rewind to proposing**: new scope appears; key design assumption wrong; interfaces change materially
- **When NOT to continue**: contract intent lock no longer matches proposal scope
__LF_CONTRACT__

  cat <<'__LF_FRESH__' | write_if_absent openspec/ensure-contract-fresh.sh
#!/usr/bin/env bash
# ensure-contract-fresh.sh - Check/update execution-contract freshness via SHA256 hash
# Usage:
#   bash ensure-contract-fresh.sh <change-dir>            # check mode: exit 0=fresh, 1=stale
#   bash ensure-contract-fresh.sh --update <change-dir>   # update mode: compute + store hash
set -euo pipefail

mode="check"
if [[ "${1:-}" == "--update" ]]; then
  mode="update"; shift
fi

dir="${1:-}"
[[ -n "$dir" ]] || { echo "Usage: ensure-contract-fresh.sh [--update] <change-dir>" >&2; exit 2; }
[[ -d "$dir" ]] || { echo "Error: not a directory: $dir" >&2; exit 2; }

# Find loop-state.yaml by searching upward for openspec/
abs_dir="$(cd "$dir" && pwd)"
openspec_dir=""
cur="$abs_dir"
while [[ "$cur" != "/" ]]; do
  if [[ -f "$cur/openspec/loop-state.yaml" ]]; then
    openspec_dir="$cur/openspec"
    break
  fi
  cur="$(dirname "$cur")"
done

if [[ -z "$openspec_dir" ]]; then
  echo "Error: openspec/loop-state.yaml not found" >&2
  exit 1
fi

state_file="$openspec_dir/loop-state.yaml"

# Compute current hash of planning artifacts
hash_input=""
for f in "$dir/proposal.md" "$dir/design.md" "$dir/tasks.md"; do
  [[ -f "$f" ]] && hash_input+="$(cat "$f")"
done
specs_dir="$dir/specs"
if [[ -d "$specs_dir" ]]; then
  while IFS= read -r sf; do
    [[ -f "$sf" ]] && hash_input+="$(cat "$sf")"
  done < <(find "$specs_dir" -name "spec.md" | sort)
fi

current_hash=$(printf '%s' "$hash_input" | shasum -a 256 | awk '{print $1}')

if [[ "$mode" == "update" ]]; then
  # Update hash in loop-state.yaml
  if grep -q '^artifacts_hash:' "$state_file"; then
    # macOS sed needs -i ''
    # Portable in-place sed (macOS BSD sed needs -i '' with space; GNU sed needs -i'')
    _tmp=$(mktemp)
    sed "s/^artifacts_hash:.*/artifacts_hash: $current_hash/" "$state_file" > "$_tmp" && mv "$_tmp" "$state_file"
  else
    echo "artifacts_hash: $current_hash" >> "$state_file"
  fi
  echo "Updated artifacts_hash: $current_hash"
  exit 0
fi

# Check mode: compare stored vs current
stored_hash=$(grep '^artifacts_hash:' "$state_file" 2>/dev/null | sed 's/^artifacts_hash: *//' | tr -d '"' || true)

if [[ -z "$stored_hash" || "$stored_hash" == "null" ]]; then
  echo "BLOCKED: artifacts_hash not set. Generate execution-contract.md and run: bash ensure-contract-fresh.sh --update <change-dir>" >&2
  exit 1
fi

if [[ "$stored_hash" == "$current_hash" ]]; then
  exit 0
else
  echo "BLOCKED: execution-contract.md is STALE. Planning artifacts changed but contract not regenerated." >&2
  echo "  stored:  $stored_hash" >&2
  echo "  current: $current_hash" >&2
  echo "  Fix: regenerate execution-contract.md, then run: bash ensure-contract-fresh.sh --update <change-dir>" >&2
  exit 1
fi
__LF_FRESH__
  chmod +x openspec/ensure-contract-fresh.sh 2>/dev/null || true
  cat <<'__LF_BUILD_CONTRACT__' | write_if_absent openspec/build-contract.sh
#!/usr/bin/env bash
# build-contract.sh - Auto-generate execution-contract.md from planning artifacts
# Extracts content from: proposal.md, specs/, design.md, tasks.md
# Usage:
#   bash build-contract.sh <change-dir>          # generate (refuse if exists)
#   bash build-contract.sh --force <change-dir>  # overwrite existing
set -euo pipefail

force=0
[[ "${1:-}" == "--force" ]] && { force=1; shift; }
dir="${1:-}"
[[ -n "$dir" ]] || { echo "Usage: build-contract.sh [--force] <change-dir>" >&2; exit 2; }
[[ -d "$dir" ]] || { echo "Error: not a directory: $dir" >&2; exit 2; }

contract="$dir/execution-contract.md"
if [[ -f "$contract" && $force -eq 0 ]]; then
  echo "execution-contract.md already exists. Use --force to overwrite." >&2
  exit 1
fi

# --- helpers ---
# extract_h2 <file> <header_text>: print lines under "## <header>" until next "## "
extract_h2() {
  local file="$1" hdr="$2"
  [[ -f "$file" ]] || return 0
  awk -v h="$hdr" '
    BEGIN { h=tolower(h) }
    { line=tolower($0) }
    line ~ "^## " h "([ \t]|$)" { found=1; next }
    found && /^## / { exit }
    found { print }
  ' "$file" | sed '/^[[:space:]]*$/d'
}

# --- extract from proposal.md ---
change_name=""
if [[ -f "$dir/proposal.md" ]]; then
  change_name=$(grep -m1 '^# Proposal:' "$dir/proposal.md" 2>/dev/null | sed 's/^# Proposal:[[:space:]]*//' || true)
fi
[[ -z "$change_name" ]] && change_name=$(basename "$dir")

why=""
what=""
scope_raw=""
constraints=""
if [[ -f "$dir/proposal.md" ]]; then
  why=$(extract_h2 "$dir/proposal.md" "Why")
  what=$(extract_h2 "$dir/proposal.md" "What")
  scope_raw=$(extract_h2 "$dir/proposal.md" "Scope")
  constraints=$(extract_h2 "$dir/proposal.md" "Constraints")
fi

# --- extract verification scenarios from specs/ or spec.md ---
specs_content=""
if [[ -d "$dir/specs" ]]; then
  while IFS= read -r sf; do
    [[ -f "$sf" ]] || continue
    local_specs=$(extract_h2 "$sf" "Verification Scenarios")
    [[ -n "$local_specs" ]] && specs_content+="### $(basename "$(dirname "$sf")")" && specs_content+=$'\n'"$local_specs"$'\n\n'
  done < <(find "$dir/specs" -name "spec.md" | sort)
fi
if [[ -z "$specs_content" && -f "$dir/spec.md" ]]; then
  specs_content=$(extract_h2 "$dir/spec.md" "Verification Scenarios")
fi
[[ -z "$specs_content" ]] && specs_content="<!-- AI: no verification scenarios found in specs/ - add them -->"

# --- extract from design.md ---
design_decisions=""
if [[ -f "$dir/design.md" ]]; then
  design_decisions=$(extract_h2 "$dir/design.md" "Decisions")
  [[ -z "$design_decisions" ]] && design_decisions=$(extract_h2 "$dir/design.md" "Architecture")
fi

# --- extract tasks from tasks.md ---
tasks_raw="<!-- AI: no tasks.md found - create it first -->"
if [[ -f "$dir/tasks.md" ]]; then
  tasks_raw=$(cat "$dir/tasks.md")
fi

# --- assemble contract ---
{
  echo "# Execution Contract"
  echo ""
  echo "> Auto-generated by build-contract.sh from planning artifacts."
  echo "> Review and refine AI-marked sections before applying."
  echo "> guard.sh enforces: proposing->applying transition checks contract existence + freshness."
  echo ""
  echo "## Intent Lock"
  echo ""
  echo "- **Change name**: $change_name"
  echo "- **Problem to solve**:"
  echo "$why"
  echo ""
  echo "<!-- AI: summarize the above into 1-2 sentences -->"
  echo "- **In scope**:"
  echo "$scope_raw"
  echo "- **Out of scope**:"
  echo "<!-- AI: extract 'Out of scope' items from the scope section above -->"
  echo ""
  echo "## Approved Behavior"
  echo ""
  echo "<!-- AI: review and confirm these verification scenarios -->"
  echo "$specs_content"
  echo ""
  echo "## Design Constraints"
  echo ""
  echo "- **Architecture/Decisions**:"
  [[ -n "$design_decisions" ]] && echo "$design_decisions" || echo "<!-- AI: no design.md found - create it first -->"
  echo "- **Technical constraints**:"
  [[ -n "$constraints" ]] && echo "$constraints" || echo "<!-- AI: fill from proposal Constraints -->"
  echo ""
  echo "## Task Batches"
  echo ""
  echo "<!-- AI: review task batching; adjust goals/inputs/outputs per batch -->"
  echo "$tasks_raw"
  echo ""
  echo "## Test Obligations"
  echo ""
  echo "<!-- AI: identify behaviors requiring failing-test-first from scenarios above -->"
  echo "- **Behaviors requiring failing-test-first**: "
  echo "- **Required edge cases**: "
  echo "- **Regression-sensitive areas**: "
  echo ""
  echo "## Execution Mode"
  echo ""
  echo "- **Mode**: \`Inline\` | \`Batch Inline\` | \`SDD\`"
  echo "- **Selection rationale**: <!-- AI: choose based on task count and complexity -->"
  echo ""
  echo "## Verification Dimensions"
  echo ""
  echo "| Dimension | Status | Findings |"
  echo "|:--|:--|:--|"
  echo "| Completeness | Pending | - |"
  echo "| Correctness | Pending | - |"
  echo "| Coherence | Pending | - |"
  echo ""
  echo "**Overall**: Pending"
  echo ""
  echo "## Review Gates"
  echo ""
  echo "- **Mandatory review points**: "
  echo "- **Blocking categories**: "
  echo ""
  echo "## Escalation Rules"
  echo ""
  echo "- **When to rewind to proposing**: new scope appears; key design assumption wrong; interfaces change materially"
  echo "- **When NOT to continue**: contract intent lock no longer matches proposal scope"
} > "$contract"

echo "Generated: $contract"
echo "Next: review AI-marked sections, then run: bash openspec/ensure-contract-fresh.sh --update $dir"
__LF_BUILD_CONTRACT__
  chmod +x openspec/build-contract.sh 2>/dev/null || true


  cat <<'__LF_GUARD__' | write_if_absent openspec/guard.sh
#!/usr/bin/env bash
# guard.sh - Phase transition guard for LoopForge workflow
# Usage: bash guard.sh [--json] <from-phase> <to-phase> <change-dir>
# Exit 0 = all checks pass, 1 = blocked
# --json: output {"pass":true/false,"failures":[...]} on stdout (for CI/programmatic use)
set -euo pipefail

_json=0
_failures=()
_args=()
for _a in "$@"; do
  [[ "$_a" == "--json" ]] && _json=1 || _args+=("$_a")
done
set -- "${_args[@]}"

from="${1:-}"
to="${2:-}"
dir="${3:-}"

[[ -n "$from" && -n "$to" && -n "$dir" ]] || {
  echo "Usage: guard.sh [--json] <from-phase> <to-phase> <change-dir>" >&2
  exit 2
}

# Resolve openspec/ directory
abs_dir="$(cd "$dir" 2>/dev/null && pwd)"
openspec_dir=""
cur="$abs_dir"
while [[ "$cur" != "/" ]]; do
  if [[ -d "$cur/openspec" ]]; then
    openspec_dir="$cur/openspec"
    break
  fi
  cur="$(dirname "$cur")"
done
[[ -z "$openspec_dir" ]] && openspec_dir="$(dirname "$abs_dir")"

if [[ $_json -eq 1 ]]; then
  fail() { _failures+=("$1"); }
else
  fail() { echo "  [BLOCKED] $1" >&2; exit 1; }
fi

check_artifacts_exist() {
  [[ -f "$dir/proposal.md" ]] || fail "proposal.md missing"
  { [[ -f "$dir/spec.md" ]] || [[ -d "$dir/specs" ]]; } || fail "spec.md or specs/ missing"
}

check_schema_valid() {
  local vpy="$openspec_dir/validate-artifacts.py"
  if [[ -f "$vpy" ]] && command -v python3 >/dev/null 2>&1; then
    if [[ $_json -eq 1 ]]; then
      python3 "$vpy" "$dir" >/dev/null 2>&1 || fail "artifact validation failed"
    else
      python3 "$vpy" "$dir" 2>&1 || fail "artifact validation failed"
    fi
    return 0
  fi
  # Bash fallback (no python3): lightweight required-field check
  [[ $_json -eq 0 ]] && echo "  [guard] schema fallback (no python3) - basic field check" >&2
  local _has_intent=0
  if [[ -f "$dir/proposal.md" ]]; then
    grep -qiE '## (Intent|Problem|In scope|Out of scope)' "$dir/proposal.md" && _has_intent=1
  fi
  [[ $_has_intent -eq 1 ]] || fail "proposal.md missing intent/problem/scope section"
  # Check spec has at least one WHEN/THEN scenario
  if [[ -d "$dir/specs" ]]; then
    grep -qrE '## Scenario:|WHEN|THEN' "$dir/specs/" 2>/dev/null || fail "specs/ has no WHEN/THEN scenarios"
  elif [[ -f "$dir/spec.md" ]]; then
    grep -qE '## Scenario:|WHEN|THEN' "$dir"/specs/*/spec.md 2>/dev/null || fail "specs/*/spec.md has no WHEN/THEN scenarios"
  fi
}

check_abandon_safe() {
  # Abandon is allowed if debt.md has entries OR no tasks were started yet
  local debt="$dir/debt.md"
  if [[ -f "$debt" ]] && grep -qE '\[DEBT\]' "$debt" 2>/dev/null; then
    [[ $_json -eq 0 ]] && echo "  [guard] abandon OK - debt.md has entries"
    return 0
  fi
  local state="$openspec_dir/loop-state.yaml"
  if [[ -f "$state" ]]; then
    local done
    done=$(grep '^tasks_done:' "$state" 2>/dev/null | awk '{print $2}')
    if [[ "${done:-0}" == "0" ]]; then
      [[ $_json -eq 0 ]] && echo "  [guard] abandon OK - no tasks started yet"
      return 0
    fi
  fi
  fail "cannot abandon: tasks were done but debt.md has no [DEBT] entries - record debt first"
}

check_contract_fresh() {
  local contract="$dir/execution-contract.md"
  [[ -f "$contract" ]] || fail "execution-contract.md missing - generate it first (see propose inject block)"
  local fresh_sh="$openspec_dir/ensure-contract-fresh.sh"
  [[ -f "$fresh_sh" ]] || { [[ $_json -eq 0 ]] && echo "  [SKIP] ensure-contract-fresh.sh not found" >&2; return 0; }
  if [[ $_json -eq 1 ]]; then
    bash "$fresh_sh" "$dir" >/dev/null 2>&1 || fail "execution-contract.md is stale - regenerate it"
  else
    bash "$fresh_sh" "$dir" 2>&1 || fail "execution-contract.md is stale - regenerate it"
  fi
}

check_tasks_complete() {
  local state="$openspec_dir/loop-state.yaml"
  [[ -f "$state" ]] || fail "loop-state.yaml not found"
  local done total
  done=$(grep '^tasks_done:' "$state" | awk '{print $2}')
  total=$(grep '^tasks_total:' "$state" | awk '{print $2}')
  [[ "$done" == "$total" ]] || fail "tasks incomplete: $done/$total"
}

check_verify_pass() {
  local verify="$dir/verify.md"
  [[ -f "$verify" ]] || fail "verify.md missing - run /opsx:verify first"
  grep -q 'overall:.*PASS' "$verify" || fail "verify.md overall is not PASS"
}

key="${from}:${to}"
case "$key" in
  proposing:applying)
    [[ $_json -eq 0 ]] && echo "  [guard] proposing -> applying"
    check_artifacts_exist
    check_schema_valid
    check_contract_fresh
    ;;
  applying:verifying)
    [[ $_json -eq 0 ]] && echo "  [guard] applying -> verifying"
    check_tasks_complete
    check_contract_fresh
    ;;
  verifying:archived)
    [[ $_json -eq 0 ]] && echo "  [guard] verifying -> archived"
    check_verify_pass
    ;;
  *:abandoned)
    [[ $_json -eq 0 ]] && echo "  [guard] $from -> abandoned"
    check_abandon_safe
    ;;
  *)
    [[ $_json -eq 0 ]] && echo "  [guard] $from -> $to (no checks required)"
    ;;
esac

if [[ $_json -eq 1 ]]; then
  if [[ ${#_failures[@]} -eq 0 ]]; then
    printf '{"pass":true,"failures":[]}\n'
    exit 0
  else
    printf '{"pass":false,"failures":['
    _first=1
    for _f in "${_failures[@]}"; do
      [[ $_first -eq 0 ]] && printf ','
      _first=0
      _esc="${_f//\"/\"}"
      printf '"%s"' "$_esc"
    done
    printf ']}\n'
    exit 1
  fi
fi
echo "  [guard] All checks passed."
exit 0
__LF_GUARD__
  chmod +x openspec/guard.sh 2>/dev/null || true


  mkdir -p openspec/sdd
  cat <<'__LF_SDD_IMP__' | write_if_absent openspec/sdd/implementer-prompt.md
# Implementer Subagent Prompt Template

Use this template when dispatching an implementer subagent (CC: Task tool; Codex: role-switch).

```
Subagent:
  description: "Implement Task N: [task name]"
  model: [MODEL - choose per role: mechanical=cheap, integration=standard, architecture=capable]
  prompt: |
    You are implementing Task N: [task name]

    ## Task Description
    Read your task brief first: [BRIEF_FILE or tasks.md task N]
    It contains the full task text from the plan.

    ## Context
    [Where this fits in the execution-contract.md batch plan.
     Dependencies on prior tasks. Architectural context from design.md.]

    ## Before You Begin
    If you have questions about requirements, approach, dependencies, or anything unclear:
    Ask them now. Raise concerns before starting work.

    ## Your Job
    1. Implement exactly what the task specifies - nothing more (YAGNI)
    2. Write tests following TDD (RED -> GREEN -> REFACTOR) or characterization mode
    3. Verify implementation works (run tests)
    4. Commit your work
    5. Self-review (see below)
    6. Report back

    Work from: [directory]

    ## TDD Discipline
    - If test runner exists: write failing test FIRST, confirm RED, then implement, confirm GREEN
    - If no test runner (legacy): characterization test OR record [DEBT] in debt.md
    - NEVER silently change code without a test or debt record

    ## When in Over Your Head
    STOP and escalate when:
    - Task requires architectural decisions with multiple valid approaches
    - You cannot understand the code beyond what was provided
    - You feel uncertain about your approach
    Report: BLOCKED or NEEDS_CONTEXT with specifics.

    ## Self-Review Before Reporting
    - Completeness: did I implement everything in the spec?
    - Quality: are names clear? is code clean?
    - Discipline: did I avoid overbuilding? follow existing patterns?
    - Testing: do tests verify real behavior? is TDD evidence present?

    ## Report Format
    Write your report to [REPORT_FILE]:
    - What you implemented
    - TDD Evidence: RED (command + failing output) + GREEN (command + passing output)
    - Files changed
    - Self-review findings
    - Issues or concerns

    Then report back with status (under 15 lines):
    - Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
    - One-line summary
    - Report file path
```

Placeholders: [task name], [BRIEF_FILE], [directory], [REPORT_FILE], [MODEL]
```

__LF_SDD_IMP__

  cat <<'__LF_SDD_REV__' | write_if_absent openspec/sdd/reviewer-prompt.md
# Reviewer Subagent Prompt Template

Use this template when dispatching a reviewer subagent (CC: Task tool; Codex: role-switch).

```
Subagent:
  description: "Review Task N: [task name]"
  model: [MODEL - match the implementer model or one level higher]
  prompt: |
    You are reviewing Task N: [task name].

    ## Inputs
    - Implementer report: [REPORT_FILE]
    - Base commit: [BASE_SHA]
    - Head commit: [HEAD_SHA]
    - Spec: [SPEC_FILE or specs/ path]
    - Execution contract: openspec/changes/[change]/execution-contract.md

    Review the diff (git diff [BASE_SHA]..[HEAD_SHA]) against the spec.

    ## Part 1: Spec Compliance
    Compare the diff against what was requested:
    - Missing: requirements skipped or claimed without implementing
    - Extra: features not requested, over-engineering
    - Misunderstood: right feature built the wrong way

    ## Part 2: Code Quality
    - Clean separation of concerns?
    - Proper error handling?
    - DRY without premature abstraction?
    - Edge cases handled?

    ## Part 3: Tests
    - Do tests verify real behavior, not mocks?
    - Are edge cases covered?
    - Is TDD evidence present (RED + GREEN)?

    ## Calibration
    - Critical: must fix before proceeding (incorrect behavior, missing requirement)
    - Important: should fix (fragile behavior, maintainability damage)
    - Minor: nice to have (polish, coverage could be broader)

    ## Output Format
    ### Spec Compliance
    - Compliant | Issues found: [what, with file:line]

    ### Strengths
    [What was done well? Be specific.]

    ### Issues
    #### Critical (Must Fix)
    #### Important (Should Fix)
    #### Minor (Nice to Have)

    ### Assessment
    Task quality: Approved | Needs fixes
    Reasoning: [1-2 sentence technical assessment]
```

Placeholders: [task name], [REPORT_FILE], [BASE_SHA], [HEAD_SHA], [SPEC_FILE], [MODEL]
```

__LF_SDD_REV__

  cat <<'__LF_SDD_PROG__' | write_if_absent openspec/sdd/progress.md
# SDD Progress Ledger

> Track per-task completion. Check this file on resume to recover state.
> Update after each task: status, commits, review verdict.

## Change: [change-name]
## Execution Mode: [Inline | Batch Inline | SDD]
## Started: [timestamp]

### Task 1: [task name]
- Status: Pending | In Progress | Complete | Blocked
- Commits: [base7..head7]
- Review: Pending | Clean | Issues Found (Critical/Important/Minor)
- Notes: 

### Task 2: [task name]
- Status: Pending
- Commits: 
- Review: Pending
- Notes: 

---

## Summary
- Total tasks: [N]
- Completed: [N]
- Blocked: [N]
- Final review: Pending | Passed | Failed
__LF_SDD_PROG__

  # ---------- 2. .claude/  (HOW - discipline) ----------
  echo "==> Creating .claude/ (HOW)"
  mkdir -p .claude/rules .claude/skills .claude/agents .claude/commands

  cat <<'EOF' | write_if_absent .claude/settings.json
{
  "permissions": {
    "allow": [
      "Bash(openspec:*)",
      "Bash(npm:*)",
      "Bash(pnpm:*)",
      "Bash(mvn:*)",
      "Bash(gradle:*)",
      "Bash(git status)",
      "Bash(git diff:*)",
      "Bash(git log:*)",
      "Bash(git add:*)",
      "Bash(git commit:*)"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Bash(git push --force*)",
      "Bash(git reset --hard*)"
    ]
  },
  "hooks": {
    "SessionStart": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "echo '[loopforge] session started'" } ] }
    ],
    "PreToolUse": [
      { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "echo '[loopforge] pre-edit gate'" } ] }
    ],
    "Stop": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "echo '[loopforge] session stop'" } ] }
    ]
  }
}
EOF
  echo "  note: hook stubs are the recommended default; optional - replace with real lint/build gates for CI enforcement."

  # Build globs dynamically from configured stack dirs
  _globs=""
  has backend && _globs="\"${BACKEND_DIR}/**\""
  has frontend && _globs="${_globs:+$_globs, }\"${FRONTEND_DIR}/**\""
  has frontend-mobile && _globs="${_globs:+$_globs, }\"${MOBILE_DIR}/**\""
  cat <<EOF | write_if_absent .claude/rules/naming.md
---
globs: [$_globs]
---
<!-- auto-loaded: English only. Human notes: docs/GUIDE.zh.md -->
# Naming Conventions (shared)

- File names: kebab-case (\`user-service.ts\`)
- [Add stack-specific rules in per-stack CLAUDE.md; only truly universal rules here]
EOF
  touch .claude/rules/.gitkeep .claude/skills/.gitkeep .claude/commands/.gitkeep

  cat <<'EOF' | write_if_absent .claude/agents/reviewer.md
---
name: reviewer
description: Code reviewer - read-only audit, never edits files.
tools: Read, Bash
---
You are a **Code Reviewer Agent**. Read code and run checks/commands.
**NEVER edit files.** Report issues with `file:line` references and severity (blocker / major / minor).
Verify implementation against `openspec/specs/` WHEN/THEN scenarios.
EOF

  cat <<'EOF' | write_if_absent .claude/agents/coordinator.md
---
name: coordinator
description: Orchestrates multi-agent workflow; delegates to domain agents.
tools: Read, Bash, Edit, Write
---
You are the **Coordinator Agent**. Delegate work to domain agents (backend / frontend).
**NEVER write domain code yourself.** Track proposals in `openspec/changes/`, route review to the `reviewer` agent.
EOF

  cat <<'EOF' | write_if_absent .claude/agents/implementer.md
---
name: implementer
description: Implements a single task from the execution contract. Dispatched by coordinator via Task tool.
tools: Read, Write, Edit, Bash
---
You are an **Implementer Agent**. You implement exactly ONE task from the execution contract.
**NEVER work outside your assigned task scope.** Follow TDD Iron Law (legacy-aware).
Read your task brief, implement, test, commit, self-review, then report back.
Report status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
EOF



  # ---------- 3. Per-stack Agent CLAUDE.md (WHO) ----------
  # ---------- 0c. Auto-install Superpowers skills (if available as plugin) ----------
  # Superpowers (brainstorm/writing-plans/executing-plans/code-review/verification) are
  # on-demand skills referenced by /opsx:propose triggers. If installed as a user-level
  # plugin, copy them into the project so the audit (S5) passes and triggers work.
  _super_src=""
  for _p in "$HOME/.claude/plugins/cache"/*/superpowers/*/skills "$HOME/.codex/plugins/cache"/*/superpowers/*/skills; do
    [[ -d "$_p/brainstorming" ]] && _super_src="$_p" && break
  done
  if [[ -n "$_super_src" ]]; then
    echo "==> Auto-installing Superpowers skills (from plugin cache)"
    for _sk in brainstorming writing-plans executing-plans requesting-code-review verification-before-completion test-driven-development systematic-debugging; do
      if [[ -d "$_super_src/$_sk" ]]; then
        cp -r "$_super_src/$_sk" .claude/skills/ 2>/dev/null && echo "  install: .claude/skills/$_sk" || echo "  skip (exists): .claude/skills/$_sk"
      fi
    done
  else
    echo "  note: Superpowers plugin not found - /opsx:propose triggers will reference skills that are not installed."
    echo "        install: Claude Code -> Superpowers plugin, or copy skills to .claude/skills/"
  fi

  echo "==> Creating Agent CLAUDE.md per stack"

  gen_agent() {
    local stack="$1"
    local dir="$2"
    local label="$3"
    case "$stack" in
      backend)
        cat <<EOF | subst | write_both "$dir/CLAUDE.md" "$dir/AGENTS.md"
<!-- auto-loaded: English only. Human notes: docs/GUIDE.zh.md -->
# CLAUDE.md - @@PROJECT_NAME@@ $label

## Role
You are a **$label**. Your scope: server-side logic, APIs, data access, business rules.
**NEVER generate frontend code** (that lives in \`../@@FRONTEND_DIR@@/CLAUDE.md\`).
**NEVER modify \`../openspec/specs/\`** - specs are shared truth, read-only.

## Project Overview
- **System**: @@PROJECT_NAME@@ - [one-line business description]
- **Stack**: [e.g. Java 17 + Spring Boot 3 + MyBatis]
- **Database**: [e.g. MySQL 8]

## Before You Code
1. Read \`../openspec/specs/api/spec.md\` (authoritative contract)
2. Read \`../openspec/specs/data/spec.md\` and \`../openspec/specs/errors/spec.md\`
3. Check \`../openspec/changes/\` for active proposals
4. If no spec exists, run \`/opsx:propose\` first - never code without a spec

## Module Structure
[Describe backend module layout]

## Coding Standards
- [Domain-specific conventions; shared conventions in \`../.claude/rules/\`]
- Never modify existing public methods - use overloading
- New behavior = new method/class

## Superpowers Workflow (auto-triggered by /opsx:propose, /opsx:apply)
1. brainstorm → clarify requirements
2. writing-plans → TDD plan
3. executing-plans → implement (tests first)
4. code-review → self/peer review
5. verification-before-completion → prove it against WHEN/THEN

## TDD
- Red: write a failing test for the WHEN/THEN scenario
- Green: minimum code to pass
- Refactor: keep tests green

## Build Commands
\`\`\`
[mvn clean test | ./gradlew test | ...]
\`\`\`
EOF
        ;;
      frontend|frontend-mobile)
        cat <<EOF | subst | write_both "$dir/CLAUDE.md" "$dir/AGENTS.md"
<!-- auto-loaded: English only. Human notes: docs/GUIDE.zh.md -->
# CLAUDE.md - @@PROJECT_NAME@@ $label

## Role
You are a **$label**. Your scope: UI, components, state, API integration.
**NEVER generate backend code** (that lives in \`../@@BACKEND_DIR@@/CLAUDE.md\`).
**NEVER modify \`../openspec/specs/\`** - specs are shared truth, read-only.

## Project Overview
- **System**: @@PROJECT_NAME@@ - [one-line business description]
- **Stack**: [e.g. Vue 3 + Vite + Element Plus (web) / Vant (mobile)]

## Before You Code
1. Read \`../openspec/specs/api/spec.md\` - mock from it (any mock tool), do not invent endpoints
2. Read \`../openspec/specs/errors/spec.md\` - handle every error code
3. Check \`../openspec/changes/\` for active proposals
4. If no spec exists, run \`/opsx:propose\` first - never code without a spec

## Mock-First
- Mock APIs from \`../openspec/specs/api/spec.md\` (any mock tool: MSW / mockjs / vite-plugin-mock / etc.)
- **Mini-program exception** (WeChat/Alipay/etc.): delivery chain (dev tools -> real device -> review -> online) makes mock low-ROI; direct connection to a real test backend is valid. Skip mock, wire real API calls early to surface openid/domain/real-device issues.
- UI prototype via \`frontend-design\` skill → **user confirms** → then \`/opsx:apply\`

## Module Structure
[Describe frontend module/layout]

## Coding Standards
- [Domain-specific conventions; shared conventions in \`../.claude/rules/\`]
- Never modify existing components - compose or extend

## Superpowers Workflow (auto-triggered by /opsx:propose, /opsx:apply)
1. brainstorm → clarify requirements
2. writing-plans → TDD plan
3. executing-plans → implement (tests first)
4. code-review → self/peer review
5. verification-before-completion → prove it against WHEN/THEN

## TDD
- Red: failing component/unit test for the WHEN/THEN scenario
- Green: minimum code to pass
- Refactor: keep tests green

## Build Commands
\`\`\`
[pnpm dev | pnpm test | pnpm build | ...]
\`\`\`
EOF
        ;;
    esac
  }

  if has backend;         then mkdir -p "$BACKEND_DIR";  gen_agent backend         "$BACKEND_DIR"  "$(label_for backend)";        touch "$BACKEND_DIR/.gitkeep"; fi
  if has frontend;        then mkdir -p "$FRONTEND_DIR"; gen_agent frontend        "$FRONTEND_DIR" "$(label_for frontend)";       touch "$FRONTEND_DIR/.gitkeep"; fi
  if has frontend-mobile; then mkdir -p "$MOBILE_DIR";   gen_agent frontend-mobile "$MOBILE_DIR"   "$(label_for frontend-mobile)"; touch "$MOBILE_DIR/.gitkeep"; fi

  # ---------- 3b. Multi-stack coordination layer (OpenSpec 1.6.0) ----------
  # OpenSpec 1.6.0 removed workspace/context-store/initiative. Cross-stack coordination is now a
  # LoopForge-managed convention built on 1.6.0 primitives (each stack is a subdir of one OpenSpec root):
  #   - openspec/coordination/<feature>.md : shared "parent" (design/decisions + per-stack change registry)
  #   - openspec new change <name> --goal "<feature>" : per-stack change soft-tagged to the feature
  #   - openspec workset : group all stack dirs to open them together (IDE; agent open is temporarily
  #     disabled in 1.6.0 - launch codex/claude manually in the project root for a coordinator session)
  # Without this, a cross-stack feature's "declared dependency" has no home and is lost.
  if [[ $RUN_INIT -eq 1 ]] && command -v openspec >/dev/null 2>&1; then
    _nstacks=$(awk -F, '{print NF}' <<<"$STACKS")
    if [[ $_nstacks -ge 2 ]]; then
      echo "==> Multi-stack detected ($_nstacks stacks): setting up coordination layer"
      # Shared coordination doc = the "parent" home for cross-stack features (CLI-safe: not parsed
      # by openspec list/validate/context).
      mkdir -p openspec/coordination
      cat <<'__COORD_README__' | subst | write_if_absent openspec/coordination/README.md
# Cross-Stack Coordination (LoopForge convention for OpenSpec 1.6.0)

> OpenSpec 1.6.0 removed `workspace`/`context-store`/`initiative`. This directory is the
> LoopForge-managed replacement for the "parent" that tracks a cross-stack feature across
> per-stack changes. It is plain documentation - the openspec CLI does not parse it.

## How a cross-stack feature works
1. **Create the parent** - copy `_template.md` to `<feature>.md`, fill the shared design/decisions.
2. **Per stack** - in each stack run `openspec new change <name> --goal "<feature>"` (soft-tagged).
3. **Register** - list each per-stack change in `<feature>.md`'s change registry table.
4. **Gate** - the feature is done when ALL registered changes verify PASS (`openspec/verify.config.yaml`); archive each.

## Open all stacks together
```bash
openspec workset open @@WS_NAME@@ --tool code   # IDE (VS Code/Cursor). Agent open is temporarily disabled in 1.6.0.
```
For a coordinator agent session, launch `codex` / `claude` manually in the project root.

## Separate repos (advanced)
If stacks live in independent git repos (each its own OpenSpec root), register and address them with stores:
`openspec store register --id <project>-<stack> <repo-path>` then `openspec new change <name> --goal "<feature>" --store <project>-<stack>`.
__COORD_README__
      cat <<'__COORD_TPL__' | subst | write_if_absent openspec/coordination/_template.md
# Coordination: <feature>

> Cross-stack parent. Shared design/decisions + per-stack change registry.
> Per-stack changes are soft-tagged via `openspec new change <name> --goal "<feature>"`.

## Why
[Business reason for the cross-stack feature]

## Shared Design
[API contracts / data model / error codes negotiated across stacks - single source of truth]

## Decisions
- [Decision] - [rationale] - [date]

## Change Registry
| Stack | Change | Status | Verify |
|:--|:--|:--|:--|
| backend | [change name] | proposing | - |
| frontend | [change name] | proposing | - |

## Gate
Feature done = ALL registered changes verify PASS -> archive each.
__COORD_TPL__
      # Workset grouping all stack code dirs (no --tool: agent open is disabled in 1.6.0; create saves cleanly).
      # OpenSpec requires kebab-case workset names; convert PROJECT_NAME accordingly.
      _ws_name=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr '_' '-')
      _members=""
      for _s in $(echo "$STACKS" | tr ',' ' '); do
        _members="$_members --member ${_s}=./$(dir_for "$_s")"
      done
      # shellcheck disable=SC2086
      openspec workset create "$_ws_name" $_members >/dev/null 2>&1 \
        || echo "  warn: workset create failed (maybe exists); manual: openspec workset create $_ws_name $_members"
      echo "    coordination:  openspec/coordination/ (shared design/decisions + per-feature change registry)"
      echo "    workset:       $_ws_name (open all stacks: openspec workset open $_ws_name --tool code)"
      echo "    cross-stack flow: see AGENTS.md \"Cross-Stack Feature\""
    fi
  fi

  # ---------- 4. Root CLAUDE.md (nav hub, <=120 lines) ----------
  echo "==> Creating root CLAUDE.md (nav hub)"
  {
    echo "<!-- auto-loaded: English only. Human notes: docs/GUIDE.zh.md -->"
    echo "# @@PROJECT_NAME@@"
    echo ""
    echo "> Structured per OpenSpec + Superpowers + Harness (Loop Engineering)."
    echo "> Launch agents from their subdirectories (Claude Code: \`claude\`; Codex: \`codex\`)."
    echo ""
    echo "## Project Map"
    echo '```'
    echo "@@PROJECT_NAME@@/"
    echo "├── CLAUDE.md          ← nav hub (≤120 lines)"
    echo "├── openspec/          ← WHAT: specs/, changes/, archive/"
    echo "├── .claude/           ← HOW: rules/, skills/, agents/, settings.json"
    if has backend;         then echo "├── @@BACKEND_DIR@@/      ← $(label_for backend)"; fi
    if has frontend;        then echo "├── @@FRONTEND_DIR@@/     ← $(label_for frontend)"; fi
    if has frontend-mobile; then echo "├── @@MOBILE_DIR@@/   ← $(label_for frontend-mobile)"; fi
    echo '```'
    echo ""
    echo "## Business Context"
    echo "[1-3 sentences from openspec/project.md]"
    echo ""
    echo "## Tech Stack"
    echo "| Layer | Tech |"
    echo "|:--|:--|"
    if has backend;         then echo "| Backend | [fill] |"; fi
    if has frontend;        then echo "| Frontend (web) | [fill] |"; fi
    if has frontend-mobile; then echo "| Frontend (mobile) | [fill] |"; fi
    echo ""
    echo "## Conventions"
    echo "- File names: kebab-case (\`user-service.ts\`)"
    echo "- Never modify existing public methods - use overloading"
    echo "- Auto-loaded files English only (Chinese notes in \`docs/GUIDE.zh.md\`)"
    echo ""
    echo "## Development Workflow"
    echo "### New Feature"
     echo "1. Write spec: \`/opsx:propose <change>\` (auto-triggers Superpowers brainstorm)"
     if has backend && (has frontend || has frontend-mobile); then
      echo "2. Backend Agent: \`cd @@BACKEND_DIR@@\` → launch AI (claude/codex) → implement to spec (TDD)"
      echo "3. Frontend Agent (parallel): \`cd @@FRONTEND_DIR@@\` → launch AI (claude/codex) → mock from spec → \`frontend-design\` skill → UI prototype → **user confirms** → \`/opsx:apply\`"
     echo "4. Verify against WHEN/THEN; \`/opsx:archive\` when done"
    else
      echo "2. Agent: \`cd <stack-dir>\` → launch AI (claude/codex) → implement to spec (TDD)"
     echo "3. Verify against WHEN/THEN; \`/opsx:archive\` when done"
    fi
    if has backend && (has frontend || has frontend-mobile); then
      echo ""
      echo "### Cross-Stack Feature (>=2 stacks - one coordination doc tracks all per-stack changes)"
      echo "A cross-stack \"declared dependency\" with no parent is lost. Stable pattern (OpenSpec 1.6.0):"
      echo "1. Parent: create \`openspec/coordination/<feature>.md\` (shared design/decisions + change registry)"
      echo "2. Per stack (parallel): \`openspec new change <name> --goal \"<feature>\"\` (soft-tagged to the feature)"
      echo "3. Implement each in its own stack (cross-domain ban unchanged; frontend mocks first - web only; mini-program may connect to real test backend); coordinate via the coordination doc \`design\`/\`decisions\`"
      echo "4. Gate: feature done = ALL registered changes verify PASS (\`openspec/verify.config.yaml\`) -> archive each"
      echo "   Single-stack: skip coordination; plain \`openspec new change\`. Open all stacks: \`openspec workset open @@WS_NAME@@ --tool code\`."
    fi
    echo ""
    echo "### AI Coding Rules"
    echo "- Spec first - read \`openspec/specs/\` before writing code"
    if has frontend || has frontend-mobile; then echo "- UI prototype first - \`frontend-design\` skill before \`/opsx:apply\`"; fi
    echo "- TDD - Superpowers auto-enforces"
    echo "- No cross-domain - each agent writes only its own stack"
    echo "- Never modify existing methods - use overloading"
    echo "- Dangerous ops (\`rm -rf\`, \`git push --force\`, \`git reset --hard\`) gated by sandbox/approval or .claude/settings.json deny list"
    echo ""
    echo "### Session Commands"
    echo "\`/resume\` · \`/branch\` · \`/rewind\`"
    echo ""
    echo "## Build & Test"
    echo '```'
    echo "[3-5 commands covering all stacks; details in per-stack CLAUDE.md]"
    echo '```'
  } | subst | write_both CLAUDE.md AGENTS.md

  cat <<'EOF' | subst | write_if_absent README.md
# @@PROJECT_NAME@@

Generated by **loopforge scaffold** (OpenSpec + Superpowers + Harness).

See `CLAUDE.md` / `AGENTS.md` (nav hub) and `openspec/README.md`.
EOF

  cat <<'EOF' | write_if_absent .gitignore
node_modules/
dist/
build/
target/
*.log
.DS_Store
.env
EOF

  # ---------- docs/ human guide (Chinese, NOT auto-loaded) ----------
  mkdir -p docs
  cat <<'__GUIDE_ZH__' | subst | write_if_absent docs/GUIDE.zh.md
# @@PROJECT_NAME@@ 项目指南（人类阅读）

> ⚠️ 非权威文档，仅供人类阅读。
> AI 自动加载的文件（根/各栈 `CLAUDE.md`、`AGENTS.md`、`.claude/rules/*.md`）均为英文且为真相源；
> 本文件与它们不一致时，以英文文件为准。本文件位于 `docs/`，不在任何自动加载路径中（Claude/Codex 不加载 docs/）。

## 这是什么
本项目用 Loop Engineering 框架协作开发：OpenSpec 定方向（WHAT）、Superpowers 强纪律（HOW）、Harness 编协作（WHO）。
每个功能走闭环：propose → apply → verify → archive。

## 去哪找什么
| 你想找的 | 位置 | 语言 |
|:--|:--|:--|
| 项目业务/架构/模块图 | `openspec/project.md` | 英文 |
| API/数据/错误契约 | `openspec/specs/` | 英文 |
| 各技术栈编码规范 | `<stack>/CLAUDE.md` | 英文 |
| 命名等通用规则 | `.claude/rules/*.md` | 英文 |
| 斜杠命令用法 | `.claude/commands/opsx/` | 英文 |
| 验证 skill/命令 | Claude: `.claude/commands/opsx/verify.md`; Codex: `.codex/skills/openspec-verify/` | 英文 |
| 构建测试配置（验证用） | `openspec/verify.config.yaml` | 英文 |
| 本人类导览 | `docs/GUIDE.zh.md`（本文件） | 中文 |

## 日常工作流（中文口语版）
1. 想做新功能 → 说"我要加 xxx 功能"或 `/opsx:propose <名字>`，AI 先澄清需求再写 spec
2. 实施 → `/opsx:apply <名字>`，AI 按 TDD 逐任务实现，每任务后跑构建检查
3. 验证 → `/opsx:verify <名字>`，跑三层（构建/规格对齐/测试），生成 `verify.md`
4. 归档 → `/opsx:archive <名字>`，检查 `verify.md` 门禁后归档

## 跨栈功能协调（前后端联动）
当一个功能跨多个栈（如前端+后端分属独立仓库），单栈 change 不够--前端 agent 按跨域禁令正确排除后端，但"声明的后端依赖"没有归属会被静默丢失（没人创建对应的兄弟 change）。OpenSpec 1.6.0 移除了原生 initiative/workspace，脚手架改用 LoopForge 约定，已为 ≥2 栈自动建好：
- **协调文档**（`openspec/coordination/`）已自动建立 -- 跨栈"父级"（共享设计/决策 + 各栈 change 登记表），CLI 不解析
- **子级 change**：各栈 `openspec new change <名> --goal "<功能>"`，用 `--goal` 软标签关联到功能
- **登记**：把各栈 change 填进 `openspec/coordination/<功能>.md` 的登记表
- **完成门禁**：所有登记的 change 都 verify PASS -> 功能才算完 -> 各自归档
- **协调会话**：`openspec workset open <项目> --tool code`（IDE 打开所有栈；1.6.0 暂时禁用 agent 直接打开，需手动在项目根启动 codex/claude）

## 约定速记
- 先 spec 后代码：没有 spec 不写代码
- 跨域禁止：后端 agent 不写前端代码，反之亦然
- 自动加载文件只写英文：中文说明写在本文件，避免每会话浪费 token
- 验证凭证：`verify.md` 是归档的通行证

## 常用命令
- `scaffold.sh check ./<project>` - 审计项目合规度（含 O7 中文检查）
- `scaffold.sh tokens ./<project>` - 测自动加载文件 token 数与中文占比
- `scaffold.sh list` - 预览脚手架生成哪些文件

> 维护提示：英文 auto-loaded 文件改了，按需把关键点同步到本文件即可，不必逐行对照。
__GUIDE_ZH__

  # ---------- done ----------
  echo ""
  echo "==> Scaffold complete: $TARGET_DIR"
  echo ""
  echo "Next steps:"
  echo "  1. cd $TARGET_DIR"
  if [[ $RUN_INIT -eq 0 ]]; then echo "  2. openspec init   (generate slash commands + base skills)"; fi
  echo "  3. Install on-demand Claude skills: Superpowers set (brainstorm / writing-plans / executing-plans / code-review / verification)"
  if has frontend || has frontend-mobile; then echo "     + frontend-design skill"; fi
  echo "  4. Fill [BRACKETS] placeholders in openspec/project.md, openspec/specs/*, and per-stack CLAUDE.md/AGENTS.md"
  echo "  5. Edit openspec/verify.config.yaml - set each stack build/test commands for /opsx:verify (L1 build / L3 test)"
  echo "  6. Run the loopforge audit (30 checks) to verify maturity"
}

# ---------------- subcommand: check (自检 + LoopForge audit) ----------------
cmd_check() {
  [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { echo "Usage: scaffold.sh check [project-dir]  # self-check + LoopForge audit"; exit 0; }
  local dir="${1:-}"
  local pass=0 partial=0 fail=0 total=0
  report() {
    local s="$1" label="$2"
    total=$((total+1))
    case "$s" in
      PASS)    pass=$((pass+1));    printf "  [ PASS ]    %s\n" "$label";;
      PARTIAL) partial=$((partial+1)); printf "  [PARTIAL]   %s\n" "$label";;
      *)       fail=$((fail+1));    printf "  [ FAIL ]    %s\n" "$label";;
    esac
  }
  json_ok() { python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$1" >/dev/null 2>&1; }

  echo "==> loopforge self-check"
  echo "  script: $0"
  echo "  bash:   ${BASH_VERSION:-unknown}"
  if bash -n "$0" 2>/dev/null; then report PASS "script syntax (bash -n)"; else report FAIL "script syntax (bash -n)"; fi
  if command -v openspec >/dev/null 2>&1; then
    report PASS "openspec CLI: $(openspec --version 2>/dev/null || echo present)"
  else
    report FAIL "openspec CLI (install: npm i -g @fission-ai/openspec@latest)"
  fi
  if command -v node >/dev/null 2>&1; then report PASS "node: $(node --version 2>/dev/null)"; else report FAIL "node (required by openspec)"; fi

  if [[ -z "$dir" ]]; then
    echo ""
    echo "==> No project directory specified - self-check only."
    echo "    Audit a project with: scaffold.sh check <project-dir>"
    _score "$pass" "$partial" "$fail" "$total"
    exit 0
  fi
  [[ -d "$dir" ]] || { echo "Error: not a directory: $dir" >&2; exit 1; }

  echo ""
  echo "==> LoopForge compliance audit: $dir"
  cd "$dir"

  # E2 / O1 / O3 / O4 / O5 / O6
  if [[ -d openspec && -d openspec/specs && -d openspec/changes ]]; then report PASS "E2 openspec/ (specs/ + changes/)"; else report FAIL "E2 openspec/ structure (run: openspec init / scaffold.sh)"; fi
  local specs=0
  [[ -f openspec/specs/api/spec.md ]] && specs=$((specs+1))
  [[ -f openspec/specs/data/spec.md ]] && specs=$((specs+1))
  [[ -f openspec/specs/errors/spec.md ]] && specs=$((specs+1))
  case $specs in 3) report PASS "O1 specs api/data/errors";; 1|2) report PARTIAL "O1 specs ($specs/3: api/data/errors)";; *) report FAIL "O1 specs api/data/errors";; esac
 if [[ -f openspec/changes/_template/proposal.md && -f openspec/changes/_template/specs/capability/spec.md ]]; then report PASS "O3 changes/_template (proposal+spec)"; else report FAIL "O3 changes/_template"; fi
  # O4 - canonical archive is openspec/archive/; archives misplaced in
  # openspec/changes/archive/ is common drift - a dir-existence-only check hides it.
  local _o4real=0 _o4mis=0 _o4e
  if [[ -d openspec/archive ]]; then
    for _o4e in openspec/archive/*; do
      [[ -e "$_o4e" ]] || continue
      case "$(basename "$_o4e")" in .gitkeep|README.md|.DS_Store) continue;; esac
      _o4real=$((_o4real+1))
    done
  fi
  if [[ -d openspec/changes/archive ]]; then
    for _o4e in openspec/changes/archive/*; do
      [[ -e "$_o4e" ]] || continue
      case "$(basename "$_o4e")" in .gitkeep|README.md|.DS_Store) continue;; esac
      _o4mis=$((_o4mis+1))
    done
  fi
  if (( _o4mis > 0 )); then
    report PARTIAL "O4 archive/ ($_o4mis misplaced in changes/archive/ - move to openspec/archive/)"
  elif [[ -d openspec/archive ]]; then
    report PASS "O4 archive/ ($_o4real archived)"
  else
    report FAIL "O4 archive/ (run: openspec init / scaffold.sh)"
  fi
 [[ -f openspec/project.md ]] && report PASS "O5 openspec/project.md" || report FAIL "O5 openspec/project.md"
  [[ -f openspec/README.md ]] && report PASS "O6 openspec/README.md" || report FAIL "O6 openspec/README.md"

  # O8 WHEN/THEN
  if grep -rq 'WHEN' openspec/changes openspec/specs 2>/dev/null; then report PASS "O8 WHEN/THEN scenarios present"; else report PARTIAL "O8 no WHEN/THEN found (add to specs/changes)"; fi

  # O7 - auto-loaded files English-only (CJK ratio; Chinese wastes tokens every session)
  if ! command -v python3 >/dev/null 2>&1; then
    report PARTIAL "O7 auto-loaded English (no python3 to scan CJK)"
  else
    local _af _cjk_over=0 _cjk_total=0 _worst="" _wpct=0 _f _pct
    _af="$(autoloaded_md)"
    if [[ -z "$_af" ]]; then
      report PARTIAL "O7 auto-loaded English (no auto-loaded .md found)"
    else
      while IFS= read -r _f; do
        [[ -f "$_f" ]] || continue
        _cjk_total=$((_cjk_total+1))
        _pct="$(python3 - "$_f" <<'PY'
import sys,re
t=open(sys.argv[1],encoding='utf-8',errors='replace').read()
cjk=len(re.findall(r'[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]',t))
tot=len(t)
print('0' if tot==0 else str(round(100*cjk/tot,1)))
PY
)"
        if awk -v p="$_pct" -v t="$CJK_THRESHOLD" 'BEGIN{exit !(p>t)}'; then
          _cjk_over=$((_cjk_over+1))
          if awk -v p="$_pct" -v w="$_wpct" 'BEGIN{exit !(p>w)}'; then _wpct="$_pct"; _worst="$_f"; fi
        fi
      done <<< "$_af"
      if [[ $_cjk_over -eq 0 ]]; then
        report PASS "O7 auto-loaded files English-only (0/$_cjk_total over ${CJK_THRESHOLD}% CJK)"
      else
        report PARTIAL "O7 auto-loaded files have Chinese ($_cjk_over/$_cjk_total over ${CJK_THRESHOLD}% CJK; worst: $_worst ${_wpct}%)"
      fi
    fi
  fi

  # E3 / S6 / S4 / S8 / S5
  if [[ -d .claude/commands/opsx ]]; then
    report PASS "E3 .claude/commands/opsx/ (Claude slash commands)"
  elif [[ -d .codex/skills/openspec-propose ]]; then
    report PASS "E3 .codex/skills/openspec-*/ (Codex skills)"
  else
    report FAIL "E3 no opsx commands/skills found (run: openspec init)"
  fi
  # E3+ - verify skill/command (loopforge enhancement: openspec init ships none)
  if [[ -f .claude/commands/opsx/verify.md ]]; then
    report PASS "E3+ verify command (.claude/commands/opsx/verify.md)"
  elif [[ -f .codex/skills/openspec-verify/SKILL.md ]]; then
    report PASS "E3+ verify skill (.codex/skills/openspec-verify/)"
  else
    report PARTIAL "E3+ verify skill missing (re-run scaffold.sh to create)"
  fi
  local _s6=0 _s6note=""
  # S6: permissions config + dangerous-command gating (merged from former H9)
  { [[ -f AGENTS.md ]] && grep -qiE 'sandbox|approval|permission' AGENTS.md; } && { _s6=1; _s6note="AGENTS.md sandbox/approval"; } || true
  { [[ -f AGENTS.md ]] && grep -qiE 'rm -rf|push --force|reset --hard' AGENTS.md; } && { _s6=1; _s6note="${_s6note:+$_s6note + }dangerous-cmd gating"; } || true
  if [[ -f .claude/settings.json ]]; then
    if ! command -v python3 >/dev/null 2>&1; then _s6note="${_s6note:+$_s6note + }settings.json (no python3)"
    elif json_ok .claude/settings.json; then _s6=1; _s6note="${_s6note:+$_s6note + }.claude/settings.json"
      { grep -q 'rm -rf' .claude/settings.json 2>/dev/null && grep -q 'push --force' .claude/settings.json 2>/dev/null; } && _s6note="$_s6note + deny list (rm -rf, push --force)" || true
    else _s6note="settings.json (invalid JSON)"; fi
  fi
  if [[ $_s6 -eq 1 ]]; then report PASS "S6 permissions & dangerous-command gating ($_s6note)"
  else report PARTIAL "S6 permissions (add sandbox/approval + dangerous-cmd gating to AGENTS.md, or .claude/settings.json with allow/deny lists)"; fi
  local _s4=0 rules=0
  { [[ -f AGENTS.md ]] && grep -qiE '## Conventions|## Coding Rules|naming|kebab-case' AGENTS.md; } && _s4=1 || true
  while IFS= read -r _; do rules=$((rules+1)); done < <(find .claude/rules -name '*.md' 2>/dev/null)
  [[ $rules -gt 0 ]] && _s4=1 || true
  if [[ $_s4 -eq 1 ]]; then report PASS "S4 universal conventions (AGENTS.md; .claude/rules/: $rules)"
  else report PARTIAL "S4 conventions (add a Conventions section to AGENTS.md or .claude/rules/)"; fi
  local _s8=0
  { [[ -f AGENTS.md ]] && grep -qiE 'reviewer|coordinator|implementer' AGENTS.md; } && _s8=1 || true
  [[ -f .claude/agents/reviewer.md && -f .claude/agents/coordinator.md ]] && _s8=1 || true
  [[ $_s8 -eq 1 ]] && report PASS "S8 reviewer+coordinator+implementer roles (AGENTS.md / .claude/agents/)" || report PARTIAL "S8 roles (add Reviewer+Coordinator+Implementer to AGENTS.md or .claude/agents/)"
  # S8b - SDD artifacts: prompt templates + progress ledger (subagent-driven development)
  local _sdd=0
  [[ -f openspec/sdd/implementer-prompt.md ]] && _sdd=$((_sdd+1))
  [[ -f openspec/sdd/reviewer-prompt.md ]] && _sdd=$((_sdd+1))
  [[ -f openspec/sdd/progress.md ]] && _sdd=$((_sdd+1))
  if [[ $_sdd -eq 3 ]]; then report PASS "S8b SDD artifacts (implementer/reviewer prompts + progress ledger)"
  elif [[ $_sdd -gt 0 ]]; then report PARTIAL "S8b SDD artifacts (found $_sdd/3: re-run scaffold to generate all openspec/sdd/ templates)"
  else report PARTIAL "S8b SDD artifacts (no openspec/sdd/ - run scaffold to generate SDD templates)"; fi
  # S5 - domain skills. Detect the Superpowers discipline set by skill name so a
  # project that has it installed scores PASS; without it, prompt to install.
  local _s5_ag=0 _s5_cl=0 _s5_super=0 _s5d _s5n
  while IFS= read -r _; do _s5_ag=$((_s5_ag+1)); done < <(find . -mindepth 2 -maxdepth 2 -name AGENTS.md -not -path './openspec/*' -not -path './.claude/*' 2>/dev/null)
  # Check project-level .claude/skills/ AND user-level plugin cache
  while IFS= read -r _s5d; do
    _s5_cl=$((_s5_cl+1)); _s5n="$(basename "$_s5d")"
    case "$_s5n" in
      brainstorming|writing-plans|executing-plans|requesting-code-review|receiving-code-review|verification-before-completion|using-superpowers|test-driven-development|systematic-debugging|subagent-driven-development|dispatching-parallel-agents|using-git-worktrees|finishing-a-development-branch|writing-skills) _s5_super=$((_s5_super+1));;
    esac
  done < <(find .claude/skills -mindepth 1 -maxdepth 1 -type d ! -name 'openspec-*' 2>/dev/null)
  # Also check user-level plugin cache (Superpowers may be installed as plugin, not copied to project)
  if [[ $_s5_super -eq 0 ]]; then
    for _p in "$HOME/.claude/plugins/cache"/*/superpowers/*/skills "$HOME/.codex/plugins/cache"/*/superpowers/*/skills; do
      [[ -d "$_p/brainstorming" ]] && { _s5_super=1; break; }
    done
  fi
  if [[ $_s5_ag -gt 0 || $_s5_super -gt 0 ]]; then report PASS "S5 domain guidance (per-stack AGENTS.md: $_s5_ag${_s5_super:+; Superpowers: $_s5_super})"
  else report PARTIAL "S5 domain guidance (add deep guidance to per-stack AGENTS.md${_s5_cl:+; or install Superpowers skills for Claude})"; fi

  # S9 - token budget per auto-loaded file (MOD-5a)
  if ! command -v python3 >/dev/null 2>&1; then
    report PARTIAL "S9 token budget (no python3 to measure)"
  else
    local _af _tok_max=0 _tok_worst="" _f _tok
    _af="$(autoloaded_md)"
    if [[ -z "$_af" ]]; then
      report PASS "S9 token budget (no auto-loaded files)"
    else
      while IFS= read -r _f; do
        [[ -f "$_f" ]] || continue
        _tok="$(python3 - "$_f" <<'PY'
import sys,re
t=open(sys.argv[1],encoding='utf-8',errors='replace').read()
cjk=len(re.findall(r'[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]',t))
print(cjk + (len(t)-cjk)//4)
PY
)"
        if [[ $_tok -gt $_tok_max ]]; then _tok_max=$_tok; _tok_worst="$_f"; fi
      done <<< "$_af"
      if [[ $_tok_max -le ${TOKEN_THRESHOLD} ]]; then
        report PASS "S9 token budget (max ${_tok_max} tokens in ${_tok_worst}; threshold ${TOKEN_THRESHOLD})"
      else
        report PARTIAL "S9 token budget exceeded (${_tok_max} tokens in ${_tok_worst}; threshold ${TOKEN_THRESHOLD}; trim or translate to English)"
      fi
    fi
  fi

  # H1 / H5 / H2
  local ag=0
  while IFS= read -r _; do ag=$((ag+1)); done < <(find . -mindepth 2 -maxdepth 2 -name CLAUDE.md -not -path './.claude/*' 2>/dev/null)
  [[ $ag -gt 0 ]] && report PASS "H1 per-stack Agent CLAUDE.md ($ag)" || report PARTIAL "H1 no per-stack Agent CLAUDE.md"
  [[ -f AGENTS.md ]] && report PASS "AGENTS.md Codex harness entry present" || report PARTIAL "AGENTS.md (Codex entry) - add for Codex support"
  if [[ -f CLAUDE.md ]]; then
    local lc; lc=$(wc -l < CLAUDE.md | tr -d ' ')
    if [[ $lc -le 120 ]]; then report PASS "H5 root CLAUDE.md nav hub ($lc lines)"; else report PARTIAL "H5 root CLAUDE.md ($lc lines > 120; trim to nav hub)"; fi
  else report FAIL "H5 root CLAUDE.md (missing)"; fi
  if grep -rq 'openspec/specs' . --include='*.md' 2>/dev/null; then report PASS "H2 agents reference openspec/specs"; else report PARTIAL "H2 no openspec/specs references found"; fi
  # H9 removed: merged into S6 (permissions & dangerous-command gating)

  # H-legacy: technical-debt entries (MOD-6c)
  # Having [DEBT] entries is Iron-Law compliant (explicitly tracked, not silent).
  # Report PASS either way; the message notes tracked debt for revisit scheduling.
  # Exclude _template/ - its placeholder [DEBT] line is an example, not real debt.
  local _debt=0
  _debt=$({ find openspec/changes -name debt.md ! -path '*/_template/*' -exec grep -h '\[DEBT\]' {} + 2>/dev/null || true; } | wc -l | tr -d ' ')
  if [[ $_debt -gt 0 ]]; then
    report PASS "H-legacy: $_debt tracked debt entries (Iron Law compliant - revisit when test harness added)"
  else
    report PASS "H-legacy: no outstanding debt entries"
  fi

  echo ""
  _score "$pass" "$partial" "$fail" "$total"
  echo "    Tip: ask the loopforge skill for a full 30-check audit + remediation plan."
}

_score() {
  local p="$1" pa="$2" f="$3" t="$4" pct=0 level="Pre-build"
  [[ $t -gt 0 ]] && pct=$(( (p*100) / t ))
  if   [[ $pct -ge 90 ]]; then level="Industrial"
  elif [[ $pct -ge 66 ]]; then level="Quality"
  elif [[ $pct -ge 33 ]]; then level="Basic"; fi
  echo "==> Result: $p/$t passed ($pct%) · $pa partial · $f failed"
  echo "    Maturity level: $level"
}

# ---------------- subcommand: list (preview manifest) ----------------

cmd_tokens() {
  [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { echo "Usage: scaffold.sh tokens [project-dir]  # token audit of auto-loaded files"; exit 0; }
  local dir="${1:-.}"
  [[ -d "$dir" ]] || { echo "Error: not a directory: $dir" >&2; exit 1; }
  command -v python3 >/dev/null 2>&1 || { echo "Error: python3 required for token audit" >&2; exit 1; }
  echo "==> Token audit: $dir (auto-loaded files only)"
  cd "$dir"
  local _af; _af="$(autoloaded_md)"
  [[ -z "$_af" ]] && { echo "  (no auto-loaded .md found)"; exit 0; }
  local _engine="heuristic"
  python3 -c 'import tiktoken' 2>/dev/null && _engine="tiktoken cl100k_base"
  echo "  engine: $_engine   (pip install tiktoken for exact counts)"
  echo ""
  printf "  %-42s %8s %7s  %s\n" "file" "tokens" "CJK%" "note"
  local _total=0 _f _tok _pct _note
  while IFS= read -r _f; do
    [[ -f "$_f" ]] || continue
    read -r _tok _pct < <(python3 - "$_f" "$_engine" <<'PY'
import sys,re
t=open(sys.argv[1],encoding='utf-8',errors='replace').read()
cjk=len(re.findall(r'[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]',t))
tot=len(t)
pct=0 if tot==0 else round(100*cjk/tot,1)
if 'tiktoken' in sys.argv[2]:
    import tiktoken
    n=len(tiktoken.get_encoding('cl100k_base').encode(t))
else:
    n=cjk + (tot-cjk)//4
print(n, pct)
PY
)
    _total=$((_total+_tok))
    _note=""
    awk -v p="$_pct" -v t="$CJK_THRESHOLD" 'BEGIN{exit !(p>t)}' && _note="!! Chinese"
    awk -v n="$_tok" -v th="${TOKEN_THRESHOLD}" 'BEGIN{exit !(n>th)}' && _note="${_note:+$_note }!! over budget"
    printf "  %-42s %8s %6s%%  %s\n" "$_f" "$_tok" "$_pct" "$_note"
  done <<< "$_af"
  echo ""
  echo "  TOTAL auto-loaded: $_total tokens/session"
  echo "  Files marked '!! Chinese' (CJK>${CJK_THRESHOLD}%) are O7 overhead — translate to English to recover."
  echo "  Files marked !! over budget exceed TOKEN_THRESHOLD=${TOKEN_THRESHOLD} tokens (S9 check)."
  echo "  Re-run after translating to confirm the drop."
}

cmd_list() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --stacks)        STACKS="$2"; shift 2;;
      --backend-dir)   BACKEND_DIR="$2"; shift 2;;
      --frontend-dir)  FRONTEND_DIR="$2"; shift 2;;
      --mobile-dir)    MOBILE_DIR="$2"; shift 2;;
      --dir|--tools|--no-init) shift 2 2>/dev/null || shift;;  # ignored (list uses temp dir)
      -h|--help)       echo "Usage: scaffold.sh list [--stacks <list>] [--backend-dir <n>] [--frontend-dir <n>] [--mobile-dir <n>]"; exit 0;;
      *) shift;;  # silently consume positional args (e.g. project name)
    esac
  done
  local tmp; tmp="$(mktemp -d)"
  PROJECT_NAME="preview"
  TARGET_DIR="$tmp"
  RUN_INIT=0
  generate_scaffold >/dev/null 2>&1
  echo "==> Preview: files scaffold.sh would generate"
  echo "    stacks: $STACKS"
  echo "    (written to a temp dir, then discarded)"
  echo "    note: openspec init creates tool-specific files (.claude/commands/opsx/ for Claude; .codex/skills/ for Codex)"
  echo ""
  ( cd "$tmp" && find . -type f | sed 's|^\./||' | sort )
  echo ""
  echo "Count: $(cd "$tmp" && find . -type f | wc -l | tr -d ' ') files"
  rm -rf "$tmp"
}


cmd_validate() {
  [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { echo "Usage: scaffold.sh validate <change-dir>  # validate artifact structure (proposal/spec/design/tasks)"; exit 0; }
  local dir="${1:-}"
  [[ -n "$dir" ]] || { echo "Usage: scaffold.sh validate <change-dir>" >&2; exit 2; }
  [[ -d "$dir" ]] || { echo "Error: not a directory: $dir" >&2; exit 1; }
  command -v python3 >/dev/null 2>&1 || { echo "Error: python3 required" >&2; exit 1; }
  local script=""
  local abs_dir; abs_dir="$(cd "$dir" && pwd)"
  local cur="$abs_dir"
  while [[ "$cur" != "/" && -z "$script" ]]; do
    [[ -f "$cur/openspec/validate-artifacts.py" ]] && script="$cur/openspec/validate-artifacts.py"
    cur="$(dirname "$cur")"
  done
  [[ -z "$script" && -f "$abs_dir/../validate-artifacts.py" ]] && script="$abs_dir/../validate-artifacts.py"
  if [[ -z "$script" ]]; then
    echo "Error: validate-artifacts.py not found. Run scaffold.sh first to generate it." >&2
    exit 2
  fi
  echo "==> Validating: $dir"
  python3 "$script" "$dir"
}


cmd_changes() {
  [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { echo "Usage: scaffold.sh changes [project-dir]  # list all changes and their phase/status"; exit 0; }
  local proj="${1:-.}"
  local changes_dir="$proj/openspec/changes"
  [[ -d "$changes_dir" ]] || { echo "No openspec/changes/ found in $proj"; exit 0; }
  echo "Changes in: $proj"
  echo ""
  printf "  %-30s %-14s %-12s %-12s\n" "CHANGE" "PHASE" "TASKS" "UPDATED"
  printf "  %-30s %-14s %-12s %-12s\n" "------" "-----" "-----" "-------"
  local found=0
  for d in "$changes_dir"/*/; do
    [[ -d "$d" ]] || continue
    local name; name="$(basename "$d")"
    [[ "$name" == "_template" ]] && continue
    local state="$d/loop-state.yaml"
    [[ -f "$state" ]] || state="$proj/openspec/loop-state.yaml"
    local phase="?" tasks="?" updated="?"
    if [[ -f "$state" ]]; then
      phase=$(grep '^phase:' "$state" 2>/dev/null | awk '{print $2}' || echo "?")
      local done total
      done=$(grep '^tasks_done:' "$state" 2>/dev/null | awk '{print $2}' || echo "0")
      total=$(grep '^tasks_total:' "$state" 2>/dev/null | awk '{print $2}' || echo "0")
      tasks="${done:-0}/${total:-0}"
      updated=$(grep '^last_updated:' "$state" 2>/dev/null | awk '{print $2}' || echo "-")
    else
      if [[ -f "$d/execution-contract.md" ]]; then phase="applying?"
      elif [[ -f "$d/proposal.md" ]]; then phase="proposing"
      else phase="empty"; fi
    fi
    printf "  %-30s %-14s %-12s %-12s\n" "$name" "$phase" "$tasks" "$updated"
    found=1
  done
  [[ $found -eq 0 ]] && echo "  (no active changes)"
  echo ""
  echo "Phases: proposing -> applying -> verifying -> archived | abandoned"
}

cmd_doctor() {
  [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { echo "Usage: scaffold.sh doctor [project-dir]  # health check: deps, scaffold, guard, verify config"; exit 0; }
  local proj="${1:-.}"
  local pass=0 fail=0 warn=0
  _dr_ok()   { printf "  \xe2\x9c\x93 %s\n" "$1"; pass=$((pass+1)); }
  _dr_fail() { printf "  \xe2\x9c\x97 %s\n" "$1"; fail=$((fail+1)); }
  _dr_warn() { printf "  \xe2\x9a\xa0 %s\n" "$1"; warn=$((warn+1)); }
  echo "LoopForge Doctor - health check"
  echo "Project: $proj"
  echo ""
  echo "== Dependencies =="
  command -v node >/dev/null 2>&1 && _dr_ok "node $(node --version 2>/dev/null)" || _dr_fail "node not found (required by openspec)"
  command -v python3 >/dev/null 2>&1 && _dr_ok "python3 $(python3 --version 2>&1 | awk '{print $2}')" || _dr_warn "python3 not found (schema validation falls back to bash)"
  command -v git >/dev/null 2>&1 && _dr_ok "git $(git --version 2>/dev/null | awk '{print $3}')" || _dr_fail "git not found"
  command -v rg >/dev/null 2>&1 && _dr_ok "ripgrep (rg) available" || _dr_warn "ripgrep not found (verify L2 uses grep fallback)"
  command -v openspec >/dev/null 2>&1 && _dr_ok "openspec CLI $(openspec --version 2>/dev/null || echo present)" || _dr_fail "openspec CLI not found (install: npm i -g @fission-ai/openspec@latest)"
  echo ""
  echo "== LoopForge structure =="
  [[ -d "$proj/openspec" ]] && _dr_ok "openspec/ directory" || _dr_fail "openspec/ missing (run scaffold.sh)"
  [[ -f "$proj/openspec/guard.sh" ]] && _dr_ok "guard.sh (phase gate)" || _dr_warn "guard.sh missing (re-run scaffold.sh)"
  [[ -f "$proj/openspec/loop-state.yaml" ]] && _dr_ok "loop-state.yaml (state machine)" || _dr_warn "loop-state.yaml missing"
  [[ -f "$proj/openspec/ensure-branch.sh" ]] && _dr_ok "ensure-branch.sh (worktree isolation)" || _dr_warn "ensure-branch.sh missing"
  [[ -f "$proj/openspec/ensure-contract-fresh.sh" ]] && _dr_ok "ensure-contract-fresh.sh (contract freshness)" || _dr_warn "ensure-contract-fresh.sh missing"
  [[ -f "$proj/openspec/build-contract.sh" ]] && _dr_ok "build-contract.sh (contract auto-generation)" || _dr_warn "build-contract.sh missing (re-run scaffold.sh)"
  [[ -f "$proj/openspec/validate-artifacts.py" ]] && _dr_ok "validate-artifacts.py (schema validation)" || _dr_warn "validate-artifacts.py missing"
  [[ -f "$proj/openspec/verify.config.yaml" ]] && _dr_ok "verify.config.yaml (local L1 build / L3 test commands)" || _dr_warn "verify.config.yaml missing (L1/L3 will prompt to create)"
  [[ -d "$proj/openspec/sdd" ]] && _dr_ok "sdd/ (subagent templates)" || _dr_warn "sdd/ missing (SDD not available)"
  echo ""
  echo "== Entry files =="
  [[ -f "$proj/CLAUDE.md" ]] && _dr_ok "CLAUDE.md (Claude Code entry)" || _dr_warn "CLAUDE.md missing"
  [[ -f "$proj/AGENTS.md" ]] && _dr_ok "AGENTS.md (Codex entry)" || _dr_warn "AGENTS.md missing"
  echo ""
  echo "== Syntax =="
  bash -n "$0" 2>/dev/null && _dr_ok "scaffold.sh syntax valid" || _dr_fail "scaffold.sh syntax error"
  [[ -f "$proj/openspec/guard.sh" ]] && bash -n "$proj/openspec/guard.sh" 2>/dev/null && _dr_ok "guard.sh syntax valid" || true
  echo ""
  echo "Result: $pass pass, $warn warn, $fail fail"
  [[ $fail -eq 0 ]] && echo "Healthy" || echo "Issues found"
  [[ $fail -eq 0 ]]
}


cmd_version() {
  echo "LoopForge $LOOPFORGE_VERSION"
  echo "  scaffold: $(basename "$0")"
  echo "  bash:     ${BASH_VERSION:-unknown}"
  command -v openspec >/dev/null 2>&1 && echo "  openspec: $(openspec --version 2>/dev/null || echo present)" || echo "  openspec: not installed"
  command -v node >/dev/null 2>&1 && echo "  node:     $(node --version 2>/dev/null)" || true
}

cmd_contract() {
  local force=""
  [[ "${1:-}" == "--force" ]] && { force="--force"; shift; }
  local change_dir="${1:-}"
  [[ -n "$change_dir" ]] || { echo "Usage: scaffold.sh contract [--force] <change-dir>" >&2; exit 1; }

  # Resolve to absolute path
  change_dir="$(cd "$change_dir" 2>/dev/null && pwd)" || { echo "Error: not a directory: $change_dir" >&2; exit 1; }
  [[ -d "$change_dir" ]] || { echo "Error: not a directory: $change_dir" >&2; exit 1; }

  # Find openspec/ by searching upward
  local openspec_dir=""
  local cur="$change_dir"
  while [[ "$cur" != "/" ]]; do
    if [[ -d "$cur/openspec" ]]; then openspec_dir="$cur/openspec"; break; fi
    cur="$(dirname "$cur")"
  done

  if [[ -z "$openspec_dir" ]]; then
    echo "Error: openspec/ not found (searched upward from $change_dir)" >&2
    exit 1
  fi

  local build_sh="$openspec_dir/build-contract.sh"
  if [[ ! -f "$build_sh" ]]; then
    echo "Error: build-contract.sh not found at $build_sh" >&2
    echo "  Re-run scaffold.sh to generate it." >&2
    exit 1
  fi

  echo "Building execution-contract.md from planning artifacts..."
  bash "$build_sh" $force "$change_dir"
  local rc=$?
  if [[ $rc -eq 0 ]]; then
    echo ""
    echo "Contract generated. Next steps:"
    echo "  1. Review AI-marked sections (<!-- AI: ... -->) in execution-contract.md"
    echo "  2. Run: bash openspec/ensure-contract-fresh.sh --update $change_dir"
    echo "  3. Begin apply phase (guard.sh will check contract freshness)"
  fi
  exit $rc
}

cmd_restructure() {
  local proj="${1:-.}"
  [[ -d "$proj" ]] || { echo "Error: not a directory: $proj" >&2; exit 1; }

  # Find root entry file
  local root_file=""
  for f in "$proj/CLAUDE.md" "$proj/AGENTS.md"; do
    [[ -f "$f" ]] && { root_file="$f"; break; }
  done
  [[ -n "$root_file" ]] || { echo "Error: no CLAUDE.md or AGENTS.md found in $proj" >&2; exit 1; }

  local total_lines
  total_lines=$(wc -l < "$root_file" | tr -d ' ')
  echo "================================================"
  echo "  LoopForge Restructure Analysis"
  echo "================================================"
  echo "Root file:    $root_file"
  echo "Total lines:  $total_lines"
  echo ""

  # --- Phase 1: Detect stacks by keyword scan ---
  local has_backend=0 has_frontend=0 has_mobile=0
  grep -qiE 'mvn|gradle|java[ _]|spring|mybatis|maven' "$root_file" && has_backend=1
  grep -qiE 'pnpm|npm|yarn|vue|react|vite|webpack|element|antd|tailwind' "$root_file" && has_frontend=1
  grep -qiE 'flutter|react-native|swift|uikit|kotlin.*android|expo' "$root_file" && has_mobile=1

  echo "--- Detected stacks ---"
  [[ $has_backend  -eq 1 ]] && echo "  [x] backend  (Java/Spring/mvn/gradle)"
  [[ $has_frontend -eq 1 ]] && echo "  [x] frontend (Vue/React/pnpm/npm)"
  [[ $has_mobile   -eq 1 ]] && echo "  [x] mobile   (Flutter/RN/Swift)"
  [[ $has_backend  -eq 0 && $has_frontend -eq 0 && $has_mobile -eq 0 ]] && echo "  [ ] no stacks detected by keyword (may need manual classification)"
  echo ""

  # --- Phase 2: Classify sections ---
  echo "--- Section classification ---"
  echo ""
  printf "%-6s %-40s %s\n" "Line" "Header" "Suggested target"
  printf "%-6s %-40s %s\n" "----" "------" "----------------"

  while IFS= read -r rawline; do
    local lineno header target section_content
    lineno=$(echo "$rawline" | cut -d: -f1)
    header=$(echo "$rawline" | cut -d: -f2-)
    [[ -z "$header" ]] && continue

    # Peek at section content until next ## header (max 15 lines)
    section_content=$(sed -n "$((lineno+1)),$((lineno+15))p" "$root_file" 2>/dev/null | sed '/^## /q' || true)

    # Classify: check header text first (more reliable), then content keywords
    target=""
    if echo "$header" | grep -qiE 'business|context|project|overview|项目|业务'; then
      target="root (nav hub) + project.md"
    elif echo "$header" | grep -qiE 'api|endpoint|route|接口'; then
      target="specs/api/spec.md"
    elif echo "$header" | grep -qiE 'error|错误|code'; then
      target="specs/errors/spec.md"
    elif echo "$header" | grep -qiE 'data|model|entity|数据|模型'; then
      target="specs/data/spec.md"
    elif echo "$header" | grep -qiE 'convention|naming|rule|规范|命名|standard'; then
      target="rules/ or specs/"
    elif echo "$header" | grep -qiE 'build|command|命令|构建'; then
      # Build commands: check which tools are present
      local _has_be=0 _has_fe=0
      echo "$section_content" | grep -qiE 'mvn|gradle|maven' && _has_be=1
      echo "$section_content" | grep -qiE 'pnpm|npm|yarn' && _has_fe=1
      if [[ $_has_be -eq 1 && $_has_fe -eq 1 ]]; then
        target="split by tool (backend+frontend agents)"
      elif [[ $_has_be -eq 1 ]]; then
        target="backend agent"
      elif [[ $_has_fe -eq 1 ]]; then
        target="frontend agent"
      else
        target="root (build commands)"
      fi
    elif echo "$header" | grep -qiE 'backend|后端|java|spring'; then
      target="backend agent"
    elif echo "$header" | grep -qiE 'frontend|前端|vue|react'; then
      target="frontend agent"
    elif echo "$header" | grep -qiE 'mobile|移动|flutter|react-native'; then
      target="mobile agent"
    elif echo "$section_content" | grep -qiE 'mvn|gradle|spring|mybatis|maven'; then
      target="backend agent"
    elif echo "$section_content" | grep -qiE 'pnpm|npm|yarn|vue|react|vite|element|antd|tailwind'; then
      target="frontend agent"
    elif echo "$section_content" | grep -qiE 'flutter|react-native|swift|kotlin.*android'; then
      target="mobile agent"
    else
      target="root or rules/"
    fi

    # Trim header for display
    local disp_header="$header"
    [[ ${#disp_header} -gt 38 ]] && disp_header="${disp_header:0:35}..."
    printf "%-6s %-40s %s\n" "$lineno" "$disp_header" "$target"
  done < <(grep -n '^## \|^### ' "$root_file")

  echo ""

  # --- Phase 3: Complexity assessment ---
  echo "--- Complexity assessment ---"
  if [[ $total_lines -gt 250 ]]; then
    echo "  [HIGH] Root file is $total_lines lines (>250). Splitting is strongly recommended."
  elif [[ $total_lines -gt 120 ]]; then
    echo "  [MED] Root file is $total_lines lines (>120). Consider splitting."
  else
    echo "  [LOW] Root file is $total_lines lines (<=120). May not need splitting."
  fi

  local stack_count=$(( has_backend + has_frontend + has_mobile ))
  if [[ $stack_count -gt 1 ]]; then
    echo "  [MULTI-STACK] $stack_count stacks detected. Per-stack agents recommended."
  elif [[ $stack_count -eq 1 ]]; then
    echo "  [SINGLE-STACK] Only 1 stack. Add Role + NEVER + Superpowers + TDD to existing file."
  fi
  echo ""

  # --- Phase 4: Migration plan ---
  echo "--- Migration plan ---"
  echo "  1. Review the classification table above"
  echo "  2. AI: extract content blocks into their target files (semantic step)"
  echo "  3. Run 'scaffold.sh <project> --no-init' to generate openspec/ + agent skeletons"
  echo "  4. Rewrite root entry file as nav hub (<=120 lines)"
  echo "  5. Verify: no content lost, no duplication, cross-domain prohibition in each agent"
  echo ""
  echo "  See SKILL.md 'Mode: Restructure' Phase 1-5 for detailed extraction rules."
}

# ---------------- dispatch ----------------
_subcmd="scaffold"
case "${1:-}" in
  list|--list)                           _subcmd="list";  shift;;
  check|--check|self-check|--self-check) _subcmd="check"; shift;;
  tokens|--tokens)                       _subcmd="tokens"; shift;;
  validate|--validate)                   _subcmd="validate"; shift;;
  changes|--changes)                     _subcmd="changes"; shift;;
  doctor|--doctor)                       _subcmd="doctor"; shift;;
  version|--version|-V)                  _subcmd="version"; shift;;
  contract|--contract)                  _subcmd="contract"; shift;;
  restructure|--restructure)            _subcmd="restructure"; shift;;
esac
case "$_subcmd" in
  list)  cmd_list  "$@"; exit 0;;
  check) cmd_check "$@"; exit 0;;
  tokens) cmd_tokens "$@"; exit 0;;
  validate) cmd_validate "$@"; exit 0;;
  changes) cmd_changes "$@"; exit 0;;
  doctor)  cmd_doctor  "$@"; exit 0;;
  version)     cmd_version     "$@"; exit 0;;
  contract)    cmd_contract    "$@"; exit 0;;
  restructure) cmd_restructure "$@"; exit 0;;
esac

# ---------------- default: scaffold ----------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stacks)        STACKS="$2"; shift 2;;
    --dir)           TARGET_DIR="$2"; shift 2;;
    --backend-dir)   BACKEND_DIR="$2"; shift 2;;
    --frontend-dir)  FRONTEND_DIR="$2"; shift 2;;
    --mobile-dir)    MOBILE_DIR="$2"; shift 2;;
    --tools)         TOOLS="$2"; shift 2;;
    --no-init)       RUN_INIT=0; shift;;
    -h|--help)       usage; exit 0;;
    *)
      if [[ -z "$PROJECT_NAME" ]]; then PROJECT_NAME="$1"
      else echo "Unknown arg: $1" >&2; usage; exit 1; fi
      shift;;
  esac
done

[[ -z "$PROJECT_NAME" ]] && { echo "Error: project name required" >&2; usage; exit 1; }
[[ -z "$TARGET_DIR" ]] && TARGET_DIR="./$PROJECT_NAME"
generate_scaffold
