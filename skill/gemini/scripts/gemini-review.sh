#!/usr/bin/env bash

set -euo pipefail

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

if ! command -v gemini >/dev/null 2>&1; then
  echo "Gemini CLI not found. Install it first and make sure \`gemini\` is on PATH." >&2
  exit 1
fi

target=""
custom_prompt=""
approval_mode="${GEMINI_SKILL_APPROVAL:-plan}"
approval_set_by_cli=0
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
      approval_set_by_cli=1
      shift
      ;;
    --plan)
      approval_mode="plan"
      approval_set_by_cli=1
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
  untracked=$(git ls-files --others --exclude-standard)
  if [[ -n "${untracked}" ]]; then
    for f in ${untracked}; do
      diff_content+=$'\n'"--- /dev/null"$'\n'"+++ b/${f}"$'\n'"$(cat "${f}" 2>/dev/null | sed 's/^/+/')"
    done
  fi
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

args=(
  --output-format
  text
  --approval-mode "${approval_mode}"
)

if [[ -n "${model}" ]]; then
  args+=(--model "${model}")
fi

exec gemini "${args[@]}" -p "${final_prompt}"
