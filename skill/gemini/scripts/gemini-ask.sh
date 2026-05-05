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
  --skip-trust
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
      # Force plan mode for worker safety (read-only by default)
      if [[ -z "${approval}" ]]; then
        approval="plan"
      fi
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

# Require --scratchpad when --worker is set
if [[ "${worker_mode}" -eq 1 && -z "${scratchpad_dir}" ]]; then
  echo "--worker requires --scratchpad <dir>" >&2
  exit 2
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

# If the prompt exceeds the safe ARG_MAX threshold, route it via stdin instead
# of the -p argument. gemini concatenates stdin + -p, so passing -p "" works.
LARGE_PROMPT_THRESHOLD="${GEMINI_LARGE_PROMPT_THRESHOLD:-50000}"
prompt_bytes=$(printf '%s' "${prompt}" | wc -c | tr -d ' ')
prompt_arg_for_p="${prompt}"
if (( prompt_bytes > LARGE_PROMPT_THRESHOLD )); then
  GEMINI_STDIN_FILE="$(mktemp -t gemini-prompt.XXXXXX)"
  printf '%s' "${prompt}" > "${GEMINI_STDIN_FILE}"
  trap 'rm -f "${GEMINI_STDIN_FILE}"' EXIT
  export GEMINI_STDIN_FILE
  prompt_arg_for_p=""
  echo "[gemini-ask] prompt size ${prompt_bytes}B > threshold ${LARGE_PROMPT_THRESHOLD}B — routing via stdin" >&2
fi

# Execute non-interactive with retry + fallback on 429
if [[ "${worker_mode}" -eq 1 ]]; then
  # Worker mode: capture output and always write to scratchpad (even on failure)
  mkdir -p "${scratchpad_dir}/workers"
  tmp_output="$(mktemp)"
  tmp_stderr="$(mktemp)"
  trap 'rm -f "${tmp_output}" "${tmp_stderr}"' EXIT

  worker_status="completed"
  worker_exit=0
  started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if gemini_exec "${args[@]}" -p "${prompt_arg_for_p}" > "${tmp_output}" 2>"${tmp_stderr}"; then
    worker_status="completed"
  else
    worker_exit=$?
    if [[ "${worker_exit}" -eq 124 ]]; then
      worker_status="timeout"
    else
      worker_status="failed"
    fi
  fi
  completed_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  {
    echo "---"
    echo "worker: gemini"
    echo "task: research"
    echo "status: ${worker_status}"
    echo "started: ${started_at}"
    echo "completed: ${completed_at}"
    echo "model: ${model:-auto}"
    echo "exit_code: ${worker_exit}"
    echo "---"
    echo ""
    if [[ -s "${tmp_output}" ]]; then
      cat "${tmp_output}"
    elif [[ "${worker_status}" == "timeout" ]]; then
      echo "Worker timed out."
      tail -n 5 "${tmp_stderr}" 2>/dev/null || true
    elif [[ "${worker_status}" == "failed" ]]; then
      echo "Worker failed."
      tail -n 5 "${tmp_stderr}" 2>/dev/null || true
    fi
  } > "${scratchpad_dir}/workers/gemini.md"
  if [[ -s "${tmp_output}" ]]; then
    cp "${tmp_output}" "${scratchpad_dir}/workers/gemini.json" 2>/dev/null || true
  fi
  echo "[gemini-worker] Output written to ${scratchpad_dir}/workers/gemini.md" >&2
else
  gemini_exec "${args[@]}" -p "${prompt_arg_for_p}"
fi
