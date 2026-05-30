#!/usr/bin/env bash
# gemini-exec.sh — Wrapper around `gemini` CLI with retry + fallback on transient errors
# Source this file, then call: gemini_exec "${args[@]}"
#
# Behavior:
#   1. Run gemini with the original args
#   2. If transient error (429/capacity/unavailable/overloaded), retry up to MAX_RETRIES times
#      with exponential backoff (3s, 6s, 9s)
#   3. If still failing, fallback to gemini-2.5-flash and retry once
#   4. If all attempts fail, show the error and exit 1
#
# Transient error patterns include:
#   - 429 (rate limited) / 503 (service unavailable)
#   - RESOURCE_EXHAUSTED / UNAVAILABLE gRPC status codes
#   - "rate limit" / "quota" / "capacity" / "overloaded" / "temporarily unavailable"
#     (per Google's April 2026 traffic prioritization changes, capacity errors during peak)

FALLBACK_MODEL="gemini-2.5-flash"
MAX_RETRIES=3
BACKOFF_BASE=3
TRANSIENT_ERROR_REGEX='429|503|rate.?limit|RESOURCE_EXHAUSTED|UNAVAILABLE|quota|capacity|overloaded|temporarily.?unavailable|server.?is.?busy'
GEMINI_DEFAULT_TIMEOUT=600

# Source the shared timeout helper (closes stdin, kills hung processes).
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-with-timeout.sh"

gemini_exec() {
  local args=("$@")
  local attempt=0
  local output
  local stderr_tmp
  local exit_code

  stderr_tmp="$(mktemp)"
  # Self-clearing RETURN trap: deregister after firing so it does not leak into
  # a caller function's scope (where ${stderr_tmp} would be unbound under `set -u`).
  trap 'rm -f "${stderr_tmp}"; trap - RETURN' RETURN

  # If the caller exported GEMINI_STDIN_FILE, route it through run_with_timeout
  # so gemini reads large prompts from stdin (avoids ARG_MAX on big diffs).
  local rwt_prefix=("${GEMINI_SKILL_TIMEOUT:-$GEMINI_DEFAULT_TIMEOUT}")
  if [[ -n "${GEMINI_STDIN_FILE:-}" && -r "${GEMINI_STDIN_FILE}" ]]; then
    rwt_prefix+=(--stdin "${GEMINI_STDIN_FILE}")
  fi

  # — Primary model: retry with backoff —
  while [[ $attempt -le $MAX_RETRIES ]]; do
    if [[ $attempt -gt 0 ]]; then
      local wait_time=$(( BACKOFF_BASE * attempt ))
      echo "Attempt $((attempt)) failed (transient error). Retrying with backoff..." >&2
      sleep "$wait_time"
    fi

    output=$(run_with_timeout "${rwt_prefix[@]}" gemini "${args[@]}" 2>"${stderr_tmp}") && exit_code=0 || exit_code=$?

    # 124 = timeout (GNU convention) — surface this distinctly so callers can react
    if [[ $exit_code -eq 124 ]]; then
      echo "[gemini-exec] timed out after ${GEMINI_SKILL_TIMEOUT:-$GEMINI_DEFAULT_TIMEOUT}s" >&2
      if [[ -s "${stderr_tmp}" ]]; then cat "${stderr_tmp}" >&2; fi
      return 124
    fi

    # Check if it's a 429 / rate limit error (check stderr, not stdout)
    if [[ $exit_code -ne 0 ]] && grep -qiE "${TRANSIENT_ERROR_REGEX}" "${stderr_tmp}" 2>/dev/null; then
      cat "${stderr_tmp}" >&2
      attempt=$((attempt + 1))
      continue
    fi

    # Non-rate-limit stderr goes to stderr
    if [[ -s "${stderr_tmp}" ]]; then
      cat "${stderr_tmp}" >&2
    fi

    # Success or non-rate-limit error — return stdout clean
    echo "$output"
    return $exit_code
  done

  # — Fallback to Flash model —
  echo "⚠️  Rate limited on primary model after $((MAX_RETRIES + 1)) attempts. Falling back to $FALLBACK_MODEL..." >&2

  # Build fallback args: replace --model <value> or append it
  local fallback_args=()
  local skip_next=0
  local model_replaced=0

  for arg in "${args[@]}"; do
    if [[ $skip_next -eq 1 ]]; then
      fallback_args+=("$FALLBACK_MODEL")
      skip_next=0
      model_replaced=1
      continue
    fi
    if [[ "$arg" == "--model" ]]; then
      fallback_args+=("$arg")
      skip_next=1
      continue
    fi
    fallback_args+=("$arg")
  done

  if [[ $model_replaced -eq 0 ]]; then
    fallback_args+=(--model "$FALLBACK_MODEL")
  fi

  output=$(run_with_timeout "${rwt_prefix[@]}" gemini "${fallback_args[@]}" 2>"${stderr_tmp}") && exit_code=0 || exit_code=$?

  if [[ $exit_code -eq 124 ]]; then
    echo "[gemini-exec] fallback model timed out after ${GEMINI_SKILL_TIMEOUT:-$GEMINI_DEFAULT_TIMEOUT}s" >&2
    if [[ -s "${stderr_tmp}" ]]; then cat "${stderr_tmp}" >&2; fi
    return 124
  fi

  if [[ $exit_code -ne 0 ]] && grep -qiE "${TRANSIENT_ERROR_REGEX}" "${stderr_tmp}" 2>/dev/null; then
    echo "❌ Rate limited on both primary and fallback ($FALLBACK_MODEL). Try again later." >&2
    cat "${stderr_tmp}" >&2
    return 1
  fi

  if [[ -s "${stderr_tmp}" ]]; then
    cat "${stderr_tmp}" >&2
  fi

  echo "$output"
  return $exit_code
}
