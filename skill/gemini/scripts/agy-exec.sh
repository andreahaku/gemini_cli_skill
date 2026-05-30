#!/usr/bin/env bash
# agy-exec.sh — Wrapper around the `agy` (Antigravity CLI) backend.
# Source this file, then call: agy_exec "${agy_args[@]}"
#
# `agy_args` are agy-NATIVE arguments (everything that would follow `agy`), e.g.:
#   --print "<prompt>"
#   --print "" --conversation <id>      (resume by id)
#   --print "<prompt>" -c               (continue most recent)
#   --print "<prompt>" --dangerously-skip-permissions   (yolo)
#
# agy has no --model / --output-format / --approval-mode / --skip-trust flags.
#   - Model: pinned in ~/.gemini/antigravity-cli/settings.json (Gemini 3.5 Flash,
#     auto-selected default). There is no per-call model override, so callers that
#     ask for --fast/--deep/--model are served the 3.5 default on this backend.
#   - JSON output: there is no native flag — structured callers must embed the
#     "respond with valid JSON only" instruction in the prompt (the caller scripts
#     already do this). agy then prints clean JSON.
#   - Approval: --print is single-shot non-interactive; yolo maps to
#     --dangerously-skip-permissions.
#
# Behavior mirrors gemini-exec.sh: retry up to MAX_RETRIES on transient errors
# with exponential backoff. Unlike gemini-exec there is no fallback model
# (the 3.5 default is the only model agy serves on this plan).
#
# Large prompts: if the caller exports GEMINI_STDIN_FILE, it is fed to agy's
# stdin via run_with_timeout. agy concatenates stdin + the `--print ""` arg,
# same convention as gemini.

AGY_MAX_RETRIES=3
AGY_BACKOFF_BASE=3
AGY_TRANSIENT_ERROR_REGEX='429|503|rate.?limit|RESOURCE_EXHAUSTED|UNAVAILABLE|quota|capacity|overloaded|temporarily.?unavailable|server.?is.?busy'
AGY_DEFAULT_TIMEOUT=600
# Cosmetic log noise agy occasionally surfaces. Generation still succeeds; the
# "not logged into Antigravity" line refers to the model-LIST polling endpoint,
# not the auth used for generation (Google One OAuth, which is present).
AGY_NOISE_REGEX='not logged into Antigravity|FetchAvailableModels|Singleflight refresh failed|Cache\(availableModels\)'

# Source the shared timeout helper (closes stdin, kills hung processes).
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-with-timeout.sh"

agy_exec() {
  local args=("$@")
  local attempt=0
  local output
  local stderr_tmp
  local exit_code

  stderr_tmp="$(mktemp)"
  # Self-clearing RETURN trap: deregister after firing so it does not leak into
  # the caller's scope (where ${stderr_tmp} would be unbound under `set -u`).
  trap 'rm -f "${stderr_tmp}"; trap - RETURN' RETURN

  # Route large prompts through stdin (avoids ARG_MAX on big diffs).
  local rwt_prefix=("${GEMINI_SKILL_TIMEOUT:-$AGY_DEFAULT_TIMEOUT}")
  if [[ -n "${GEMINI_STDIN_FILE:-}" && -r "${GEMINI_STDIN_FILE}" ]]; then
    rwt_prefix+=(--stdin "${GEMINI_STDIN_FILE}")
  fi

  while [[ $attempt -le $AGY_MAX_RETRIES ]]; do
    if [[ $attempt -gt 0 ]]; then
      local wait_time=$(( AGY_BACKOFF_BASE * attempt ))
      echo "[agy-exec] attempt $((attempt)) failed (transient error). Retrying with backoff..." >&2
      sleep "$wait_time"
    fi

    output=$(run_with_timeout "${rwt_prefix[@]}" agy "${args[@]}" 2>"${stderr_tmp}") && exit_code=0 || exit_code=$?

    # Strip cosmetic noise from stderr before surfacing it.
    if [[ -s "${stderr_tmp}" ]]; then
      grep -viE "${AGY_NOISE_REGEX}" "${stderr_tmp}" > "${stderr_tmp}.clean" 2>/dev/null || true
      mv -f "${stderr_tmp}.clean" "${stderr_tmp}" 2>/dev/null || true
    fi

    # 124 = timeout (GNU convention)
    if [[ $exit_code -eq 124 ]]; then
      echo "[agy-exec] timed out after ${GEMINI_SKILL_TIMEOUT:-$AGY_DEFAULT_TIMEOUT}s" >&2
      if [[ -s "${stderr_tmp}" ]]; then cat "${stderr_tmp}" >&2; fi
      return 124
    fi

    # Transient error → retry
    if [[ $exit_code -ne 0 ]] && grep -qiE "${AGY_TRANSIENT_ERROR_REGEX}" "${stderr_tmp}" 2>/dev/null; then
      cat "${stderr_tmp}" >&2
      attempt=$((attempt + 1))
      continue
    fi

    # Surface any remaining (non-noise) stderr
    if [[ -s "${stderr_tmp}" ]]; then
      cat "${stderr_tmp}" >&2
    fi

    echo "$output"
    return $exit_code
  done

  echo "❌ [agy-exec] Rate limited after $((AGY_MAX_RETRIES + 1)) attempts. Try again later, or set GEMINI_BACKEND=gemini." >&2
  return 1
}
