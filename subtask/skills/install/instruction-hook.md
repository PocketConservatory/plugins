<!-- subtask:begin -->
## Quota-Aware Task Delegation

The subtask plugin loads a routing strategy and quota levels into context. **Before starting any non-trivial task**, check the quota pressure and apply these rules:

- **High/Critical (<20% remaining):** Default to `/subtask:delegate`. Only stay inline if the task specifically requires capabilities unique to you (e.g., MCP access, multi-turn interaction). Everything else — implementation, research, code review, file analysis — gets delegated.
- **Medium (20–50%):** Delegate multi-step tasks and implementation work. Simple single-call tasks can stay inline.
- **Low (>50%):** Delegate when it saves context or crosses provider boundaries. Speed takes priority.

This is not optional. Running work inline that another provider could handle wastes your quota — especially when the loaded context shows they have capacity.
<!-- subtask:end -->
