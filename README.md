# Tonic Plugins

Claude Code plugin marketplace for Tonic.

## Setup

```sh
claude plugin marketplace add PocketConservatory/plugins
claude plugin install subtask@tonic --scope project
```

Restart Claude Code after installing.

## Available Plugins

### subtask

Multi-model task delegation with quota-aware routing across AI CLIs (Claude, Codex, Gemini, Cursor Agent).

**Skills:**
- `/subtask:new <task>` — delegate a task to the optimal AI model based on routing rules and quota
- `/subtask:install` — one-time setup: adds startup hook to CLAUDE.md and verifies CLI environment

**Hooks:**
- `SessionStart` — auto-injects CLI availability and quota snapshot on startup, resume, clear, and compaction
