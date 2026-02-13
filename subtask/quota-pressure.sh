#!/usr/bin/env bash
# quota-pressure.sh — Parse cclimits JSON into structured quota data
# Pure data service. Outputs one pipe-delimited line per provider:
#   label|remaining%|pressure
# Caches with deterministic staleness. Callers parse the structured output.
#
# Cache format:
#   QUOTA_CACHE|<calculated_epoch>|<stale_epoch>
#   label|remaining%|pressure
#   ...

set -euo pipefail

CACHE_FILE="${TMPDIR:-/tmp}/quota-pressure.cache"
NOW_EPOCH=$(date +%s)

# ─── Cache check ─────────────────────────────────────────────────────
# If cache exists and is fresh, serve it immediately (no network call).

if [[ -f "$CACHE_FILE" ]]; then
  meta=$(head -1 "$CACHE_FILE")
  if [[ "$meta" == QUOTA_CACHE\|* ]]; then
    IFS='|' read -r _ _calc_epoch stale_epoch <<< "$meta"
    if (( NOW_EPOCH < stale_epoch )); then
      tail -n +2 "$CACHE_FILE"
      exit 0
    fi
  fi
fi

# ─── Dependency checks ───────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[quota-pressure] ERROR: jq is required but not found" >&2
  exit 1
fi

# ─── Fetch cclimits JSON ─────────────────────────────────────────────

RAW_JSON=$(npx --yes cclimits --json 2>/dev/null) || {
  if [[ -f "$CACHE_FILE" ]]; then
    tail -n +2 "$CACHE_FILE"
    exit 0
  fi
  echo "[quota-pressure] ERROR: cclimits failed" >&2
  exit 1
}

# ─── Helpers ──────────────────────────────────────────────────────────

# "4h 38m" → 278, "3d 23h" → 5700
parse_reset_to_minutes() {
  local input="$1" total=0 val
  val=$(echo "$input" | grep -oE '[0-9]+d' | grep -oE '[0-9]+' || true)
  [[ -n "$val" ]] && total=$((total + val * 24 * 60))
  val=$(echo "$input" | grep -oE '[0-9]+h' | grep -oE '[0-9]+' || true)
  [[ -n "$val" ]] && total=$((total + val * 60))
  val=$(echo "$input" | grep -oE '[0-9]+m' | grep -oE '[0-9]+' || true)
  [[ -n "$val" ]] && total=$((total + val))
  echo "$total"
}

# remaining% + reset_minutes → pressure level (with reset-time adjustment)
remaining_to_pressure() {
  local remaining="$1" reset_min="${2:-9999}"
  if (( remaining < 5 )); then
    if (( reset_min <= 15 )); then echo "HIGH"; else echo "CRITICAL"; fi
  elif (( remaining < 20 )); then
    if (( reset_min <= 15 )); then echo "MEDIUM"; else echo "HIGH"; fi
  elif (( remaining <= 50 )); then
    echo "MEDIUM"
  else
    echo "LOW"
  fi
}

# ─── Vendor parsers ──────────────────────────────────────────────────
# Each returns: label|remaining%|reset_minutes|pressure (internal format)

parse_claude() {
  local json="$1"
  echo "$json" | jq -e '.claude' &>/dev/null || return
  local status
  status=$(echo "$json" | jq -r '.claude.status // empty') || return
  [[ "$status" == "ok" ]] || { echo "Claude|—|9999|UNAVAILABLE"; return; }

  local r5h r7d rm5h rm7d
  r5h=$(echo "$json" | jq -r '.claude.five_hour.remaining // empty' | tr -d '%') || return
  r7d=$(echo "$json" | jq -r '.claude.seven_day.remaining // empty' | tr -d '%') || return
  [[ -n "$r5h" && -n "$r7d" ]] || return
  rm5h=$(parse_reset_to_minutes "$(echo "$json" | jq -r '.claude.five_hour.resets_in // empty')")
  rm7d=$(parse_reset_to_minutes "$(echo "$json" | jq -r '.claude.seven_day.resets_in // empty')")

  local r=${r5h%.*} rm=$rm5h
  if (( ${r7d%.*} < r )); then r=${r7d%.*}; rm=$rm7d; fi
  echo "Claude|${r}%|${rm}|$(remaining_to_pressure "$r" "$rm")"
}

