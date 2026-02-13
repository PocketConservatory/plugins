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

Restart Claude Code, then run the one-time setup:

```
/subtask:install
```

This does two things:
1. Adds a small section to your `CLAUDE.md` that tells Claude to use quota-aware routing
2. Verifies which AI CLIs are installed and working

## Usage

### Automatic session context

Every time you start, resume, or clear a Claude Code session, subtask automatically injects:

- **Which CLIs are installed** and their paths
- **Current quota levels** across all providers (via [cclimits](https://github.com/cruzanstx/cclimits))
- **The routing strategy** so Claude knows how to delegate

Claude is always aware of your quota situation without you doing anything.

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

### Routing rules

The router walks a decision tree — first match wins:

1. **User override** — you said which provider to use
2. **MCP required** — task needs Linear/Notion/Slack/etc. → stays on Claude
3. **Multi-turn** — iterative exploration → stays on Claude (external CLIs are single-shot)
4. **Code review** → Codex (separate review quota)
5. **Implementation** → Codex or Claude, whichever has more quota
6. **Read-only** → Gemini (large context, separate quota)
7. **Default** → provider with the most remaining 7-day quota

### Quota pressure

subtask assesses pressure based on remaining quota and adjusts how aggressively it delegates:

| Pressure | Condition | Behavior |
|----------|-----------|----------|
| Low | >50% remaining | Most tasks run inline for speed |
| Medium | 20–50% remaining | Multi-step tasks get delegated |
| High | <20% remaining | Everything possible gets delegated |
| Critical | <5% remaining | All work offloaded to external CLIs |

## Skills

| Skill | Description |
|-------|-------------|
| `/subtask:delegate <task>` | Route a task to the optimal AI CLI based on type and quota |
| `/subtask:install` | One-time setup: inject config into CLAUDE.md, verify CLIs |

---

## License

MIT
