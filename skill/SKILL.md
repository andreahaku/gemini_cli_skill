---
name: gemini-cli-agent
description: Interact with Gemini CLI via the gemini-mcp server. Use this to delegate tasks to Gemini, manage persistent Gemini sessions, or collaborate between Claude and Gemini agents.
user-invocable: true
context: fork
---

# Gemini CLI Agent Skill

This skill enables Claude to act as an orchestrator for the Gemini CLI using the `gemini-mcp` server.

## Core Capabilities

- **Task Delegation**: Send complex prompts to Gemini for advanced reasoning, architecture analysis, or code generation.
- **Persistence**: Use `session_id` (`sid`) to maintain conversation context across multiple turns with Gemini.
- **Multi-Agent Collaboration**: Coordinate Claude, Gemini, and Codex by chaining their specific tools and strengths.

## Parameters and Variables
This skill can be invoked with arguments: `$ARGUMENTS`.
If provided, use `$ARGUMENTS` as the initial prompt for Gemini via the `gemini_ask` tool.

## Recommended Workflows

### 1. Quick Consultation
For a single question or one-off task for Gemini:
- Use the `gemini_ask` tool with your desired `prompt`.

### 2. Persistent Working Sessions
For complex tasks requiring multiple steps:
1. Choose a unique `sid` (e.g., `feature-x-dev`).
2. Send the first prompt using `gemini_ask` including the `sid`.
3. Continue sending subsequent prompts using the same `sid` to maintain context.

### 3. Monitoring
- Use `gemini_status` to view active Gemini sessions and their request counts.

## Multi-Agent Integration Strategy

When working in an environment with multiple MCP servers (Codex, Gemini, Claude):
- **Gemini** excels at: Advanced logical reasoning, detailed explanations, and Google Cloud/Workspace-related tasks.
- **Codex** excels at: Pure code generation, refactoring, and applying patches.
- **Claude** (You) acts as: The supervisor, orchestrator, and final integrator of the multi-agent workflow.

## Example Prompts

- "Ask Gemini to analyze the architecture of this file and then use Codex to implement the suggested changes."
- "Start a Gemini session named 'debug-db' to investigate this connection error."
- "Delegate the documentation of this module to Gemini while I work on the unit tests."
