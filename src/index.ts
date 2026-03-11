#!/usr/bin/env node

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema
} from '@modelcontextprotocol/sdk/types.js';
import { z } from 'zod';
import { zodToJsonSchema } from 'zod-to-json-schema';
import dotenv from 'dotenv';

import { SessionManager } from './session-manager.js';
import { chunkResponse, formatPaginatedResponse } from './token-utils.js';
import { logger } from './logger.js';

dotenv.config();

const sessionManager = new SessionManager(logger);

const AskSchema = z.object({
  prompt: z.string().describe('Prompt text'),
  sid: z.string().optional().describe('Session ID'),
  ws: z.string().optional().describe('Workspace path'),
  page: z.number().int().min(1).default(1).describe('Page number')
});

const StatusSchema = z.object({
  sid: z.string().optional().describe('Session ID')
});

const server = new Server(
  {
    name: 'gemini-mcp',
    version: '1.0.0',
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

async function handleAsk(args: any): Promise<any> {
  const params = AskSchema.parse(args);
  const sessionId = params.sid || `gemini_${Date.now().toString(36)}`;
  const workspacePath = params.ws || process.cwd();

  try {
    const response = await sessionManager.sendCommand(
      sessionId,
      {
        args: [params.prompt],
        input: params.prompt
      },
      workspacePath
    );

    if (!response.success) {
      return { type: 'text', text: `❌ Gemini Error: ${response.error}` };
    }

    const chunk = chunkResponse(response.text, 18000, params.page);
    const paginatedText = formatPaginatedResponse(chunk, response.text);

    return {
      type: 'text',
      text: `${paginatedText}\n\nSession: ${sessionId}`
    };
  } catch (error: any) {
    return { type: 'text', text: `❌ Error: ${error.message}` };
  }
}

async function handleStatus(_args: any): Promise<any> {
  const sessions = sessionManager.getAllSessions();
  if (sessions.length === 0) return { type: 'text', text: 'No active Gemini sessions.' };

  const list = sessions.map(s => `${s.id} (${s.status}) - ${s.requestCount} requests`).join('\n');
  return { type: 'text', text: `Active Gemini Sessions:\n${list}` };
}

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'gemini_ask',
      description: 'Ask Gemini CLI for help',
      inputSchema: zodToJsonSchema(AskSchema) as any
    },
    {
      name: 'gemini_status',
      description: 'Check Gemini session status',
      inputSchema: zodToJsonSchema(StatusSchema) as any
    }
  ]
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case 'gemini_ask':
        return { content: [await handleAsk(args)] };
      case 'gemini_status':
        return { content: [await handleStatus(args)] };
      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (error: any) {
    return {
      content: [{ type: 'text', text: `❌ Tool ${name} failed: ${error.message}` }]
    };
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  logger.info('Gemini MCP Server is running');
}

process.on('SIGINT', async () => {
  await sessionManager.shutdown();
  process.exit(0);
});

main().catch((error) => {
  logger.error('Unhandled error:', error);
  process.exit(1);
});
