# Routing Strategy

**Priority: Claude (you) → Codex → Gemini.** You are the primary model. External CLIs are overflow buckets. `agent` (Cursor) is manual-only — only when the user says so or names a model only it supports.

## Quota enforcement

A PreToolUse hook monitors quota pressure and will warn you before Task calls when Claude is running low. Follow its directives.

## Proactive delegation

Use `/subtask:delegate` even when you have headroom:

- **Code review** → always delegate to Codex Review (separate quota)
- **Large output tasks** (web searches, broad codebase exploration) → delegate to keep context clean
- **User says `using codex` / `with gemini` / etc.** → delegate to that provider unconditionally
