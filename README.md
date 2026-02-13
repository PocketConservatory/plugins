# Tonic Plugins

A collection of [Claude Code plugins](https://docs.anthropic.com/en/docs/claude-code/plugins) for working with AI coding agents.

## Quick Start

```sh
# Add the marketplace
claude plugin marketplace add PocketConservatory/plugins

# Install a plugin (e.g. subtask)
claude plugin install subtask@tonic --scope project
```

Restart Claude Code after installing.

## Plugins

### [subtask](#subtask-1) — Multi-model task delegation

Route coding tasks across Claude Code, OpenAI Codex, Google Gemini CLI, and Cursor Agent based on task type and remaining quota. Never hit a quota wall on a single provider again.

---

# subtask

Every AI coding CLI has usage limits. When you hit one, you're stuck waiting for it to reset. **subtask** automatically routes tasks to whichever provider has the most remaining quota, based on what the task actually needs:

| Task type | Routed to | Why |
|-----------|-----------|-----|
| Code review | Codex | Separate review quota pool |
| Implementation | Codex or Claude | Whichever has more quota |
| Research / analysis | Gemini | Large context window, separate quota |
| MCP-dependent (Linear, Notion, etc.) | Claude (host) | Only Claude has MCP servers |

When your preferred provider runs out, subtask automatically falls back to the next best option — including Cursor Agent as a last resort (separate quota pool entirely).

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- At least one additional AI CLI for delegation to be useful:
  - [OpenAI Codex](https://github.com/openai/codex) — `npm i -g @openai/codex`
  - [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) — `npm i -g @google/gemini-cli`
  - [Cursor Agent](https://docs.cursor.com/agent) — see Cursor docs
- [Node.js](https://nodejs.org/) (for the quota checker, `npx cclimits`)

## Install

```sh
claude plugin marketplace add PocketConservatory/plugins
claude plugin install subtask@tonic --scope project
```

Restart Claude Code. The routing strategy and quota hooks activate automatically.

## Usage

### Automatic quota enforcement

subtask uses two hooks to manage quota without you doing anything:

- **SessionStart** — primes a quota cache (via [cclimits](https://github.com/cruzanstx/cclimits)) and injects the routing strategy
- **PreToolUse** — intercepts Task calls when Claude is running low on quota and directs it to use `/subtask:delegate` instead, listing available providers

### Delegating tasks

Use `/subtask:delegate` to send a task to the optimal provider:

```
/subtask:delegate Research best practices for caching in Firebase
```

subtask will automatically pick Gemini (read-only research task, large context window, preserves Claude quota).

You can also force a specific provider:

```
/subtask:delegate Review the auth changes using codex
/subtask:delegate Use gemini to analyze the performance impact
/subtask:delegate Implement retry logic with codex
```

### Routing

**Priority: Claude → Codex → Gemini.** Claude is the primary model. External CLIs are overflow buckets when Claude is under pressure.

The PreToolUse hook computes pressure levels from remaining quota and reset times. When Claude is HIGH or CRITICAL and alternative providers are available, it blocks Task calls with a directive to delegate. Code reviews always go to Codex (separate quota pool).

## Skills

| Skill | Description |
|-------|-------------|
| `/subtask:delegate <task>` | Route a task to the optimal AI CLI based on type and quota |

---

## License

MIT
