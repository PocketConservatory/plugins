---
name: delegate
description: Delegate a task to the optimal AI model based on quota pressure and routing rules
user-invocable: true
argument-hint: <task description>
---

# Subtask — Delegate

Delegate a task to the best available AI model. The routing strategy is auto-loaded at session start — it tells the agent when and where to delegate.

**External CLIs:** `codex` (OpenAI) · `codex review` (separate quota) · `gemini` (Google) · `agent` (Cursor, manual-only)

All CLI flags MUST come from cached `--help` output. Never hardcode flags.

## Usage

```
/subtask:delegate <task description>
```

Model hints can appear anywhere in the input:

- `Research caching best practices in Firebase` — auto-routes
- `Review the auth changes using codex` — Codex
- `Use gemini to analyze performance` — Gemini
- `with codex, implement retry logic` — Codex
- `Create a Linear ticket for the billing bug` — Claude (needs MCP)
- `Analyze this with grok` — Agent (Grok only available there)

## Sandbox Rules

Apply the **least access** that satisfies the task. Derive flags from cached `--help`.

| Level | Access | Use When |
|-------|--------|----------|
| 1. Pipe | No filesystem | Self-contained: summarize, parse, generate from provided context |
| 2. Read-only | Read, no writes | Reviews, analysis, advisory needing codebase context |
| 3. Working dir | Read + scoped writes | Implementation within a worktree or temp sandbox |
| 4. Full access | Read + write beyond working dir | Needs config outside worktree (still sandboxed) |

**⛔ NEVER use elevated-permission flags. This is a hard constraint, not a guideline. ⛔**

**If a task cannot be completed within a sandbox, DO NOT delegate it. Fall back to Claude (native subagent) or abandon the delegation entirely. An unsandboxed external CLI invocation is never acceptable — not for any task, any provider, any reason.**

| CLI | Banned flags |
|-----|-------------|
| `codex` | `--dangerously-bypass-approvals-and-sandbox` |
| `gemini` | `-y` / `--yolo`, `--approval-mode yolo` |
| `agent` | `-f` / `--force`, `--sandbox disabled` |

This covers any flag — present or future — that bypasses permission prompts, auto-approves all actions, or disables the sandbox.

If the ideal sandbox level fails on a CLI, try a more relaxed sandbox on the same CLI if safe. If no sandboxed invocation works, do not delegate — use Claude (native subagent) instead.

## Execution

All steps are silent — only the final result is shown to the user.

### 1. Parse Input

Extract **task description** and **model hint** (if any). Match hints case-insensitively: `using <model>`, `use <model>`, `with <model>`. Model names can include variants (e.g., "Codex 5.3 High"). Specific model names (e.g., "grok", "gpt-5.2") resolve by family (OpenAI → `codex`, Google → `gemini`). Models without a native CLI → `agent` if supported.

### 2. CLI Discovery

1. Run `<cli> --help` for the selected CLI and cache output
2. If routing selected `agent`, also run `agent --list-models` and cache

### 3. Route

Model hint present → use that provider unconditionally.

No model hint → classify the task and route by type. Both Codex and Gemini are general-purpose and can handle any task — the chain picks the best fit first, then falls back based on availability:

| Task Type | Fallback Chain | Sandbox Level |
|-----------|---------------|---------------|
| Code analysis, understanding, exploration | Codex → Gemini | Read-only |
| Code changes, implementation, refactoring | Codex → Gemini | Working dir |
| Code review, PR review, diff analysis | Codex Review → Codex → Gemini | Read-only |
| Web search, URL fetching, library research | Gemini → Codex | Pipe |
| Needs MCP tools (Linear, Slack, Notion, etc.) | Claude (native subagent) | N/A |

### 4. Persona (Optional)

If the task maps to an agent role in `.claude/agents/*.md`, read the matching definition and compose it into the prompt. Otherwise skip.

### 5. Launch

**Native subagent** (routed to Claude): spawn with persona + task description.

**External CLI**: derive flags for non-interactive mode, prompt, and sandbox level from cached `--help`. Additional rules:
- Request summarized output for research/analysis/review tasks (not implementation)
- Use text output format (not JSON/stream-JSON)
- Always launch in background (`run_in_background: true`)
- Working directory: relevant worktree path, or monorepo root

### 6. Monitor & Handle

Poll output silently. Kill the process if fatal patterns appear with no new output for ~10s:
- `denied by policy`, `permission error`, `permission denied`
- `quota exhausted`, `exhausted your capacity`
- `error executing tool`, `crash`, `panic`, `fatal`

If output stalls without error patterns, ask the user before killing — it may be legitimately slow.

**On failure:**
- Quota-related → skip to next provider immediately
- Sandbox-related → try relaxed sandbox if safe, otherwise next provider
- Transient (timeout, rate limit) → retry once, then treat as hard failure
- User-specified model → show error, don't fall back
- Auto-routed → fall back silently through priority chain

## Output Format

> **subtask**
> **model:** codex · **reason:** code review · **sandbox:** read-only

```
[model output here — fenced for external CLI, plain markdown for native subagent]
```

On failure, add a status line: `**status:** error — <reason>`.
