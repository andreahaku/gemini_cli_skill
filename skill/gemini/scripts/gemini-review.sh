#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/gemini-exec.sh"
source "${SCRIPT_DIR}/agy-exec.sh"
source "${SCRIPT_DIR}/backend-detect.sh"

usage() {
  cat <<'EOF'
Usage:
  gemini-review.sh [--uncommitted] [--base <branch>] [--commit <sha>] [--title <title>] [--prompt <text>] [--plan]
                   [--fast] [--deep] [--structured]

Defaults:
  If no target is provided, the script uses --uncommitted.
  By default, reviews run in 'plan' mode (read-only) for safety.

Options:
  --fast           Use Flash model for quick reviews
  --deep           Use Pro model with max reasoning for thorough reviews
  --structured     Output JSON-structured findings for cross-model chaining

Environment:
  GEMINI_SKILL_MODEL     Optional model override (default: auto → Gemini 3.1 Pro)
  GEMINI_SKILL_APPROVAL  Optional approval policy override (defaults to 'plan' for reviews)
EOF
}

# Resolve backend (auto|agy|gemini). resolve_backend errors out if the chosen
# backend's CLI is missing, so no separate `command -v` check is needed.
backend="$(resolve_backend)" || exit 1

target=""
custom_prompt=""
approval_mode="${GEMINI_SKILL_APPROVAL:-plan}"
model="${GEMINI_SKILL_MODEL:-}"
structured=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uncommitted)
      target="uncommitted"
      shift
      ;;
    --base)
      if [[ $# -lt 2 ]]; then
        echo "--base requires a branch name" >&2
        exit 2
      fi
      target="base:$2"
      shift 2
      ;;
    --commit)
      if [[ $# -lt 2 ]]; then
        echo "--commit requires a commit SHA" >&2
        exit 2
      fi
      target="commit:$2"
      shift 2
      ;;
    --title)
      # Handled via prompt
      shift 2
      ;;
    --prompt)
      if [[ $# -lt 2 ]]; then
        echo "--prompt requires a value" >&2
        exit 2
      fi
      custom_prompt="$2"
      shift 2
      ;;
    --yolo)
      approval_mode="yolo"
      shift
      ;;
    --plan)
      approval_mode="plan"
      shift
      ;;
    --fast)
      model="gemini-2.5-flash"
      shift
      ;;
    --deep)
      model="pro"
      shift
      ;;
    --structured)
      structured=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -n "${custom_prompt}" ]]; then
        custom_prompt+=" "
      fi
      custom_prompt+="$1"
      shift
      ;;
  esac
done

if [[ -z "${target}" ]]; then
  target="uncommitted"
fi

# Gather the diff
diff_content=""
if [[ "${target}" == "uncommitted" ]]; then
  # Include both tracked changes and untracked files
  diff_content=$(git diff HEAD)
  while IFS= read -r -d '' f; do
    # Skip binary files (charset=binary catches images, archives, etc.
    # while allowing JSON, JS, TS, XML and other non-text/* source files)
    if file --brief --mime "${f}" 2>/dev/null | grep -q "charset=binary"; then
      diff_content+=$'\n'"--- /dev/null"$'\n'"+++ b/${f}"$'\n'"+[binary file]"
    else
      diff_content+=$'\n'"--- /dev/null"$'\n'"+++ b/${f}"$'\n'"$(sed 's/^/+/' "${f}" 2>/dev/null)"
    fi
  done < <(git ls-files -z --others --exclude-standard)
elif [[ "${target}" =~ ^base: ]]; then
  base_branch="${target#base:}"
  diff_content=$(git diff "${base_branch}...HEAD")
elif [[ "${target}" =~ ^commit: ]]; then
  commit_sha="${target#commit:}"
  diff_content=$(git show "${commit_sha}")
fi

if [[ -z "${diff_content}" ]]; then
  if [[ "${structured}" -eq 1 ]]; then
    echo '{"findings":[],"summary":"No changes found to review for target: '"${target}"'","model":"gemini"}'
  else
    echo "No changes found to review for target: ${target}"
  fi
  exit 0
fi

