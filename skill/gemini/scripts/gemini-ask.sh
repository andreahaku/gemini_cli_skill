#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/gemini-exec.sh"

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
  --worker                     Worker mode: write output to scratchpad, structured by default
  --scratchpad <dir>           Scratchpad directory for worker mode output
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
structured=0
has_optional_flags=0
worker_mode=0
scratchpad_dir=""

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
      has_optional_flags=1
      shift 2
      ;;
    --model)
      if [[ $# -lt 2 ]]; then echo "--model requires value"; exit 2; fi
      model="$2"
      has_optional_flags=1
      shift 2
      ;;
    --yolo)
      args+=(--yolo)
      has_optional_flags=1
      shift
      ;;
    --plan)
      approval="plan"
      has_optional_flags=1
      shift
      ;;
    --fast)
      model="gemini-2.5-flash"
      has_optional_flags=1
      shift
      ;;
    --deep)
      model="pro"
      has_optional_flags=1
      shift
      ;;
    --structured)
      structured=1
      shift
      ;;
    --worker)
      worker_mode=1
      structured=1
      has_optional_flags=1
      shift
      ;;
    --scratchpad)
      if [[ $# -lt 2 ]]; then echo "--scratchpad requires a directory path" >&2; exit 2; fi
      scratchpad_dir="$2"
      has_optional_flags=1
      shift 2
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
  if [[ "${has_optional_flags}" -eq 1 ]]; then
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

# In structured mode, use JSON output format to prevent text formatter
# from inserting newlines between assistant turns that break JSON
if [[ "${structured}" -eq 1 ]]; then
  # Replace --output-format text with --output-format json
  for i in "${!args[@]}"; do
    if [[ "${args[$i]}" == "text" && $i -gt 0 && "${args[$((i-1))]}" == "--output-format" ]]; then
      args[$i]="json"
      break
    fi
  done
fi

# Execute non-interactive with retry + fallback on 429
if [[ "${worker_mode}" -eq 1 && -n "${scratchpad_dir}" ]]; then
  # Worker mode: capture output and write to scratchpad
  mkdir -p "${scratchpad_dir}/workers"
  tmp_output="$(mktemp)"
  trap 'rm -f "${tmp_output}"' EXIT

  worker_status="completed"
  if gemini_exec "${args[@]}" -p "${prompt}" > "${tmp_output}" 2>&1; then
    worker_status="completed"
  else
    worker_status="failed"
  fi

  {
    echo "---"
    echo "worker: gemini"
    echo "task: research"
    echo "status: ${worker_status}"
    echo "started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "completed: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "model: ${model:-auto}"
    echo "---"
    echo ""
    cat "${tmp_output}"
  } > "${scratchpad_dir}/workers/gemini.md"
  # Also write raw output for JSON parsing
  cp "${tmp_output}" "${scratchpad_dir}/workers/gemini.json" 2>/dev/null || true
  echo "[gemini-worker] Output written to ${scratchpad_dir}/workers/gemini.md" >&2
else
  gemini_exec "${args[@]}" -p "${prompt}"
fi
