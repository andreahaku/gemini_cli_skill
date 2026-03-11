# Gemini CLI MCP & Skill

A comprehensive integration for using Gemini CLI as an MCP server and an orchestrated skill for Claude Code. This project allows multiple AI agents (Claude, Gemini, Codex) to collaborate effectively.

## Project Structure

```
src/                          # Gemini MCP Server (bridge for MCP clients)
skill/gemini/                 # Standalone Claude Code skill
├── SKILL.md                  # Skill instructions and routing guide
├── references/               # Additional documentation
└── scripts/
    ├── gemini-ask.sh         # Main consultation wrapper (sessions, depth control)
    ├── gemini-review.sh      # Code review wrapper (uncommitted, branch, commit)
    ├── cross-model-tracker.sh # Cross-model session tracking
    └── debate.sh             # Automated cross-model debate/critique
dist/                         # Compiled server output
```

---

## 1. Gemini CLI Agent Skill (Recommended for Claude Code)

The skill provides specialized instructions for Claude to act as an orchestrator for Gemini using the CLI directly. This approach leverages native session management and safety features.

### Key Features
- **Native Session Management**: Resume previous conversations with Gemini using `--resume latest` or a specific index (e.g., `--resume 2`).
- **Safe Planning**: Uses `--approval-mode plan` for reviews and analysis to prevent accidental changes.
- **Independence**: Works directly with the `gemini` binary without requiring a running MCP server.
- **Depth Control**: `--fast` (gemini-2.5-flash), default (Gemini 3.1 Pro via `auto`), `--deep` (explicit Pro with max reasoning).
- **Structured Output**: `--structured` flag for JSON output (`{ findings[], summary, model }`) for cross-model chaining.

### Installation
Copy the `skill/gemini` directory to your Claude skills folder:
```bash
cp -r skill/gemini ~/.claude/skills/gemini
```

---

## 2. Gemini MCP Server

The MCP server acts as a bridge for MCP-compatible clients (like Claude Desktop) that don't support custom skills or direct shell execution.

### Installation
1. Ensure **Gemini CLI** is installed and authenticated.
2. Install dependencies and build:
   ```bash
   npm install
   npm run build
   ```

### MCP Configuration
Add the following to your MCP client configuration (e.g., `claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "gemini": {
      "command": "node",
      "args": ["/path/to/gemini_mcp/dist/index.js"]
    }
  }
}
```

### Available Tools
- `gemini_ask`: Send a prompt to Gemini CLI. Supports persistent sessions via `sid`.
- `gemini_status`: View active sessions and request counts.

---

## Multi-Agent Collaboration

When working with multiple agents (Claude, Gemini, Codex):

- **Gemini**: Advanced reasoning, large context analysis, platform-specific knowledge (iOS/Android/BLE), multimodal capabilities, Google Cloud integration.
- **Codex**: Code generation, refactoring, patches, algorithm/logic bug detection, state machine reasoning.
- **Claude**: Supervisor, orchestrator, final integrator.

### Cross-Model Features

| Feature | Script | Description |
|---------|--------|-------------|
| **Reviews** | `gemini-review.sh` / `codex-review.sh` | Run parallel reviews from both models to find complementary blind spots |
| **Debate** | `debate.sh` | Automated critique cycle: Model A responds, Model B critiques, Model A revises. Configurable rounds. |
| **Session Tracking** | `cross-model-tracker.sh` | Link Codex and Gemini sessions under a shared thread ID with turn summaries |
| **Structured Output** | `--structured` flag | JSON output format for machine-readable cross-model chaining |
| **Depth Control** | `--fast` / `--deep` | Adjust model and reasoning depth per task complexity |

### Routing Guide

| Task Type | Best Model | Why |
|-----------|-----------|-----|
| Platform-specific (iOS/Android/BLE) | **Gemini** | Platform quirks, real-world edge cases |
| Large codebase analysis | **Gemini** | Largest context window |
| Logic/algorithm bugs | **Codex** | Strong state machine reasoning |
| Code review | **Both** in parallel | Different blind spots |
| Security audit | **Both** in parallel | Complementary: integration risks vs logic flaws |
| Quick lookups | Either with `--fast` | Fastest response |

---

## License
MIT
