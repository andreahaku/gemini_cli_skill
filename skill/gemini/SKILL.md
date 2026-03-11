---
name: gemini
description: >
  Use the local Gemini CLI for advanced reasoning, code generation, and multi-agent collaboration.
  Invoke this skill when the user explicitly asks to consult Gemini, delegate a task to Gemini,
  run /gemini, continue or resume a Gemini conversation, or request a Gemini review of local changes,
  a branch, a commit, or a PR. Also use this skill when Claude decides that Gemini's strengths
  (large context window, multimodal reasoning, grounded search, platform awareness) would complement
  its own analysis — for instance to get a second opinion, validate an architectural decision, or
  cross-check a complex code review. This skill is independent from any MCP server and talks
  directly to the installed `gemini` CLI.
user-invocable: true
argument-hint: "<prompt or review request>"
compatibility: Requires Gemini CLI installed and authenticated.
---

# Gemini

Use the local `gemini` CLI directly (Gemini 3.1 Pro default). This skill leverages the full power of the Gemini CLI, including session persistence and safe planning modes.

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

## Depth Control

Choose the depth level based on task complexity:

- `--fast`: Uses `gemini-2.5-flash`. Best for quick lookups, simple questions, high-throughput tasks. Fast and lightweight.
- *(default)*: Uses `auto` which resolves to Gemini 3.1 Pro. Good for most tasks.
- `--deep`: Explicitly uses `pro` (Gemini 3.1 Pro). Best for complex architecture analysis, deep reasoning, security audits.

```bash
# Quick question
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" --fast "What's the default BLE MTU size on iOS?"

# Deep analysis
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" --deep "Analyze this entire module for architectural issues: $(cat src/ble/)"

# Fast review
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-review.sh" --fast --uncommitted
```

## Structured Output

Use `--structured` to get JSON output for machine-readable results. This is essential for cross-model chaining — when output from Gemini will be compared with or fed to Codex.

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" --structured "Review this function for bugs: $(cat src/utils.ts)"
```

Output schema: `{ findings[], summary, model }` — each finding has `id`, `severity`, `category`, `file`, `line`, `title`, `detail`, `recommendation`, `confidence`.

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

## Multi-Agent Routing Guide

Use this guide when deciding whether to delegate a task to Gemini, Codex, or both:

| Task Type | Best Model | Depth | Why |
|-----------|-----------|-------|-----|
| Platform-specific (iOS/Android/BLE) | **Gemini** | --deep | Excellent at platform quirks, real-world edge cases, battery/lifecycle |
| Large codebase analysis | **Gemini** | default | Largest context window, can process entire modules |
| Code review (general) | **Both** in parallel | default | Different blind spots — merge findings |
| Security audit | **Both** in parallel | --deep | Gemini finds integration risks, Codex finds logic flaws |
| Architecture design | Codex first, **Gemini** validates | --deep | Gemini adds real-world platform considerations |
| Logic/algorithm bugs | **Codex** first | --deep | Better at state machine reasoning |
| Quick syntax/API question | **Gemini** | --fast | Flash model is very fast for simple lookups |
| Multimodal analysis (images, video) | **Gemini** | default | Native multimodal capabilities |

## Multi-Agent Collaboration

When Claude delegates work to Gemini as part of a broader multi-model workflow:

### One-Shot Consultation
For a focused question where Claude needs Gemini's perspective once:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-ask.sh" --plan "<specific question with full context>"
```

Use `--plan` to ensure Gemini only analyzes and does not modify files. Include all necessary context in the prompt — Gemini does not share Claude's conversation history.

### Cross-Model Session Tracking
For tasks involving both Codex and Gemini, use the shared tracker to link sessions:

```bash
# Create a shared thread
bash "${CLAUDE_SKILL_DIR}/scripts/cross-model-tracker.sh" new "auth-redesign"

# Link Gemini session
bash "${CLAUDE_SKILL_DIR}/scripts/cross-model-tracker.sh" link "auth-redesign" gemini "latest"

# Log a turn summary after each model interaction
bash "${CLAUDE_SKILL_DIR}/scripts/cross-model-tracker.sh" log "auth-redesign" gemini "Validated JWT rotation approach, flagged iOS background refresh limits"

# Export context for injection into the next model's prompt
context=$(bash "${CLAUDE_SKILL_DIR}/scripts/cross-model-tracker.sh" export "auth-redesign")
```

### Debate Mode
For thorough analysis with automatic cross-model critique:

```bash
GEMINI_SKILL_DIR="${CLAUDE_SKILL_DIR}" \
bash "${CLAUDE_SKILL_DIR}/scripts/debate.sh" \
  --topic "Should we use WebSockets or SSE for real-time BLE data streaming?" \
  --first gemini \
  --rounds 1 \
  --deep \
  --output-dir /tmp/debate-ble-streaming
```

The debate script automates: Model A responds → Model B critiques → Model A addresses critique. Multiple rounds are supported. After the debate, read all round files and synthesize: consensus points, divergences, unique insights, and corrected errors.

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

- `GEMINI_SKILL_MODEL`: Override the default model (default: auto → Gemini 3.1 Pro). Use CLI aliases: `pro`, `flash`, `flash-lite`.
- `GEMINI_SKILL_APPROVAL`: Override the default approval policy.

## Notes

- The wrappers live inside this skill, so the skill remains portable and independent from `gemini_mcp`.
- For advanced Gemini CLI features, run `gemini <command>` directly: `gemini extensions list`, `gemini skills list`, `gemini hooks list`.
