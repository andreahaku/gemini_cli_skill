# Gemini CLI wrappers

This skill uses local wrapper scripts instead of the MCP server in this repository.

## Ask wrapper

Path:

```bash
${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh
```

Behavior:

- Defaults to a fresh Gemini session
- Supports session resume via `--resume latest` or `--resume <index>`
- Lists available sessions via `--list`
- Accepts the prompt either as arguments, with `--prompt`, or interactively (when no prompt is given)
- Approval modes: `--plan` (read-only), `--yolo` (auto-approve), `--approval <mode>`

Depth and model flags:

- `--fast` uses `gemini-2.5-flash` — fast, lightweight
- `--deep` uses `pro` (Gemini 3.1 Pro) — max analysis depth
- *(default)* uses `auto` which resolves to Gemini 3.1 Pro
- `--structured` switches output format to JSON for machine-readable results

Optional environment variables:

- `GEMINI_SKILL_MODEL` — model override (CLI aliases: `pro`, `flash`, `flash-lite`, or full model names)
- `GEMINI_SKILL_APPROVAL` — approval policy override

Examples:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" "Review this architecture for scalability issues"
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" --resume latest "Continue the analysis"
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" --fast "What's the default BLE MTU size on iOS?"
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" --deep --structured "Analyze this module for security issues"
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" --plan "Read-only analysis of the codebase"
```

## Review wrapper

Path:

```bash
${CLAUDE_SKILL_DIR}/scripts/gemini-review.sh
```

Supported options:

- `--uncommitted`
- `--base <branch>`
- `--commit <sha>`
- `--title <title>`
- `--prompt <text>`
- `--fast` — Flash model for quick reviews
- `--deep` — Pro model for thorough reviews
- `--structured` — JSON output with findings schema

Behavior:

- Runs `gemini` directly with the diff as prompt context
- Defaults to `--uncommitted` when no explicit target is provided
- Defaults to `--approval-mode plan` for safety (reviews are read-only)
- Includes untracked files in `--uncommitted` mode with proper binary detection
- Uses `--output-format json` when `--structured` is enabled

## Cross-model tracker

Path:

```bash
${CLAUDE_SKILL_DIR}/scripts/cross-model-tracker.sh
```

Manages shared threads across Codex and Gemini. Commands:

- `new <name>` — create a new cross-model thread
- `link <name> <model> <session-ref>` — link a model session to a thread
- `log <name> <model> <summary>` — append a turn summary
- `get <name>` — show thread state (JSON)
- `list` — list all active threads
- `export <name>` — export context summary for prompt injection

Thread names must match `^[a-zA-Z0-9_-]+$` (alphanumeric, hyphens, underscores only).
State is stored in `~/.claude/cross-model-threads/`.

## Debate script

Path:

```bash
${CLAUDE_SKILL_DIR}/scripts/debate.sh
```

Automates structured cross-model critique cycles. Options:

- `--topic <text>` — the question to debate (required)
- `--first <model>` — which model goes first: `codex` or `gemini` (default: codex)
- `--rounds <n>` — number of critique rounds (default: 1)
- `--context <text>` — additional context for all prompts
- `--structured` — use JSON output
- `--fast` / `--deep` — depth control
- `--output-dir <dir>` — save round outputs

Debate flow: Model A responds, Model B critiques, Model A addresses critique. In additional rounds, roles stay fixed (no swap) to prevent a model from critiquing its own output.

Requires `CODEX_SKILL_DIR` environment variable to locate the Codex skill.
