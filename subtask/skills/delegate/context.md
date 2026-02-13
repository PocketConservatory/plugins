# Routing Strategy

**Priority: Claude (you) → Codex → Gemini.** You are the primary model. External CLIs are overflow buckets. `agent` (Cursor) is manual-only — only when the user says so or names a model only it supports.

Skip any CLI the user doesn't have installed.

## Pre-work delegation check

**STOP before every task.** Before spawning a Task subagent, making a WebFetch/WebSearch call, or starting any multi-step work:

1. Check quota pressure from the session start context below
2. If you're pressured or worse: use `/subtask:delegate` unless the task requires MCP access or multi-turn interaction with the user. No exceptions.
3. If you catch yourself about to use `Task` tool with `subagent_type` of `general-purpose` or `Explore` while pressured — that's a delegation candidate. Stop and use `/subtask:delegate` instead.

This is a blocking gate, not a suggestion. Using host tokens for work another provider could handle is a bug.

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

Each provider has different windows and thresholds — assess independently:

- **Has headroom:** >50% on all windows
- **Getting tight:** any window 20–50%
- **Pressured:** any window <20%
- **Exhausted:** <5% or rate-limited

Factor in **reset times** — 15% remaining but resets in 10 minutes is effectively available. 30% with 5 days until reset is tighter than it looks.
