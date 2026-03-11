/**
 * Enhanced structured logging system for Gemini MCP Server
 */

import winston from 'winston';
import { ErrorContext, CategorizedError } from './error-types.js';

export interface LogContext extends ErrorContext {
  duration?: number;
  success?: boolean;
  retryCount?: number;
  metadata?: Record<string, any>;
}

export class StructuredLogger {
  private logger: winston.Logger;

  constructor(level: string = 'info') {
    this.logger = winston.createLogger({
      level,
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
      ),
      transports: [
        new winston.transports.Console({
          format: winston.format.combine(
            winston.format.colorize(),
            winston.format.simple()
          )
        })
      ]
    });
  }

  logWithContext(level: string, message: string, context: Partial<LogContext> = {}) {
    this.logger.log(level, message, context);
  }

  logError(error: Error | CategorizedError, context: Partial<LogContext> = {}) {
    this.logger.error(error.message, { ...context, stack: error.stack });
  }

  info(message: string, context: Partial<LogContext> = {}) {
    this.logWithContext('info', message, context);
  }

  warn(message: string, context: Partial<LogContext> = {}) {
    this.logWithContext('warn', message, context);
  }

  error(message: string, context: Partial<LogContext> = {}) {
    this.logWithContext('error', message, context);
  }

  debug(message: string, context: Partial<LogContext> = {}) {
    this.logWithContext('debug', message, context);
  }
}

export const logger = new StructuredLogger(process.env.LOG_LEVEL || 'info');
