# Routing Strategy

**Priority: Claude (you) → Codex → Gemini.** You are the primary model. External CLIs are overflow buckets. `agent` (Cursor) is manual-only — only when the user says so or names a model only it supports.

Skip any CLI the user doesn't have installed.

## When to use `/subtask:delegate`

| Situation | Action |
|-----------|--------|
| Task needs MCP (Linear, Notion, Sentry, Slack, etc.) | Stay inline — only you have MCP access |
| Task needs multi-turn / interactive debugging | Stay inline — external CLIs are single-shot |
| Code review | `/subtask:delegate` → Codex Review (separate quota, always prefer) |
| You have headroom | Stay inline for speed. Delegate only to keep context clean (large output, web searches) |
| You're getting tight, Codex has capacity | `/subtask:delegate` multi-step work to Codex |
| You and Codex both tight, Gemini has capacity | `/subtask:delegate` to Gemini |
| Simple task (1–2 tool calls, small output) | Stay inline at any pressure — delegation latency isn't worth it |
| User says `using codex` / `with gemini` / etc. | `/subtask:delegate` to that provider unconditionally |

## Reading quota data

The session start context includes a `cclimits` snapshot. Each provider has different windows and thresholds — assess independently:

- **Has headroom:** >50% on all windows
- **Getting tight:** any window 20–50%
- **Pressured:** any window <20%
- **Exhausted:** <5% or rate-limited

Factor in **reset times** — 15% remaining but resets in 10 minutes is effectively available. 30% with 5 days until reset is tighter than it looks.
