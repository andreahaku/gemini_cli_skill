/**
 * Error categorization and type system for Gemini MCP Server
 */

export enum ErrorCategory {
  GEMINI_CLI = 'gemini_cli',
  SESSION_MANAGEMENT = 'session_management',
  MCP_PROTOCOL = 'mcp_protocol',
  VALIDATION = 'validation',
  RESOURCE = 'resource',
  TIMEOUT = 'timeout',
  AUTHENTICATION = 'authentication',
  SYSTEM = 'system'
}

export enum ErrorSeverity {
  LOW = 'low',
  MEDIUM = 'medium',
  HIGH = 'high',
  CRITICAL = 'critical'
}

export interface ErrorContext {
  sessionId?: string;
  workspaceId?: string;
  workspacePath?: string;
  requestId?: string;
  toolName?: string;
  timestamp: Date;
  [key: string]: any;
}

export interface CategorizedError extends Error {
  category: ErrorCategory;
  severity: ErrorSeverity;
  code: string;
  context: ErrorContext;
  originalError?: Error;
  recoverable: boolean;
  retryAfter?: number;
}

export class GeminiError extends Error implements CategorizedError {
  public readonly category: ErrorCategory;
  public readonly severity: ErrorSeverity;
  public readonly code: string;
  public readonly context: ErrorContext;
  public readonly originalError?: Error;
  public readonly recoverable: boolean;
  public readonly retryAfter?: number;

  constructor(
    message: string,
    category: ErrorCategory,
    severity: ErrorSeverity,
    code: string,
    context: ErrorContext,
    originalError?: Error,
    recoverable: boolean = false,
    retryAfter?: number
  ) {
    super(message);
    this.name = 'GeminiError';
    this.category = category;
    this.severity = severity;
    this.code = code;
    this.context = context;
    this.originalError = originalError;
    this.recoverable = recoverable;
    this.retryAfter = retryAfter;

    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, GeminiError);
    }
  }

  toJSON() {
    return {
      name: this.name,
      message: this.message,
      category: this.category,
      severity: this.severity,
      code: this.code,
      context: this.context,
      recoverable: this.recoverable,
      retryAfter: this.retryAfter,
      stack: this.stack,
      originalError: this.originalError ? {
        name: this.originalError.name,
        message: this.originalError.message,
        stack: this.originalError.stack
      } : undefined
    };
  }
}

export const ERROR_CODES = {
  GEMINI_NOT_FOUND: 'GEMINI_001',
  GEMINI_TIMEOUT: 'GEMINI_002', 
  GEMINI_COMMAND_FAILED: 'GEMINI_003',
  GEMINI_AUTH_FAILED: 'GEMINI_004',
  GEMINI_RATE_LIMITED: 'GEMINI_005',
  
  SESSION_NOT_FOUND: 'SESSION_001',
  SESSION_CREATION_FAILED: 'SESSION_002',
  SESSION_TIMEOUT: 'SESSION_003',
  SESSION_TERMINATED: 'SESSION_004',
  MAX_SESSIONS_EXCEEDED: 'SESSION_005',
  
  MCP_INVALID_REQUEST: 'MCP_001',
  MCP_TOOL_NOT_FOUND: 'MCP_002',
  MCP_RESPONSE_TOO_LARGE: 'MCP_003',
  
  INVALID_PARAMETERS: 'VALIDATION_001',
  MISSING_REQUIRED_FIELD: 'VALIDATION_002',
  
  FILE_NOT_FOUND: 'RESOURCE_001',
  PERMISSION_DENIED: 'RESOURCE_002',
  
  UNEXPECTED_ERROR: 'SYSTEM_001',
  INITIALIZATION_FAILED: 'SYSTEM_002'
} as const;

export type ErrorCode = typeof ERROR_CODES[keyof typeof ERROR_CODES];
