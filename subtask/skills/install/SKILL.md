---
name: install
description: Set up the /subtask plugin — adds startup hook to CLAUDE.md and verifies CLI environment
user-invocable: true
disable-model-invocation: true
---

# Subtask — Install

Run this once after installing the plugin to configure the project for quota-aware task delegation.

## Steps

1. **Check CLAUDE.md** for an existing `/subtask` startup hook. Look for a section that references reading the `/subtask` skill at session start.

2. **If missing**, add a short section to CLAUDE.md:

```markdown
## Quota-Aware Task Delegation

At the start of each session, read the `/subtask:delegate` skill to load the multi-model routing and quota management strategy. Assess quota pressure early and use it to guide inline vs. delegation decisions throughout the session. Use `/subtask:delegate` to delegate tasks to external AI CLIs when appropriate.
```

3. **Run CLI discovery** to verify the environment is ready:
   - Run `which claude codex gemini agent` to detect installed CLIs. Do not chain with `;`, `||`, `&&`, pipes, or redirects.
   - For each installed CLI, run `<cli> --help` and confirm it responds.
   - If `agent` is installed, run `agent --list-models` and confirm it responds.

4. **Report** what was set up, which CLIs are available, and confirm the plugin hooks are active. The plugin's SessionStart hook auto-injects CLI availability and quota context on every session start, resume, clear, and compaction — no manual configuration needed.

Skip any step where the config already exists.
