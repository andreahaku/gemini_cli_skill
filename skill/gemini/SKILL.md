name: gemini
description: >
  Use the local Gemini CLI for advanced reasoning, code generation, and multi-agent collaboration.
  This skill is independent from any MCP server and talks directly to the installed `gemini` CLI,
  leveraging its native session management and safety features.
user-invocable: true
argument-hint: "<prompt or review request>"
compatibility: Requires Gemini CLI installed and authenticated.
---

# Gemini

Use the local `gemini` CLI directly. This skill leverages the full power of the Gemini CLI, including session persistence and safe planning modes.

## Context

- Working directory: !`pwd`
- Current branch: !`git branch --show-current 2>/dev/null || true`
- Git status: !`git status -sb 2>/dev/null | head -20 || true`

## When to use this skill

- The user invokes `/gemini ...`
- The user explicitly asks you to delegate a task to Gemini.
- The user wants a code review, architecture analysis, or complex reasoning from Gemini.

## Workflow

### 1. General Consultation
For questions or tasks, use the `gemini-ask.sh` wrapper.

**Basic usage:**
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" "Analyze this architecture: $(cat main.ts)"
```

**Persistent Sessions:**
Gemini CLI maintains local sessions. You can list them or resume the latest one, or a specific one by index:
```bash
# List sessions for the current project
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" --list

# Resume the latest session
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" --resume latest "Now implement the suggested changes"

# Resume a specific session by index
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" --resume 2 "Riassumi questa conversazione"
```

**Approval Modes:**
- `--yolo`: Auto-approve all tool calls (use for trusted automated tasks).
- `--plan`: Read-only mode (ideal for analysis and reviews).
- `--approval <mode>`: Set a specific mode (`default`, `auto_edit`, `yolo`, `plan`).

### 2. Code Reviews
Use the dedicated review wrapper. It defaults to `--approval-mode plan` for safety.

```bash
# Review uncommitted changes
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-review.sh" --uncommitted

# Review against a base branch
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-review.sh" --base main --prompt "Focus on security"
```

## Advanced Gemini CLI Features

The Gemini CLI provides additional commands that you can run directly via `gemini <command>`:
- `gemini extensions list`: Manage capabilities.
- `gemini skills list`: Manage Gemini-native skills.
- `gemini hooks list`: Manage workflow integrations.

## Environment Variables
- `GEMINI_SKILL_MODEL`: Set the default model (e.g., `gemini-2.0-flash-exp`).
- `GEMINI_SKILL_APPROVAL`: Override the default approval policy.

## Best Practices
1. **Prefer `plan` mode** for reviews and analysis to prevent Gemini from making accidental changes.
2. **Use sessions** for long-running tasks to maintain context without re-sending full files.
3. **Summarize results** clearly, highlighting file paths and specific recommendations.