# Build the final prompt
if [[ "${structured}" -eq 1 ]]; then
  final_prompt="You MUST respond with valid JSON only. Use this exact schema:
{
  \"findings\": [
    {
      \"id\": \"<short-id>\",
      \"severity\": \"high|medium|low|info\",
      \"category\": \"bug|security|performance|architecture|style|missing\",
      \"file\": \"<file path or null>\",
      \"line\": <line number or null>,
      \"title\": \"<one-line summary>\",
      \"detail\": \"<explanation>\",
      \"recommendation\": \"<suggested fix or action>\",
      \"confidence\": \"high|medium|low\"
    }
  ],
  \"summary\": \"<2-3 sentence overview>\",
  \"model\": \"gemini\"
}

Do not include any text outside the JSON block.

Review the following code changes. Focus on potential bugs, security issues, performance improvements, and adherence to best practices.
${custom_prompt:+Additional instructions: ${custom_prompt}}

--- START OF CHANGES ---
${diff_content}
--- END OF CHANGES ---"
else
  final_prompt="Please review the following code changes and provide constructive feedback. Focus on potential bugs, security issues, performance improvements, and adherence to best practices.

${custom_prompt:+Additional instructions: ${custom_prompt}}

--- START OF CHANGES ---
${diff_content}
--- END OF CHANGES ---"
fi

output_fmt="text"
if [[ "${structured}" -eq 1 ]]; then
  output_fmt="json"
fi

args=(
  --output-format
  "${output_fmt}"
  --approval-mode "${approval_mode}"
  --skip-trust
)

if [[ -n "${model}" ]]; then
  args+=(--model "${model}")
fi

# --- Level-A context compression (lossless; protects code blocks; no-op on small input) ---
# Large review prompts are mostly diffs + logs — compress the noise (protects fenced code)
# so big reviews fit and cost less. Best-effort: only replaces on non-empty output.
_cc_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compress-context.ts"
if command -v bun >/dev/null 2>&1 && [[ -f "${_cc_script}" ]]; then
  # `printf X` sentinel preserves trailing newlines that $() would otherwise strip.
  _cc_out="$(printf '%s' "${final_prompt}" | bun "${_cc_script}" --skill gemini-review --guard 700000; printf X)"
  _cc_out="${_cc_out%X}"
  [[ -n "${_cc_out//[[:space:]]/}" ]] && final_prompt="${_cc_out}"
fi

# If the prompt exceeds the safe ARG_MAX threshold (mostly large diffs), route
# it via stdin instead of -p. gemini concatenates stdin + -p, so -p "" works.
LARGE_PROMPT_THRESHOLD="${GEMINI_LARGE_PROMPT_THRESHOLD:-50000}"
prompt_bytes=$(printf '%s' "${final_prompt}" | wc -c | tr -d ' ')
prompt_arg_for_p="${final_prompt}"
if (( prompt_bytes > LARGE_PROMPT_THRESHOLD )); then
  GEMINI_STDIN_FILE="$(mktemp -t gemini-review.XXXXXX)"
  printf '%s' "${final_prompt}" > "${GEMINI_STDIN_FILE}"
  trap 'rm -f "${GEMINI_STDIN_FILE}"' EXIT
  export GEMINI_STDIN_FILE
  prompt_arg_for_p=""
  echo "[gemini-review] prompt size ${prompt_bytes}B > threshold ${LARGE_PROMPT_THRESHOLD}B — routing via stdin" >&2
fi

# Dispatch to the resolved backend. agy lacks --output-format/--approval-mode:
# structured JSON comes from the prompt instruction already baked into
# final_prompt, plan-mode is implicit in single-shot --print, and only yolo
# needs translation (--dangerously-skip-permissions).
if [[ "${backend}" == "agy" ]]; then
  agy_args=(--print "${prompt_arg_for_p}")
  if [[ "${approval_mode}" == "yolo" ]]; then
    agy_args+=(--dangerously-skip-permissions)
  fi
  agy_exec "${agy_args[@]}"
else
  gemini_exec "${args[@]}" -p "${prompt_arg_for_p}"
fi
