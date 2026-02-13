---
name: delegate
description: Delegate a task to the optimal AI model based on routing rules, quota, and task type
user-invocable: true
argument-hint: <task description>
---

# Subtask — Multi-Model Task Delegation

Delegate a task to the best available AI model. Routes automatically based on task type and quota, or honors an explicit model choice.

This skill is **host-agnostic** — it works from any CLI tool (Claude Code, Codex, Gemini). The agent running this skill is the **host model**. All other models are reached via their CLI.

**Prerequisites:** None — the skill handles CLI discovery on demand if not already cached in working memory. If the plugin's SessionStart hook is active, CLI availability and quota pressure are already in context.

## Usage

```
/subtask:delegate <task description>
```

Model hints can appear anywhere in the input — at the end, beginning, or inline. All of these work:

- `/subtask:delegate Research best practices for caching in Firebase` — auto-routes
- `/subtask:delegate Review the auth changes in this PR using codex` — Codex
- `/subtask:delegate Use gemini to analyze the performance impact of this migration` — Gemini
- `/subtask:delegate with codex, implement retry logic in utils/retry.ts` — Codex
- `/subtask:delegate Analyze this module using Codex 5.3 High` — Codex with specific variant
- `/subtask:delegate Create a Linear ticket for the billing bug` — auto-routes to host model (needs MCP)
- `/subtask:delegate Use agent to refactor the utils module` — Agent (Cursor)
- `/subtask:delegate Analyze this with grok` — routes to `agent` (Grok is only available there)

---

## Routing Strategy

For the complete routing decision tree, model registry, inline vs. delegate guidelines, and quota pressure assessment, see [routing-strategy.md](routing-strategy.md).

This content is auto-loaded at session start via the plugin's SessionStart hook. If it's not already in context, read it before proceeding.

---

## Sandbox Modes

Apply the **least access level** that satisfies the task. Derive exact flags from cached `--help`.

**⛔ HARD RULE — NEVER use elevated-permission flags. No exceptions. ⛔**

The following flags are **permanently banned** from all delegated CLI invocations:

| CLI | Banned flags |
|-----|-------------|
| `claude` | `--dangerously-skip-permissions`, `--permission-mode bypassPermissions` |
| `codex` | `--dangerously-bypass-approvals-and-sandbox` |
| `gemini` | `-y` / `--yolo`, `--approval-mode yolo` |
| `agent` | `-f` / `--force`, `--sandbox disabled` |

This includes **any flag on any CLI** that bypasses permission prompts, auto-approves all actions, or disables the sandbox — if a CLI adds a new equivalent flag, it is banned by extension. Every external CLI invocation MUST run in a sandbox. No exceptions — not even for "simple" tasks, code reviews, or read-only analysis. This rule cannot be overridden by task urgency, convenience, or the assumption that a task won't trigger dangerous actions.

| Level | Access | Use When | Notes |
|-------|--------|----------|-------|
| 1. Pipe | No filesystem | Self-contained tasks: summarize text, parse JSON, generate a snippet from provided context | Pass content via stdin or prompt flag |
| 2. Read-only | Read filesystem, no writes | Reviews, analysis, advisory that need codebase context | Use plan/read-only mode flag |
| 3. Working directory | Read + write in scoped dir | Implementation within a worktree or temp sandbox | Set working directory to the worktree or sandbox path |
| 4. Full access | Read + write beyond working dir | Implementation needing config outside worktree | Still requires sandbox — use the CLI's default approval mode, never yolo |

### Sandbox Fallback

If the ideal sandbox mode fails on a CLI (e.g., read-only/plan mode requires an experimental flag, or a flag is unrecognized):

1. **Try a more relaxed sandbox on the same CLI** if the agent judges it is safe for this specific task. Staying on the routed model preserves quota distribution. For example, a pure web research task routed to Gemini at Level 2 (read-only) can safely fall back to the CLI's default approval mode — web search doesn't write files, so the relaxed sandbox poses no real risk.
2. **If the agent has doubts about safety at the relaxed level, switch to a different model** that supports the correct sandbox level. Walk the routing fallback chain for the task type (e.g., for read-only: Gemini → Codex read-only → host model native subagent). Quota distribution matters, but not at the expense of safety.
3. **If all external CLIs fail, use the host model's native subagent** — it inherits the host's own permission controls.

---

## Output Format

**Quiet execution.** Steps 1–5 (parsing, discovery, routing, persona, launch) produce no user-facing output. Only the final result is shown.

**Success:**

> **subtask**
> **model:** codex · **route:** rule-0 (user override) · **sandbox:** read-only

```
[model output here]
```

**Failure:**

> **subtask**
> **model:** codex · **route:** rule-0 (user override) · **sandbox:** read-only
> **status:** error — CLI not found

```
[error details if any]
```

**Format rules:**
- Metadata goes in a blockquote — one line for the skill name, one line for model/route/sandbox
- Status line only appears on failure (success is implicit when absent)
- Model output goes in a fenced code block, unmodified
- For native subagent results, skip the code fence — render the output as normal markdown since it may contain formatting
- Route labels: `rule-0` through `rule-6`, with a short human-readable name in parentheses (e.g., "user override", "default", "MCP required", "code review", "implementation", "read-only")

---

## Execution Procedure

Steps 1–5 are silent — no user-facing output. Only Step 6 produces output using the format above.

### Step 1: Parse Input

