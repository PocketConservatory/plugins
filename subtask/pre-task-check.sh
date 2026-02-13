#!/usr/bin/env bash
# pre-task-check.sh — PreToolUse hook for Task tool
# Reads structured quota data from quota-pressure.sh, emits an actionable
# directive when Claude is HIGH/CRITICAL and the subagent type is a
# delegation candidate. Non-blocking: always exits 0.

# Only check delegation-candidate subagent types
INPUT=$(cat)
subagent_type=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null) || exit 0

case "$subagent_type" in
  general-purpose|Explore) ;;
  *) exit 0 ;;
esac

# Get structured quota data (served from cache if fresh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
data=$(bash "${SCRIPT_DIR}/quota-pressure.sh" 2>/dev/null) || exit 0

# Check Claude's pressure level
claude_pressure=$(echo "$data" | grep '^Claude|' | cut -d'|' -f3)
case "$claude_pressure" in
  HIGH|CRITICAL) ;;
  *) exit 0 ;;
esac

# Build available providers list from LOW entries (excluding Claude)
available=""
while IFS='|' read -r label remaining pressure; do
  [[ "$pressure" == "LOW" && "$label" != "Claude" ]] || continue
  [[ -n "$available" ]] && available+=", "
  available+="${label} ${remaining}"
done <<< "$data"

# Only warn if there's somewhere to delegate to
[[ -z "$available" ]] && exit 0

echo "⚠️ STOP: Claude quota is critically low. Use /subtask:delegate instead of Task for this work."
echo "Available: ${available}"

exit 0
