import { exec } from 'child_process';
import { promisify } from 'util';
import { EventEmitter } from 'events';
import { StructuredLogger } from './logger.js';
import { categorizeError, createErrorContext } from './error-utils.js';
import { ErrorCategory } from './error-types.js';

const execAsync = promisify(exec);

export interface GeminiCommand {
  args: string[];
  input?: string;
  timeout?: number;
  signal?: AbortSignal;
}

export interface GeminiResponse {
  text: string;
  success: boolean;
  error?: string;
  exitCode?: number;
}

export class GeminiProcess extends EventEmitter {
  private sessionId: string;
  private workingDirectory: string;
  private logger: StructuredLogger;
  private isReady = false;

  constructor(sessionId: string, workingDirectory = process.cwd(), logger: StructuredLogger) {
    super();
    this.sessionId = sessionId;
    this.workingDirectory = workingDirectory;
    this.logger = logger;
  }

  async start(): Promise<void> {
    this.isReady = true;
    this.logger.info('Gemini session ready', { sessionId: this.sessionId });
  }

  async send(command: GeminiCommand): Promise<GeminiResponse> {
    const requestId = `req_${Date.now().toString(36)}`;
    
    try {
      const prompt = command.args[command.args.length - 1];
      const escapedPrompt = `'${prompt.replace(/'/g, "'\\''")}'`;
      
      // Gemini CLI command: gemini -p "prompt"
      const fullCommand = `gemini -p ${escapedPrompt} --output-format text`;

      this.logger.debug('Executing Gemini command', { sessionId: this.sessionId, command: fullCommand });

      const { stdout } = await execAsync(fullCommand, {
        cwd: this.workingDirectory,
        maxBuffer: 10 * 1024 * 1024,
        timeout: command.timeout || 120000
      });

      return {
        text: stdout.trim(),
        success: true,
        exitCode: 0
      };

    } catch (error: any) {
      const context = createErrorContext(this.sessionId, undefined, this.workingDirectory, requestId);
      const categorized = categorizeError(error, context, ErrorCategory.GEMINI_CLI);
      this.logger.logError(categorized);

      return {
        text: '',
        success: false,
        error: categorized.message,
        exitCode: error.code || 1
      };
    }
  }

  async kill(): Promise<void> {
    this.isReady = false;
  }

  isHealthy(): boolean {
    return this.isReady;
  }
}
