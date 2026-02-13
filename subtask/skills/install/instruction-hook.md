<!-- subtask:begin -->
## MANDATORY: Pre-Work Delegation Check

**STOP before every task.** Before spawning a Task subagent, making a WebFetch/WebSearch call, or starting any multi-step work:

1. Check the quota pressure from the session start context
2. If **High/Critical**: Use `/subtask:delegate` unless the task requires MCP access or multi-turn interaction with the user. No exceptions.
3. If you catch yourself about to use `Task` tool with `subagent_type` of `general-purpose` or `Explore` at High pressure — that's a delegation candidate. Stop and use `/subtask:delegate` instead.

**This is a blocking gate, not a suggestion.** The routing strategy was loaded for a reason. Using host tokens for work another provider could handle is a bug, not a judgment call.
<!-- subtask:end -->
