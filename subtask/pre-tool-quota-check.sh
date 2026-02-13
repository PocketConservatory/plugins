#!/usr/bin/env bash
# pre-tool-quota-check.sh — PreToolUse hook for quota-sensitive tools
# Reads structured quota data from quota-pressure.sh, emits an actionable
# directive when Claude is HIGH/CRITICAL and the tool use is a delegation
# candidate. Emits permissionDecision:deny JSON to block the call.

INPUT=$(cat)
tool_name=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0

# ─── Tool-specific filtering ────────────────────────────────────────
# Task: only check delegation-candidate subagent types
# WebSearch/WebFetch: always candidates (any web research can be delegated)
case "$tool_name" in
  Task)
    subagent_type=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null) || exit 0
    case "$subagent_type" in
      general-purpose|Explore) ;;
      *) exit 0 ;;
    esac
    ;;
  WebSearch|WebFetch)
    ;;  # always a delegation candidate
  *)
    exit 0 ;;
esac

# Get structured quota data (served from cache if fresh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
data=$(bash "${SCRIPT_DIR}/quota-pressure.sh" 2>/dev/null) || exit 0

# Check Claude's pressure level
claude_remaining=$(echo "$data" | grep '^Claude|' | cut -d'|' -f2)
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

# ─── Emit JSON to deny the tool call ─────────────────────────────────
reason="Claude quota is ${claude_pressure} (${claude_remaining}). Use /subtask:delegate with the routing and sandbox rules from your session context. Available: ${available}"

jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'

exit 0
