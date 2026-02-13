# Routing Strategy

Auto-loaded at session start by the subtask plugin's SessionStart hook.

## Overview

This is a **Claude Code plugin**. Claude (host) is the primary model. External CLIs are overflow — work spills into them as Claude's quota fills up.

**Priority: Claude → Codex → Gemini.** The only variable is *when* to spill.

`agent` (Cursor) is **manual-only** — used when the user explicitly requests it or names a model only `agent` supports (e.g., Grok).

## Model Registry

| Model | CLI | Quota Pool |
|-------|-----|------------|
| Claude | host (native subagent) | Anthropic |
| Codex | `codex` | OpenAI |
| Codex Review | `codex review` | OpenAI (separate review quota) |
| Gemini | `gemini` | Google |
| Agent | `agent` | Cursor (not measurable) |

All CLI flags MUST come from cached `--help` output. Never hardcode flags.

## Routing Rules

Walk top-to-bottom. First match wins.

### Rule 0: User Override

User specified a CLI (`using codex`, `with gemini`, `using agent`) → use it unconditionally.

User specified a model name (`grok`, `gpt-5.2`, `gemini-3-pro`) → resolve to native CLI by family (OpenAI → `codex`, Google → `gemini`). Models without a native CLI (e.g., Grok) → `agent` if supported. Otherwise report error.

### Rule 1: MCP Required

Task needs MCP servers (Linear, Notion, Sentry, Figma, Slack, etc.) → **Claude (host)**. No fallback.

### Rule 2: Multi-Turn

Task requires iterative conversation or interactive debugging → **Claude (host)**. External CLIs are single-shot.

### Rule 3: Code Review

→ **Codex Review** (separate quota pool — always prefer regardless of pressure). Fallback: Claude → Gemini.

### Rule 4: Bucket Fill

Everything else. Route to the provider with the most remaining capacity, respecting priority order.

- Claude has headroom → run inline (fastest)
- Claude tight, Codex has capacity → delegate to Codex
- Both tight, Gemini has capacity → delegate to Gemini
- All tight → whichever has the most remaining capacity relative to its limits

**Simple tasks** (1–2 tool calls, small output) stay on Claude at any pressure — delegation latency isn't worth it.

**Multi-step research and web searches** should almost always be delegated — intermediate output pollutes context.

On failure or quota exhaustion mid-task, move to the next provider. Claude is always the final fallback.

## Reading Quota Data

`cclimits` reports capacity per provider. Each has different windows and thresholds — assess independently:

- **Has headroom:** >50% on all windows
- **Getting tight:** any window 20–50%
- **Pressured:** any window <20%
- **Exhausted:** <5% or rate-limited

Factor in **reset times** — a provider at 15% that resets in 10 minutes is effectively available. A provider at 30% with 5 days until reset is tighter than it looks.
