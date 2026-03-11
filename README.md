# Gemini CLI MCP & Skill

A comprehensive integration for using Gemini CLI as an MCP server and an orchestrated skill for Claude Code. This project allows multiple AI agents (Claude, Gemini, Codex) to collaborate effectively.

## Project Structure

- `src/`: Source code for the Gemini MCP Server.
- `skill/`: Claude Code / Gemini CLI skill for agent orchestration.
- `dist/`: Compiled server output.

## 1. Gemini MCP Server

The MCP server acts as a bridge between the Gemini CLI and any MCP-compatible client.

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

## 2. Gemini CLI Agent Skill

The skill provides specialized instructions for Claude to act as an orchestrator for Gemini.

### Features

- **Task Delegation**: Seamlessly hand over complex reasoning or Google Cloud tasks to Gemini.
- **Context Persistence**: Maintains history across multiple turns using session IDs.
- **Multi-Agent Workflows**: Orchestrate sequences between Claude, Gemini, and Codex.

### Installation

Copy the `skill/` directory to your Claude skills folder:
```bash
cp -r skill/ ~/.claude/skills/gemini-cli-agent
```

Or install the pre-packaged `.skill` file:
```bash
gemini skills install skill/gemini-cli-agent.skill --scope user
```

---

## License

MIT
