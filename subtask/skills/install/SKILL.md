---
name: install
description: Set up the /subtask plugin — injects startup hook into the host's instruction file and verifies CLI environment
user-invocable: true
disable-model-invocation: true
---

# Subtask — Install

Run this once after installing the plugin, or re-run to update an existing installation to the latest version.

## Steps

### 1. Identify the host's instruction file

Determine where the current host agent reads project-level instructions. Examples:
- **Claude Code** → `CLAUDE.md` in the project root
- **Other hosts** → their equivalent project instruction file (e.g., `AGENTS.md`, `.codexrc`, etc.)

Use the identified file for all subsequent steps.

### 2. Read the canonical section

Read the canonical injection text from [instruction-hook.md](instruction-hook.md). This is the single source of truth for what gets injected.

### 3. Inject or update the instruction file

Search the instruction file for the `<!-- subtask:begin -->` marker:

- **Marker found:** Compare the content between `<!-- subtask:begin -->` and `<!-- subtask:end -->` with the canonical text from instruction-hook.md.
  - If different → replace the entire marked block (inclusive of markers) with the canonical version.
  - If identical → skip, already up to date.

- **Marker not found:** Search for the old-style unmarked section — a `## Quota-Aware Task Delegation` heading without surrounding `<!-- subtask:begin/end -->` markers.
  - If found → replace the old section (from the heading through the end of its content paragraph) with the canonical marked version from instruction-hook.md.
  - If not found → append the canonical marked section at the end of the file.

### 4. Run CLI discovery

Verify the environment is ready:
- Run `which claude codex gemini agent` to detect installed CLIs. Do not chain with `;`, `||`, `&&`, pipes, or redirects.
- For each installed CLI, run `<cli> --help` and confirm it responds.
- If `agent` is installed, run `agent --list-models` and confirm it responds.

### 5. Report

Report what changed:
- Which instruction file was updated (or "already up to date")
- Whether the section was added, updated, or replaced from legacy format
- Which CLIs are available
- Confirm the plugin's SessionStart hook is active (it auto-injects CLI availability, quota context, and the routing strategy on every session start, resume, clear, and compaction)
