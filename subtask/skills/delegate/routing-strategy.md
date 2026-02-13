# Routing Strategy

Auto-loaded at session start by the subtask plugin's SessionStart hook.

---

## Overview

This is a **Claude Code plugin**. Claude (the host) is always the primary model. External CLIs (`codex`, `gemini`) are overflow buckets — work spills into them as Claude's quota fills up.

**Priority order: Claude → Codex → Gemini.** Always. The only variable is *when* to spill.

`agent` (Cursor) is **never auto-routed**. It is only used when the user explicitly requests it or requests a model that only `agent` supports (e.g., Grok).

---

## Model Registry

| Model | CLI | Quota Pool |
|-------|-----|------------|
| Claude | host (native subagent) | Anthropic family (Opus/Sonnet/Haiku) |
| Codex | `codex` | OpenAI family |
| Codex Review | `codex review` | OpenAI family (separate review quota) |
| Gemini | `gemini` | Google family |
| Agent (Cursor) | `agent` | Cursor quota (separate, not measurable) |

**Flag derivation:** All CLI flags MUST come from the cached `--help` output. Never hardcode flags. Consult the cached `--help` to determine flags for: non-interactive mode, sandbox level, prompt input method, and output format.

---

## Routing Rules

Walk top-to-bottom. **First matching rule wins.**

### Rule 0: User Override

If the user specified a **CLI name** (e.g., "using codex", "using gemini", "using agent"), use that CLI unconditionally.

If the user specified a **specific model name** (e.g., "grok", "gpt-5.2", "gemini-3-pro"):
1. Identify the **native CLI** for the model's family (OpenAI → `codex`, Google → `gemini`). Use that CLI with `--model <id>`.
2. If the model doesn't belong to `codex` or `gemini` families (e.g., Grok), check cached `agent --list-models` — if supported, route to `agent`.
3. If no CLI supports the model, report the error to the user.

### Rule 1: MCP Required

Task needs MCP servers (Linear, Notion, Sentry, Amplitude, Figma, Slack, etc.).

→ **Claude (host).** Only the host has MCP access. No fallback.

### Rule 2: Multi-Turn Required

Task requires iterative conversation, back-and-forth reasoning, or interactive debugging.

→ **Claude (host, native subagent).** External CLIs are single-shot.

### Rule 3: Code Review

Task is reviewing code for correctness, quality, security, or patterns.

→ **Codex Review** (separate quota pool — always prefer this regardless of pressure)
→ Fallback: Claude (host) → Gemini in read-only mode

### Rule 4: Bucket Fill (All Other Tasks)

Everything else — implementation, research, analysis, advisory, documentation — follows the same priority based on quota pressure:

| Pressure | Route to | Rationale |
|----------|----------|-----------|
| **Low** (>50%) | Claude (host, inline) | Speed wins. No delegation latency. |
| **Medium** (20–50%) | Codex for multi-step tasks; Claude for simple tasks | Start spilling heavy work to preserve Claude quota |
| **High** (<20%) | Codex for everything delegatable | Reserve Claude for MCP, multi-turn, and displaying results |
| **Critical** (<5%) | Codex → Gemini | Exhaust Codex first, then spill to Gemini |

**Fallback chain at any pressure:** Codex → Gemini → Claude (host, native subagent).

If a provider fails or is out of quota, move to the next in the chain. Claude as host is always the final fallback — it can't be "unavailable."

---

## Inline vs. Delegate

Delegation has real latency cost. The goal is to **maximize value per quota token**, not to delegate everything blindly.

- **Low pressure:** Most tasks run inline. Only delegate when output would flood context (large file dumps, raw search results).
- **Medium pressure:** Delegate multi-step tasks and implementation. Keep simple single-call tasks inline.
- **High/Critical pressure:** Delegate everything except MCP calls, trivial single-tool-call tasks, and displaying results to the user.
- **Multi-step research and web searches:** Almost always delegate regardless of pressure — the intermediate output pollutes context.

---

## Quota Pressure Assessment

| Pressure | Condition | Delegation stance |
|----------|-----------|-------------------|
| **Low** | >50% remaining on both 5hr and 7-day windows | Inline by default, delegate for context hygiene |
| **Medium** | 20–50% remaining on either window | Delegate multi-step work, inline simple tasks |
| **High** | <20% remaining on either window | Delegate aggressively to Codex |
| **Critical** | <5% remaining or rate-limited | Delegate all work; spill from Codex to Gemini |

Note the **reset times** from the quota snapshot. Pressure applies until the earliest reset — after that, re-run `cclimits` to reassess.
