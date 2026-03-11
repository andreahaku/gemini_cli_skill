import { GeminiProcess, GeminiCommand, GeminiResponse } from './gemini-process.js';
import { StructuredLogger } from './logger.js';

export interface SessionInfo {
  id: string;
  workspacePath: string;
  created: Date;
  lastActive: Date;
  status: 'ready' | 'error';
  requestCount: number;
}

export class SessionManager {
  private sessions: Map<string, GeminiProcess> = new Map();
  private sessionInfo: Map<string, SessionInfo> = new Map();
  private logger: StructuredLogger;

  constructor(logger: StructuredLogger) {
    this.logger = logger;
  }

  async getOrCreateSession(sessionId: string, workspacePath: string = process.cwd()): Promise<GeminiProcess> {
    let process = this.sessions.get(sessionId);
    
    if (process && process.isHealthy()) {
      const info = this.sessionInfo.get(sessionId);
      if (info) {
        info.lastActive = new Date();
        info.requestCount++;
      }
      return process;
    }

    if (process) {
      await this.destroySession(sessionId);
    }

    return await this.createSession(sessionId, workspacePath);
  }

  async createSession(sessionId: string, workspacePath: string): Promise<GeminiProcess> {
    const process = new GeminiProcess(sessionId, workspacePath, this.logger);

    const info: SessionInfo = {
      id: sessionId,
      workspacePath,
      created: new Date(),
      lastActive: new Date(),
      status: 'ready',
      requestCount: 0
    };

    this.sessionInfo.set(sessionId, info);
    this.sessions.set(sessionId, process);

    await process.start();
    return process;
  }

  async destroySession(sessionId: string): Promise<void> {
    const process = this.sessions.get(sessionId);
    if (process) {
      await process.kill();
      this.sessions.delete(sessionId);
      this.sessionInfo.delete(sessionId);
    }
  }

  async sendCommand(
    sessionId: string, 
    command: GeminiCommand,
    workspacePath: string = process.cwd()
  ): Promise<GeminiResponse> {
    const process = await this.getOrCreateSession(sessionId, workspacePath);
    return process.send(command);
  }

  async shutdown(): Promise<void> {
    for (const sessionId of this.sessions.keys()) {
      await this.destroySession(sessionId);
    }
  }

  getAllSessions(): SessionInfo[] {
    return Array.from(this.sessionInfo.values());
  }
}
