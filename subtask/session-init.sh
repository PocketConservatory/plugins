#!/usr/bin/env bash
# /subtask session init — runs at session start via Claude Code hooks
# Primes quota cache and injects routing strategy into context

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prime quota cache for PreToolUse hook (output suppressed)
bash "${SCRIPT_DIR}/quota-pressure.sh" &>/dev/null || true

cat "${SCRIPT_DIR}/skills/delegate/context.md"