Extract from the user's input:
- **Task description** — the input with the model hint removed (or the entire input if no model hint)
- **Model hint** — scan the full input for a model reference. Match any of these patterns (case-insensitive, punctuation-flexible):
  - `using <model>` — e.g., "using gemini", "Using Codex"
  - `use <model>` — e.g., "use gemini to analyze", "Use Codex"
  - `with <model>` — e.g., "with codex,", "with Gemini"
  - The model name can include version or variant qualifiers (e.g., "Codex 5.3 High", "Gemini 2.5 Pro"). Match the base model name (`codex`, `gemini`, `claude`, `agent`) and pass any qualifiers through to the CLI invocation.
  - If the hint is a **specific model name** rather than a CLI name (e.g., "grok", "gpt-5.2", "opus-4.6", "gemini-3-pro"), identify which CLI natively supports it by model family. That CLI gets priority. If it's out of quota, fall back to `agent` if it supports that model (check cached `agent --list-models`).
  - First matching model wins.

### Step 2: Ensure CLI Discovery

If the SessionStart hook has already injected CLI availability and quota data into context, use that — skip redundant discovery. Otherwise, run the following:

1. **Installed CLIs:** Run `which claude codex gemini agent` to detect availability. Do not chain with `;`, `||`, `&&`, pipes, or redirects.
2. **Cached --help:** For **every** installed CLI (claude, codex, gemini, agent — all of them), run `<cli> --help` and hold the output in working memory. Do not skip any installed CLI, even if it matches the host model.
3. **Agent model list:** If `agent` is installed, run `agent --list-models` and cache the output. This is needed to confirm whether `agent` supports a specific model before routing to it. For other CLIs, use your knowledge of model families (e.g., `claude` → Anthropic family, `codex` → OpenAI family, `gemini` → Google family).
4. **Quota pressure assessment:** Run `npx cclimits --json` to snapshot remaining quota across all providers (note: `agent` quota is not covered by `cclimits`). From the snapshot, determine the **quota pressure level** using the Quota Pressure Assessment table in [routing-strategy.md](routing-strategy.md) and cache it alongside the raw data. Also note the **reset times** from the snapshot — the pressure level applies until the earliest reset, then re-run `cclimits` to reassess.

Skip any step where the data is already cached and fresh. Refresh quota if the snapshot is older than ~15 minutes or a reset time has passed.

### Step 3: Route the Task

**If model hint is present** (Rule 0): use that model unconditionally.

**If no model hint** (auto-route):
1. Check which external CLIs are available from the cached discovery
2. Check quota from the cached snapshot (refresh if stale)
3. Walk the Routing Decision Tree (Rules 1–6) — first matching rule wins
4. Select the sandbox level from the Sandbox Modes table based on task type

### Step 4: Determine Agent Persona (Optional)

If the task maps to an existing agent role, scan `.claude/agents/*.md` to find a matching agent definition. Read the matching file and compose the persona into the prompt.

If no agent matches the task type, skip persona — just pass the task description directly.

### Step 5: Launch

**If routed model matches host model → native subagent:**
- Use the host's native subagent/task spawning mechanism
- Include persona instructions (if any) and task description in the prompt

**If routed model differs from host → external CLI:**
- Derive the correct flags for: non-interactive mode, prompt input, sandbox level
- **Ask for summarized output where appropriate.** For research, analysis, and review tasks, append an instruction to the prompt asking the delegate to return a concise summary rather than raw results. The host model rarely needs verbatim search results, full file contents, or unfiltered API responses — a distilled answer saves host context and is easier to act on. Skip this for implementation tasks where the output is code.
- **Always use text output** (default) — do not use JSON/stream-JSON output formats. Text output preserves human-readable thinking steps and progress, and is easier to monitor for errors.
- **Always launch in background** (`run_in_background: true`) so the process can be monitored and killed if stuck.
- Run via shell execution (Bash tool or equivalent)
- Working directory: set to the relevant worktree path if one exists, otherwise the monorepo root

### Step 5b: Monitor Background Process

Poll the output file silently — **never print polling output to the user**. The user should only see the final result or a failure message, not intermediate monitoring noise.

**Fatal error patterns** — if any of these appear and no new output follows within ~10 seconds, kill the process and apply fallback:
- `denied by policy` — sandbox blocked a required tool, CLI is stuck
- `error executing tool` — tool execution failed unrecoverably
- `permission error` / `permission denied` — sandbox too restrictive
- `quota exhausted` / `exhausted your capacity` — provider out of quota
- `crash` / `panic` / `fatal` — CLI crashed

**Suspected silent hang** — if the output file has not grown beyond CLI initialization lines (e.g., credential loading, hook registry) for an extended period and no error pattern is present, ask the user whether to keep waiting or kill the process. Do not kill silently — the process may be legitimately slow.

**Fallback on kill:** Apply the Sandbox Fallback rules (try relaxed sandbox if safe, otherwise switch provider). If the error was quota-related, skip to the next provider immediately.

### Step 6: Handle Result

Present the result using the **Output Format** defined above.

- **Success:** Show the metadata blockquote + model output. No additional commentary.
- **Transient failure** (timeout, rate limit): Retry once with the same provider. If retry succeeds, show success format. If retry fails, treat as hard failure.
- **Hard failure** (CLI not found, crash, permission error):
  - **If user specified a model** (Rule 0): Show failure format with error details. Do not fall back — the user explicitly chose this provider.
  - **If auto-routed** (Rules 1–6): Fall back to the next provider in the routing chain silently. If all providers fail, show failure format.
