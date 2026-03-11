/**
 * Error mapping and categorization utilities for Gemini
 */

import { ErrorCategory, ErrorSeverity, ErrorContext, GeminiError, ERROR_CODES, ErrorCode } from './error-types.js';

export interface ErrorMapping {
  pattern: RegExp | string;
  category: ErrorCategory;
  severity: ErrorSeverity;
  code: ErrorCode;
  recoverable: boolean;
  retryAfter?: number;
}

export const ERROR_MAPPINGS: ErrorMapping[] = [
  {
    pattern: /gemini.*not found|command not found.*gemini/i,
    category: ErrorCategory.GEMINI_CLI,
    severity: ErrorSeverity.CRITICAL,
    code: ERROR_CODES.GEMINI_NOT_FOUND,
    recoverable: false
  },
  {
    pattern: /gemini.*timeout|timed out.*gemini/i,
    category: ErrorCategory.TIMEOUT,
    severity: ErrorSeverity.HIGH,
    code: ERROR_CODES.GEMINI_TIMEOUT,
    recoverable: true,
    retryAfter: 5000
  },
  {
    pattern: /rate.*limit|too many requests/i,
    category: ErrorCategory.GEMINI_CLI,
    severity: ErrorSeverity.MEDIUM,
    code: ERROR_CODES.GEMINI_RATE_LIMITED,
    recoverable: true,
    retryAfter: 60000
  }
];

export function categorizeError(
  error: Error,
  context: ErrorContext,
  fallbackCategory: ErrorCategory = ErrorCategory.SYSTEM
): GeminiError {
  if (error instanceof GeminiError) {
    return error;
  }

  for (const mapping of ERROR_MAPPINGS) {
    if (mapping.pattern instanceof RegExp ? mapping.pattern.test(error.message) : error.message.includes(mapping.pattern)) {
      return new GeminiError(
        error.message,
        mapping.category,
        mapping.severity,
        mapping.code,
        context,
        error,
        mapping.recoverable,
        mapping.retryAfter
      );
    }
  }

  return new GeminiError(
    error.message,
    fallbackCategory,
    ErrorSeverity.HIGH,
    ERROR_CODES.UNEXPECTED_ERROR,
    context,
    error,
    false
  );
}

export function createErrorContext(
  sessionId?: string,
  workspaceId?: string,
  workspacePath?: string,
  requestId?: string,
  toolName?: string,
  additionalContext?: Record<string, any>
): ErrorContext {
  return {
    sessionId,
    workspaceId,
    workspacePath,
    requestId,
    toolName,
    timestamp: new Date(),
    ...additionalContext
  };
}
