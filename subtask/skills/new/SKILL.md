---
name: new
description: Delegate a task to the optimal AI model based on routing rules, quota, and task type
user-invocable: true
argument-hint: <task description>
---

# Subtask — Multi-Model Task Delegation

Delegate a task to the best available AI model. Routes automatically based on task type and quota, or honors an explicit model choice.

This skill is **host-agnostic** — it works from any CLI tool (Claude Code, Codex, Gemini). The agent running this skill is the **host model**. All other models are reached via their CLI.

**Prerequisites:** None — the skill handles CLI discovery on demand if not already cached in working memory. If the plugin's SessionStart hook is active, CLI availability and quota pressure are already in context.

## Usage

```
/subtask:new <task description>
```

Model hints can appear anywhere in the input — at the end, beginning, or inline. All of these work:

- `/subtask:new Research best practices for caching in Firebase` — auto-routes
- `/subtask:new Review the auth changes in this PR using codex` — Codex
- `/subtask:new Use gemini to analyze the performance impact of this migration` — Gemini
- `/subtask:new with codex, implement retry logic in utils/retry.ts` — Codex
- `/subtask:new Analyze this module using Codex 5.3 High` — Codex with specific variant
- `/subtask:new Create a Linear ticket for the billing bug` — auto-routes to host model (needs MCP)
- `/subtask:new Use agent to refactor the utils module` — Agent (Cursor)
- `/subtask:new Analyze this with grok` — routes to `agent` (Grok is only available there)

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

## Sandbox Modes

Apply the **least access level** that satisfies the task. Derive exact flags from cached `--help`.

**Hard rule: NEVER use yolo, auto-approve-all, danger-full-access, or any equivalent unrestricted mode.** Every external CLI invocation MUST run in a sandbox. No exceptions — not even for "simple" tasks. This rule cannot be overridden by task urgency, convenience, or the assumption that a task won't trigger dangerous actions.

| Level | Access | Use When | Notes |
|-------|--------|----------|-------|
| 1. Pipe | No filesystem | Self-contained tasks: summarize text, parse JSON, generate a snippet from provided context | Pass content via stdin or prompt flag |
| 2. Read-only | Read filesystem, no writes | Reviews, analysis, advisory that need codebase context | Use plan/read-only mode flag |
| 3. Working directory | Read + write in scoped dir | Implementation within a worktree or temp sandbox | Set working directory to the worktree or sandbox path |
| 4. Full access | Read + write beyond working dir | Implementation needing config outside worktree | Still requires sandbox — use the CLI's default approval mode, never yolo |

### Sandbox Fallback

If the ideal sandbox mode fails on a CLI (e.g., read-only/plan mode requires an experimental flag, or a flag is unrecognized):

1. **Try a more relaxed sandbox on the same CLI** if the agent judges it is safe for this specific task. Staying on the routed model preserves quota distribution. For example, a pure web research task routed to Gemini at Level 2 (read-only) can safely fall back to the CLI's default approval mode — web search doesn't write files, so the relaxed sandbox poses no real risk.
2. **If the agent has doubts about safety at the relaxed level, switch to a different model** that supports the correct sandbox level. Walk the routing fallback chain for the task type (e.g., for read-only: Gemini → Codex read-only → host model native subagent). Quota distribution matters, but not at the expense of safety.
3. **If all external CLIs fail, use the host model's native subagent** — it inherits the host's own permission controls.

---

## Output Format

**Quiet execution.** Steps 1–5 (parsing, discovery, routing, persona, launch) produce no user-facing output. Only the final result is shown.

**Success:**

> **subtask**
> **model:** codex · **route:** rule-0 (user override) · **sandbox:** read-only

```
[model output here]
```

**Failure:**

> **subtask**
> **model:** codex · **route:** rule-0 (user override) · **sandbox:** read-only
> **status:** error — CLI not found

```
[error details if any]
```

**Format rules:**
- Metadata goes in a blockquote — one line for the skill name, one line for model/route/sandbox
- Status line only appears on failure (success is implicit when absent)
- Model output goes in a fenced code block, unmodified
- For native subagent results, skip the code fence — render the output as normal markdown since it may contain formatting
- Route labels: `rule-0` through `rule-6`, with a short human-readable name in parentheses (e.g., "user override", "default", "MCP required", "code review", "implementation", "read-only")

---

## Execution Procedure

Steps 1–5 are silent — no user-facing output. Only Step 6 produces output using the format above.

### Step 1: Parse Input

Extract from the user's input:
- **Task description** — the input with the model hint removed (or the entire input if no model hint)
- **Model hint** — scan the full input for a model reference. Match any of these patterns (case-insensitive, punctuation-flexible):
  - `using <model>` — e.g., "using gemini", "Using Codex"
  - `use <model>` — e.g., "use gemini to analyze", "Use Codex"
  - `with <model>` — e.g., "with codex,", "with Gemini"
  - The model name can include version or variant qualifiers (e.g., "Codex 5.3 High", "Gemini 2.5 Pro"). Match the base model name (`codex`, `gemini`, `claude`, `agent`) and pass any qualifiers through to the CLI invocation.
  - If the hint is a **specific model name** rather than a CLI name (e.g., "grok", "gpt-5.2", "opus-4.6", "gemini-3-pro"), identify which CLI natively supports it by model family. That CLI gets priority. If it's out of quota, fall back to `agent` if it supports that model (check cached `agent --list-models`).
  - First matching model wins.

