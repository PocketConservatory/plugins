# Routing Strategy

**Priority: Claude (you) → Codex → Gemini.** You are the primary model. External CLIs are overflow buckets. `agent` (Cursor) is manual-only — only when the user says so or names a model only it supports.

## Quota enforcement

A PreToolUse hook monitors quota pressure and will warn you before Task, WebSearch, and WebFetch calls when Claude is running low. Follow its directives.

## Quota-pressure routing

When Claude quota is HIGH or CRITICAL, route by task type:

| Task Type | Route To | Examples |
|-----------|----------|----------|
| Code analysis & understanding | Codex | Reading code, explaining logic, finding patterns, codebase exploration |
| Code changes | Codex | Writing code, refactoring, implementing features, fixing bugs |
| Code review | Codex Review | PR reviews, code quality checks, diff analysis |
| Web search & research | Gemini | Searching the web, fetching URLs, researching libraries/APIs |

If the preferred provider is also at quota, fall through to the next available.

## Proactive delegation

Use `/subtask:delegate` even when you have headroom:

- **Code review** → always delegate to Codex Review (separate quota)
- **Large output tasks** (web searches, broad codebase exploration) → delegate to keep context clean
- **User says `using codex` / `with gemini` / etc.** → delegate to that provider unconditionally
