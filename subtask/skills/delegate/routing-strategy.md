# Routing Strategy

Auto-loaded at session start by the subtask plugin's SessionStart hook.

---

## Concepts

**Host model:** The agent currently executing this skill. It has native subagent spawning, tool access, and (potentially) MCP servers. Conserve host model quota by delegating to external CLIs when possible.

**External CLI:** Any model reached via shell command (`claude`, `codex`, `gemini`, `agent`). If routing picks the same model as the host, use native subagent spawning instead of shelling out to the CLI.

---

## Model Registry

| Model | CLI | Capabilities | Quota Pool |
|-------|-----|-------------|------------|
| Claude | `claude` | Full coding agent, MCP servers (if configured), multi-turn orchestration | Anthropic family (Opus/Sonnet/Haiku) |
| Codex | `codex` | Full coding agent with file R/W, Bash, configurable sandbox | OpenAI family |
| Codex Review | `codex` | Dedicated code review mode | OpenAI family (separate review quota) |
| Gemini | `gemini` | Full agent with tool access, large context window | Google family |
| Agent (Cursor) | `agent` | Multi-model CLI spanning multiple families (Anthropic, OpenAI, Google, Grok, etc.). Run `agent --list-models` to get the current list. | Cursor quota (separate pool, not measurable) |

**Agent (Cursor) constraints:** No programmatic quota measurement — `agent` is **never used in automatic routing**. It is only used when: (1) the user explicitly requests it, (2) the user requests a specific model that no other CLI supports (e.g., Grok), or (3) the native CLI for a model's family is out of quota (e.g., `codex` exhausted → `agent --model gpt-5.2` as fallback). `agent` is never considered for quota balancing in Rules 1–6.

**Flag derivation:** All CLI flags MUST come from the cached `--help` output. Never hardcode flags. Consult the cached `--help` to determine flags for: non-interactive mode, sandbox level, prompt input method, and output format.

---

## Routing Decision Tree

Walk this tree top-to-bottom. **First matching rule wins.**

### Rule 0: User Override

If the user specified a **CLI name** (e.g., "using gemini", "using codex", "using claude", "using agent"), use that CLI unconditionally. No further routing needed.

If the user specified a **specific model name** (e.g., "grok", "gpt-5.2", "opus-4.6-thinking", "gemini-3-pro"), resolve it by model family:
1. Identify the **native CLI** for the model's family (e.g., OpenAI family → `codex`, Anthropic family → `claude`, Google family → `gemini`). Use that CLI with `--model <id>`.
2. If the native CLI is **out of quota**, fall back to `agent --model <id>` (separate quota pool).
3. If the model doesn't belong to any primary CLI's family (e.g., Grok), check the cached `agent --list-models` — if it appears there, route to `agent`.
4. If no installed CLI supports the model, **report the error to the user** — do not silently fall back to another provider.

### Rule 1: MCP Required

Task needs MCP servers (Linear, Notion, Sentry, Amplitude, Firebase, Figma, Slack, or any other MCP tool).

-> **Host model** if it has the required MCP servers configured (check available tools).
-> **Fallback:** Claude CLI (most likely to have MCP configured). If neither has MCP, report to user.

### Rule 2: Multi-Turn Required

Task requires multi-turn conversation with the codebase (iterative exploration, back-and-forth reasoning).

-> **Host model (native subagent).** External CLIs are single-shot.

### Rule 3: Code Review

Task is reviewing code for correctness, quality, security, or patterns.

-> **Prefer:** Codex Review (separate quota pool)
-> **Fallback:** Gemini in read-only mode -> `agent` with an equivalent model -> host model (native subagent)

### Rule 4: Implementation

Task is writing code, creating files, or making changes.

-> **Prefer:** Codex or Claude — pick whichever has more remaining quota
-> **Quota-exhaustion fallback:** If both are out of quota, use `agent` with an equivalent model (via `--model`)
-> **Final fallback:** host model (native subagent)
-> **NOT Gemini** (not suited for code generation tasks)

### Rule 5: Read-Only

Task is advisory, analysis, plan review, documentation review, or research. Does not modify files.

-> **Prefer:** Gemini in read-only/plan mode (large context, separate quota)
-> **Fallback:** Codex in read-only mode -> `agent` in plan/ask mode -> host model (native subagent)

### Rule 6: Default

No specific routing constraint applies.

-> Use the provider with the **most remaining 7-day quota** (from `cclimits`)
-> If quota is unknown, prefer external CLIs over host model to conserve host quota
-> If no external CLIs are installed, use host model (native subagent)

---

## Inline vs. Delegate

External CLI delegation is slower than native tool calls — there's real latency cost. The goal is not to delegate everything blindly, but to **maximize the value extracted from every quota token across all providers.**

**Use your judgement.** You have the quota pressure level, the task complexity, and the context value of the results. Balance these:

- **When quota pressure is low**, favor speed. Run tasks inline unless they'd flood the context with throwaway output (e.g., raw search results, large file dumps). The latency cost of delegation isn't worth it when quota is abundant.
- **When quota pressure is medium or high**, favor preservation. The host model's remaining quota is a finite resource that should be spent on tasks where inline context matters — interactive debugging, iterative design decisions, multi-turn conversations with the user. Offload everything else.
- **Simple, fast tasks** (a single tool call, a quick file read, an MCP query) can stay inline at any pressure level. The token cost is negligible and the result is often needed in the conversation. Don't pay the delegation latency tax for something that costs 100 tokens.
- **Multi-step research and web searches** should almost always be delegated regardless of pressure — not primarily for quota, but because the raw intermediate output pollutes context. The exception is when pressure is low AND the intermediate results are themselves valuable to the ongoing conversation.

Effective quota management is a core competency. Many developers hit quota walls because their tools don't distribute load intelligently. This skill exists to solve that — make every token count across all available providers.

---

## Quota Pressure Assessment

| Pressure | Condition | Delegation stance | Inline threshold |
|----------|-----------|-------------------|------------------|
| **Low** | >50% remaining on both short-term (e.g., 5hr) and long-term (weekly) windows | Delegate only when it clearly saves context or crosses providers | Most tasks can run inline |
| **Medium** | 20–50% remaining on either window | Actively prefer delegation for multi-step tasks | Only simple, fast tasks inline (1–2 tool calls, small output) |
| **High** | <20% remaining on either window | Aggressively delegate everything possible to external CLIs | Only trivial single-call tasks inline |
| **Critical** | <5% remaining or rate-limited | Delegate all work to external CLIs; avoid host model usage entirely | Nothing inline except displaying results |

Note the **reset times** from the quota snapshot. The pressure level applies until the earliest reset — after that, re-run `cclimits` to reassess.