### Step 2: Ensure CLI Discovery

If the SessionStart hook has already injected CLI availability and quota data into context, use that — skip redundant discovery. Otherwise, run the following:

1. **Installed CLIs:** Run `which claude codex gemini agent` to detect availability. Do not chain with `;`, `||`, `&&`, pipes, or redirects.
2. **Cached --help:** For **every** installed CLI (claude, codex, gemini, agent — all of them), run `<cli> --help` and hold the output in working memory. Do not skip any installed CLI, even if it matches the host model.
3. **Agent model list:** If `agent` is installed, run `agent --list-models` and cache the output. This is needed to confirm whether `agent` supports a specific model before routing to it. For other CLIs, use your knowledge of model families (e.g., `claude` → Anthropic family, `codex` → OpenAI family, `gemini` → Google family).
4. **Quota pressure assessment:** Run `npx cclimits --json` to snapshot remaining quota across all providers (note: `agent` quota is not covered by `cclimits`). From the snapshot, determine the **quota pressure level** for the host model and cache it alongside the raw data:

   | Pressure | Condition | Delegation stance | Inline threshold |
   |----------|-----------|-------------------|------------------|
   | **Low** | >50% remaining on both short-term (e.g., 5hr) and long-term (weekly) windows | Delegate only when it clearly saves context or crosses providers | Most tasks can run inline |
   | **Medium** | 20–50% remaining on either window | Actively prefer delegation for multi-step tasks | Only simple, fast tasks inline (1–2 tool calls, small output) |
   | **High** | <20% remaining on either window | Aggressively delegate everything possible to external CLIs | Only trivial single-call tasks inline |
   | **Critical** | <5% remaining or rate-limited | Delegate all work to external CLIs; avoid host model usage entirely | Nothing inline except displaying results |

   Also note the **reset times** from the snapshot. The pressure level applies until the earliest reset — after that, re-run `cclimits` to reassess.

Skip any step where the data is already cached and fresh. Refresh quota if the snapshot is older than ~15 minutes or a reset time has passed.

### Step 3: Route the Task

**If model hint is present** (Rule 0): use that model unconditionally.

**If no model hint** (auto-route):
1. Check which external CLIs are available from the cached discovery
2. Check quota from the cached snapshot (refresh if stale)
3. Walk the Routing Decision Tree (Rules 1–6) — first matching rule wins
4. Select the sandbox level from the Sandbox Modes table based on task type

### Step 4: Determine Agent Persona (Optional)

If the task maps to an existing agent role, scan `.claude/agents/*.md` to find a matching agent definition. Read the matching file and compose the persona into the prompt.

If no agent matches the task type, skip persona — just pass the task description directly.

### Step 5: Launch

**If routed model matches host model → native subagent:**
- Use the host's native subagent/task spawning mechanism
- Include persona instructions (if any) and task description in the prompt

**If routed model differs from host → external CLI:**
- Derive the correct flags for: non-interactive mode, prompt input, sandbox level
- **Ask for summarized output where appropriate.** For research, analysis, and review tasks, append an instruction to the prompt asking the delegate to return a concise summary rather than raw results. The host model rarely needs verbatim search results, full file contents, or unfiltered API responses — a distilled answer saves host context and is easier to act on. Skip this for implementation tasks where the output is code.
- **Always use text output** (default) — do not use JSON/stream-JSON output formats. Text output preserves human-readable thinking steps and progress, and is easier to monitor for errors.
- **Always launch in background** (`run_in_background: true`) so the process can be monitored and killed if stuck.
- Run via shell execution (Bash tool or equivalent)
- Working directory: set to the relevant worktree path if one exists, otherwise the monorepo root

### Step 5b: Monitor Background Process

Poll the output file silently — **never print polling output to the user**. The user should only see the final result or a failure message, not intermediate monitoring noise.

**Fatal error patterns** — if any of these appear and no new output follows within ~10 seconds, kill the process and apply fallback:
- `denied by policy` — sandbox blocked a required tool, CLI is stuck
- `error executing tool` — tool execution failed unrecoverably
- `permission error` / `permission denied` — sandbox too restrictive
- `quota exhausted` / `exhausted your capacity` — provider out of quota
- `crash` / `panic` / `fatal` — CLI crashed

**Suspected silent hang** — if the output file has not grown beyond CLI initialization lines (e.g., credential loading, hook registry) for an extended period and no error pattern is present, ask the user whether to keep waiting or kill the process. Do not kill silently — the process may be legitimately slow.

**Fallback on kill:** Apply the Sandbox Fallback rules (try relaxed sandbox if safe, otherwise switch provider). If the error was quota-related, skip to the next provider immediately.

### Step 6: Handle Result

Present the result using the **Output Format** defined above.

- **Success:** Show the metadata blockquote + model output. No additional commentary.
- **Transient failure** (timeout, rate limit): Retry once with the same provider. If retry succeeds, show success format. If retry fails, treat as hard failure.
- **Hard failure** (CLI not found, crash, permission error):
  - **If user specified a model** (Rule 0): Show failure format with error details. Do not fall back — the user explicitly chose this provider.
  - **If auto-routed** (Rules 1–6): Fall back to the next provider in the routing chain silently. If all providers fail, show failure format.
