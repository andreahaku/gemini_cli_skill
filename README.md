# Gemini CLI MCP & Skill

A comprehensive integration for using Gemini CLI as an MCP server and an orchestrated skill for Claude Code. This project allows multiple AI agents (Claude, Gemini, Codex) to collaborate effectively.

## Project Structure

- `src/`: Source code for the Gemini MCP Server (bridge for other MCP clients).
- `skill/gemini/`: Standalone Claude Code skill that interacts directly with the `gemini` CLI.
- `dist/`: Compiled server output.

---

## 1. Gemini CLI Agent Skill (Recommended for Claude Code)

The skill provides specialized instructions for Claude to act as an orchestrator for Gemini using the CLI directly. This approach leverages native session management and safety features.

### Key Features
- **Native Session Management**: Resume previous conversations with Gemini using `--resume latest`.
- **Safe Planning**: Uses `--approval-mode plan` for reviews and analysis to prevent accidental changes.
- **Independence**: Works directly with the `gemini` binary without requiring a running MCP server.

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

## Multi-Agent Collaboration Strategy

When working with multiple agents (Claude, Gemini, Codex):
- **Gemini**: Excels at advanced reasoning, architecture analysis, and Google Cloud integration.
- **Codex**: Optimized for pure code generation, refactoring, and applying patches.
- **Claude (You)**: Acts as the supervisor, orchestrator, and final integrator.

---

## License
MIT
