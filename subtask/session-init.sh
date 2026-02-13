#!/usr/bin/env bash
# /subtask session init — runs at session start via Claude Code hooks
# Outputs CLI availability and quota snapshot for context injection

set -euo pipefail

echo "[subtask] Session context:"

# CLI discovery
echo ""
echo "Installed CLIs:"
for cmd in claude codex gemini agent; do
  path=$(which "$cmd" 2>/dev/null || true)
  if [ -n "$path" ]; then
    echo "  $cmd: $path"
  fi
done

# Quota snapshot
echo ""
echo "Quota snapshot (via cclimits):"
if command -v npx &>/dev/null; then
  npx --yes cclimits 2>/dev/null || echo "  cclimits unavailable"
else
  echo "  npx not found"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo ""
cat "${SCRIPT_DIR}/skills/delegate/routing-strategy.md"
