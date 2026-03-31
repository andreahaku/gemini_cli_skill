#!/usr/bin/env bash
# gemini-exec.sh — Wrapper around `gemini` CLI with retry + fallback on 429
# Source this file, then call: gemini_exec "${args[@]}"
#
# Behavior:
#   1. Run gemini with the original args
#   2. If 429 (rate limited), retry up to 2 times with exponential backoff (3s, 6s)
#   3. If still failing, fallback to gemini-2.5-flash and retry once
#   4. If all attempts fail, show the error and exit 1

FALLBACK_MODEL="gemini-2.5-flash"
MAX_RETRIES=2
BACKOFF_BASE=3

gemini_exec() {
  local args=("$@")
  local attempt=0
  local output
  local exit_code

  # — Primary model: retry with backoff —
  while [[ $attempt -le $MAX_RETRIES ]]; do
    if [[ $attempt -gt 0 ]]; then
      local wait_time=$(( BACKOFF_BASE * attempt ))
      echo "⏳ Rate limited (429). Retrying in ${wait_time}s... (attempt $((attempt + 1))/$((MAX_RETRIES + 1)))" >&2
      sleep "$wait_time"
    fi

    output=$(gemini "${args[@]}" 2>&1) && exit_code=0 || exit_code=$?

    # Check if it's a 429 / rate limit error
    if [[ $exit_code -ne 0 ]] && echo "$output" | grep -qiE '429|rate.limit|RESOURCE_EXHAUSTED|quota'; then
      attempt=$((attempt + 1))
      continue
    fi

    # Success or non-rate-limit error — return as-is
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

  output=$(gemini "${fallback_args[@]}" 2>&1) && exit_code=0 || exit_code=$?

  if [[ $exit_code -ne 0 ]] && echo "$output" | grep -qiE '429|rate.limit|RESOURCE_EXHAUSTED|quota'; then
    echo "❌ Rate limited on both primary and fallback ($FALLBACK_MODEL). Try again later." >&2
    echo "$output"
    return 1
  fi

  echo "$output"
  return $exit_code
}