parse_codex() {
  local json="$1"
  echo "$json" | jq -e '.codex' &>/dev/null || return
  local status
  status=$(echo "$json" | jq -r '.codex.status // empty') || return
  [[ "$status" == "ok" ]] || { echo "Codex|—|9999|UNAVAILABLE"; return; }

  local rp rs rmp rms
  rp=$(echo "$json" | jq -r '.codex.primary_window.remaining // empty' | tr -d '%') || return
  rs=$(echo "$json" | jq -r '.codex.secondary_window.remaining // empty' | tr -d '%') || return
  [[ -n "$rp" && -n "$rs" ]] || return
  rmp=$(parse_reset_to_minutes "$(echo "$json" | jq -r '.codex.primary_window.resets_in // empty')")
  rms=$(parse_reset_to_minutes "$(echo "$json" | jq -r '.codex.secondary_window.resets_in // empty')")

  local r=${rp%.*} rm=$rmp
  if (( ${rs%.*} < r )); then r=${rs%.*}; rm=$rms; fi
  echo "Codex|${r}%|${rm}|$(remaining_to_pressure "$r" "$rm")"
}

parse_codex_review() {
  local json="$1"
  echo "$json" | jq -e '.codex' &>/dev/null || return
  local status
  status=$(echo "$json" | jq -r '.codex.status // empty') || return
  [[ "$status" == "ok" ]] || { echo "Codex Review|—|9999|UNAVAILABLE"; return; }

  local used
  used=$(echo "$json" | jq -r '.codex.code_review.used // empty' | tr -d '%') || return
  [[ -n "$used" ]] || return
  local r=$((100 - ${used%.*}))
  echo "Codex Review|${r}%|9999|$(remaining_to_pressure "$r" "9999")"
}

parse_gemini_tier() {
  local json="$1" tier="$2" label="$3"
  echo "$json" | jq -e '.gemini' &>/dev/null || return
  local status
  status=$(echo "$json" | jq -r '.gemini.status // empty') || return
  [[ "$status" == "ok" ]] || { echo "${label}|—|9999|UNAVAILABLE"; return; }

  local worst_r=101 worst_rm=9999 found=false
  while IFS='|' read -r _name remaining reset; do
    [[ -n "$_name" ]] || continue
    found=true
    local r=${remaining%.*} rm
    rm=$(parse_reset_to_minutes "$reset")
    if (( r < worst_r )); then worst_r=$r; worst_rm=$rm; fi
  done < <(echo "$json" | jq -r "
    .gemini.models | to_entries[]
    | select(.key | test(\"${tier}\"))
    | \"\(.key)|\(.value.remaining // \"100%\" | rtrimstr(\"%\"))|\(.value.resets_in // \"24h\")\"
  " 2>/dev/null)
  $found || return
  echo "${label}|${worst_r}%|${worst_rm}|$(remaining_to_pressure "$worst_r" "$worst_rm")"
}

# ─── Orchestrator ─────────────────────────────────────────────────────

ROWS=()
ALL_RESET_MINUTES=()

collect_row() {
  local result="$1"
  if [[ -n "$result" ]]; then
    IFS='|' read -r _ _ rm _ <<< "$result"
    [[ "$rm" != "9999" ]] && ALL_RESET_MINUTES+=("$rm")
    ROWS+=("$result")
  fi
}

collect_row "$(parse_claude "$RAW_JSON" 2>/dev/null || true)"
collect_row "$(parse_codex "$RAW_JSON" 2>/dev/null || true)"
collect_row "$(parse_codex_review "$RAW_JSON" 2>/dev/null || true)"
collect_row "$(parse_gemini_tier "$RAW_JSON" flash "Gemini Flash" 2>/dev/null || true)"
collect_row "$(parse_gemini_tier "$RAW_JSON" pro "Gemini Pro" 2>/dev/null || true)"

if (( ${#ROWS[@]} == 0 )); then
  stale_epoch=$((NOW_EPOCH + 60))
  echo "QUOTA_CACHE|${NOW_EPOCH}|${stale_epoch}" > "$CACHE_FILE"
  exit 1
fi

# Cache TTL: min(15 minutes, earliest provider reset)
earliest=9999
for rm in "${ALL_RESET_MINUTES[@]}"; do (( rm < earliest )) && earliest=$rm; done
ttl=15; (( earliest < ttl )) && ttl=$earliest
stale_epoch=$((NOW_EPOCH + ttl * 60))

# ─── Output ───────────────────────────────────────────────────────────
# Emit structured lines: label|remaining%|pressure

output=""
for row in "${ROWS[@]}"; do
  IFS='|' read -r label remaining _rm pressure <<< "$row"
  [[ -n "$output" ]] && output+=$'\n'
  output+="${label}|${remaining}|${pressure}"
done

echo "$output"
{ echo "QUOTA_CACHE|${NOW_EPOCH}|${stale_epoch}"; echo "$output"; } > "$CACHE_FILE"
