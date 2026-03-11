#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  gemini-review.sh [--uncommitted] [--base <branch>] [--commit <sha>] [--title <title>] [--prompt <text>] [--plan]

Defaults:
  If no target is provided, the script uses --uncommitted.
  By default, reviews run in 'plan' mode (read-only) for safety.

Environment:
  GEMINI_SKILL_MODEL     Optional model override
  GEMINI_SKILL_APPROVAL  Optional approval policy override (defaults to 'plan' for reviews)
EOF
}

if ! command -v gemini >/dev/null 2>&1; then
  echo "Gemini CLI not found. Install it first and make sure \`gemini\` is on PATH." >&2
  exit 1
fi

target=""
custom_prompt=""
approval_mode="${GEMINI_SKILL_APPROVAL:-plan}"
approval_set_by_cli=0

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
      approval_set_by_cli=1
      shift
      ;;
    --plan)
      approval_mode="plan"
      approval_set_by_cli=1
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
  diff_content=$(git diff HEAD)
elif [[ "${target}" =~ ^base: ]]; then
  base_branch="${target#base:}"
  diff_content=$(git diff "${base_branch}...HEAD")
elif [[ "${target}" =~ ^commit: ]]; then
  commit_sha="${target#commit:}"
  diff_content=$(git show "${commit_sha}")
fi

if [[ -z "${diff_content}" ]]; then
  echo "No changes found to review for target: ${target}"
  exit 0
fi

# Build the final prompt for Gemini
final_prompt="Please review the following code changes and provide constructive feedback. Focus on potential bugs, security issues, performance improvements, and adherence to best practices.

${custom_prompt:+Additional instructions: ${custom_prompt}}

--- START OF CHANGES ---
${diff_content}
--- END OF CHANGES ---"

args=(
  --output-format
  text
  --approval-mode "${approval_mode}"
)

if [[ -n "${GEMINI_SKILL_MODEL:-}" ]]; then
  args+=(--model "${GEMINI_SKILL_MODEL}")
fi

exec gemini "${args[@]}" -p "${final_prompt}"
