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

Everything else — implementation, research, analysis, advisory, documentation.

**The decision is based on remaining capacity across ALL providers, not just the host.** Each provider measures quota differently (different window durations, tiers, rate limits). Use the raw data from `cclimits` — don't assume uniform windows.

**Principle:** Route to the provider with the most remaining capacity, respecting the priority order (Claude → Codex → Gemini). Stay on a higher-priority provider when it has headroom; spill to the next when it doesn't.

**How it works:**

1. If Claude has comfortable headroom → run inline on Claude (fastest, no delegation latency)
2. If Claude is getting tight but Codex has capacity → delegate to Codex
3. If both Claude and Codex are pressured but Gemini has capacity → delegate to Gemini
4. If all providers are low → use whichever has the *most* remaining capacity relative to its limits

**Simple tasks** (1–2 tool calls, small output) can stay on Claude at any pressure — the token cost is negligible and delegation latency isn't worth it.

**Fallback on failure:** If a provider errors or is quota-exhausted mid-task, move to the next in priority. Claude as host is always the final fallback — it can't be "unavailable."

---

## Inline vs. Delegate

Delegation has real latency cost. The goal is to **maximize value per quota token across all providers**, not to delegate everything blindly.

- **When Claude has headroom:** Most tasks run inline. Only delegate when output would flood context (large file dumps, raw search results).
- **When Claude is pressured but Codex isn't:** Delegate multi-step tasks and implementation to Codex. Keep trivial tasks inline.
- **When both Claude and Codex are pressured:** Spill to Gemini. Reserve Claude for MCP, multi-turn, and displaying results.
- **Multi-step research and web searches:** Almost always delegate regardless of pressure — the intermediate output pollutes context.

---

## Reading Quota Data

`cclimits` reports remaining capacity per provider. Each provider has its own measurement windows and thresholds — don't normalize them into a single scale. Instead, assess each provider independently:

- **Has headroom:** Comfortably above 50% on all of its windows
- **Getting tight:** Any window between 20–50%
- **Pressured:** Any window below 20%
- **Exhausted:** Below 5% or actively rate-limited

Note the **reset times**. A provider that's pressured now but resets in 10 minutes is effectively available. A provider at 30% with 5 days until reset is tighter than it looks. Factor reset proximity into the judgment.
