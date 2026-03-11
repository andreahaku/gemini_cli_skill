#!/usr/bin/env bash

set -euo pipefail

if ! command -v gemini >/dev/null 2>&1; then
  echo "Gemini CLI not found. Install it first and make sure \`gemini\` is on PATH." >&2
  exit 1
fi

usage() {
  cat <<'EOF'
Usage:
  gemini-ask.sh [options] "<prompt>"

Options:
  -r, --resume <latest|index>  Resume a previous session
  --list                       List available sessions for current project
  --approval <mode>            Set approval mode (default, auto_edit, yolo, plan)
  --model <model>              Specify model
  --yolo                       YOLO mode (auto-approve all)
  --plan                       Read-only (plan) mode
  --fast                       Use Flash model for quick, low-latency responses
  --deep                       Use Pro model with max reasoning for complex analysis
  --structured                 Request JSON-structured output for cross-model chaining
  -h, --help                   Show this help

Environment (used as defaults, CLI flags take precedence):
  GEMINI_SKILL_MODEL           Default model (default: auto → Gemini 3.1 Pro)
  GEMINI_SKILL_APPROVAL        Default approval policy

You can also pipe a prompt on stdin.
EOF
}

# Environment variables as defaults — CLI flags override these
model="${GEMINI_SKILL_MODEL:-}"
approval="${GEMINI_SKILL_APPROVAL:-}"

args=(
  --output-format text
)

prompt=""
has_prompt=0
model_set_by_cli=0
approval_set_by_cli=0
structured=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--resume)
      if [[ $# -lt 2 ]]; then echo "--resume requires value"; exit 2; fi
      args+=(--resume "$2")
      shift 2
      ;;
    --list)
      exec gemini --list-sessions
      ;;
    --approval)
      if [[ $# -lt 2 ]]; then echo "--approval requires value"; exit 2; fi
      approval="$2"
      approval_set_by_cli=1
      shift 2
      ;;
    --model)
      if [[ $# -lt 2 ]]; then echo "--model requires value"; exit 2; fi
      model="$2"
      model_set_by_cli=1
      shift 2
      ;;
    --yolo)
      args+=(--yolo)
      approval_set_by_cli=1
      shift
      ;;
    --plan)
      approval="plan"
      approval_set_by_cli=1
      shift
      ;;
    --fast)
      model="gemini-2.5-flash"
      model_set_by_cli=1
      shift
      ;;
    --deep)
      model="pro"
      model_set_by_cli=1
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
      if [[ -n "${prompt}" ]]; then prompt+=" "; fi
      prompt+="$1"
      has_prompt=1
      shift
      ;;
  esac
done

# Apply model and approval (env default or CLI override, never duplicated)
if [[ -n "${model}" ]]; then
  args+=(--model "${model}")
fi

if [[ -n "${approval}" ]]; then
  args+=(--approval-mode "${approval}")
fi

# If no prompt and stdin is a pipe, read from stdin
if [[ $has_prompt -eq 0 ]]; then
  if [[ ! -t 0 ]]; then
    prompt="$(cat)"
    has_prompt=1
  fi
fi

if [[ $has_prompt -eq 0 ]]; then
  if [[ ${#args[@]} -gt 1 ]]; then
     echo "Error: No prompt provided." >&2
     usage
     exit 2
  fi
  exec gemini
fi

# Wrap prompt for structured output if requested
if [[ "${structured}" -eq 1 ]]; then
  prompt="You MUST respond with valid JSON only. Use this exact schema:
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

Task:
${prompt}"
fi

# Execute non-interactive
exec gemini "${args[@]}" -p "${prompt}"
