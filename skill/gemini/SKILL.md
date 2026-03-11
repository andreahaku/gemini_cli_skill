---
name: gemini
description: >
  Use the local Gemini CLI for advanced reasoning, code generation, and multi-agent collaboration.
  Invoke this skill when the user explicitly asks to consult Gemini, delegate a task to Gemini,
  run /gemini, continue or resume a Gemini conversation, or request a Gemini review of local changes,
  a branch, a commit, or a PR. Also use this skill when Claude decides that Gemini's strengths
  (large context window, multimodal reasoning, grounded search) would complement its own analysis —
  for instance to get a second opinion, validate an architectural decision, or cross-check a complex
  code review. This skill is independent from any MCP server and talks directly to the installed
  `gemini` CLI.
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

## Workflow

1. Decide whether the request is a **consultation** (ask) or a **code review**.
2. For consultations, decide the session strategy (see below).
3. For reviews, use the review wrapper (see below).

### Consultations

Start a fresh consultation (default — most common case):

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" "<prompt>"
```

Resume the latest Gemini session when the user is clearly continuing a previous Gemini conversation:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" --resume latest "<follow-up prompt>"
```

Resume a specific session by index:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" --resume 2 "<follow-up prompt>"
```

List available sessions for the current project:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" --list
```

### Approval Modes

- `--plan`: Read-only mode. Best for analysis, reviews, and when Gemini should not touch files.
- `--yolo`: Auto-approve all tool calls. Only for trusted automated tasks.
- `--approval <mode>`: Explicit mode — one of `default`, `auto_edit`, `yolo`, `plan`.

Default is `default` for consultations. Reviews default to `plan`.

### Code Reviews

Use the dedicated review wrapper. It defaults to `plan` mode for safety.

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-review.sh" --uncommitted
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-review.sh" --base main
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-review.sh" --commit <sha>
```

Add custom instructions with `--prompt`:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-review.sh" --uncommitted --prompt "Focus on security"
```

## Session Strategy

- Start a fresh session for new questions, isolated tasks, or one-shot consultations.
- Use `--resume latest` when the user says to continue, iterate on, or follow up the most recent Gemini conversation.
- Use `--resume <index>` when the user refers to a specific past session or when multiple ongoing threads make `latest` ambiguous.
- If the continuation target is ambiguous, ask one short clarifying question.

## Review Defaults

- No target specified → `--uncommitted`.
- User refers to a specific commit → `--commit`.
- User refers to branch or PR changes against a base → `--base`.
- If the review target is ambiguous and the wrong target would be misleading, ask one short clarifying question.

## Multi-Agent Collaboration

When Claude delegates work to Gemini as part of a broader multi-model workflow:

### One-Shot Consultation
For a focused question where Claude needs Gemini's perspective once:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" --plan "<specific question with full context>"
```

Use `--plan` to ensure Gemini only analyzes and does not modify files. Include all necessary context in the prompt — Gemini does not share Claude's conversation history.

### Providing Context to Gemini
Gemini cannot see Claude's conversation. When delegating, always embed the relevant context directly in the prompt:
- For code analysis: include the file contents or a diff inline.
- For architecture questions: summarize the current design and constraints.
- For follow-ups on a previous Gemini session: use `--resume` so Gemini has its own prior context.

### Interpreting Results
After receiving Gemini's response:
1. Summarize the key findings and attribute them to Gemini.
2. Preserve concrete details: file paths, line references, specific recommendations.
3. If Gemini's analysis conflicts with Claude's own, present both perspectives and let the user decide.
4. If Gemini's output will be forwarded to another model (e.g., Codex), extract the actionable parts cleanly.

## Environment Variables

- `GEMINI_SKILL_MODEL`: Override the default model (e.g., `gemini-2.5-pro`).
- `GEMINI_SKILL_APPROVAL`: Override the default approval policy.

## Notes

- The wrappers live inside this skill, so the skill remains portable and independent from `gemini_mcp`.
- For advanced Gemini CLI features, run `gemini <command>` directly: `gemini extensions list`, `gemini skills list`, `gemini hooks list`.
