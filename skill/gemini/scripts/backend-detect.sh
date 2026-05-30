#!/usr/bin/env bash
# backend-detect.sh — Resolve which Gemini backend to use.
# Source this file, then call: resolve_backend
#
# The /gemini skill can run on two backends:
#   - agy     : Antigravity CLI (`agy`). Serves Gemini 3.5 Flash (default model,
#               auto-selected). Required path after 18/6/2026 when the legacy
#               `gemini` CLI stops serving the Google One AI Pro plan.
#   - gemini  : Legacy Gemini CLI (`gemini`). Serves Gemini 3.1/2.5. Still used
#               for session listing and as a large-prompt fallback.
#
# Selection (env var GEMINI_BACKEND, default `auto`):
#   - auto    : prefer agy if installed, else fall back to gemini
#   - agy     : force agy (error if not installed)
#   - gemini  : force gemini (error if not installed)
#
# resolve_backend prints the resolved backend name ("agy"|"gemini") on stdout,
# or exits non-zero with a message on stderr if nothing usable is available.

resolve_backend() {
  local requested="${GEMINI_BACKEND:-auto}"
  local have_agy=0
  local have_gemini=0
  command -v agy >/dev/null 2>&1 && have_agy=1
  command -v gemini >/dev/null 2>&1 && have_gemini=1

  case "${requested}" in
    agy)
      if [[ "${have_agy}" -eq 1 ]]; then echo "agy"; return 0; fi
      echo "GEMINI_BACKEND=agy but \`agy\` (Antigravity CLI) is not on PATH." >&2
      return 1
      ;;
    gemini)
      if [[ "${have_gemini}" -eq 1 ]]; then echo "gemini"; return 0; fi
      echo "GEMINI_BACKEND=gemini but \`gemini\` CLI is not on PATH." >&2
      return 1
      ;;
    auto|"")
      if [[ "${have_agy}" -eq 1 ]]; then echo "agy"; return 0; fi
      if [[ "${have_gemini}" -eq 1 ]]; then echo "gemini"; return 0; fi
      echo "Neither \`agy\` (Antigravity CLI) nor \`gemini\` CLI is on PATH. Install one." >&2
      return 1
      ;;
    *)
      echo "Invalid GEMINI_BACKEND='${requested}'. Use auto|agy|gemini. Defaulting to auto." >&2
      if [[ "${have_agy}" -eq 1 ]]; then echo "agy"; return 0; fi
      if [[ "${have_gemini}" -eq 1 ]]; then echo "gemini"; return 0; fi
      return 1
      ;;
  esac
}
