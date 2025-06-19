/**
 * Logger utility for OpenShift GitHub Actions Repository Helper MCP Server
 * 
 * Provides structured logging with different levels and methodological pragmatism support
 */

export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
}

export interface LogEntry {
  timestamp: string;
  level: string;
  message: string;
  data?: any;
  confidence?: number;
  verification?: string;
}

class Logger {
  private logLevel: LogLevel;

  constructor(logLevel: LogLevel = LogLevel.INFO) {
    this.logLevel = logLevel;
  }

  private formatMessage(level: string, message: string, data?: any, confidence?: number, verification?: string): LogEntry {
    const entry: LogEntry = {
      timestamp: new Date().toISOString(),
      level,
      message,
    };

    if (data !== undefined) {
      entry.data = data;
    }

    if (confidence !== undefined) {
      entry.confidence = confidence;
    }

    if (verification) {
      entry.verification = verification;
    }

    return entry;
  }

  private log(level: LogLevel, levelName: string, message: string, data?: any, confidence?: number, verification?: string): void {
    if (level >= this.logLevel) {
      const entry = this.formatMessage(levelName, message, data, confidence, verification);
      
      // Output to stderr for MCP server compatibility
      console.error(JSON.stringify(entry));
    }
  }

  debug(message: string, data?: any, confidence?: number): void {
    this.log(LogLevel.DEBUG, 'DEBUG', message, data, confidence);
  }

  info(message: string, data?: any, confidence?: number): void {
    this.log(LogLevel.INFO, 'INFO', message, data, confidence);
  }

  warn(message: string, data?: any, confidence?: number): void {
    this.log(LogLevel.WARN, 'WARN', message, data, confidence);
  }

  error(message: string, error?: any, confidence?: number): void {
    this.log(LogLevel.ERROR, 'ERROR', message, error, confidence);
  }

  /**
   * Log with methodological pragmatism context
   */
  pragmatic(message: string, confidence: number, verification: string, data?: any): void {
    this.log(LogLevel.INFO, 'PRAGMATIC', message, data, confidence, verification);
  }

  /**
   * Log repository-specific analysis
   */
  repoAnalysis(message: string, confidence: number, detectedTech: string[], data?: any): void {
    this.log(LogLevel.INFO, 'REPO_ANALYSIS', message, { detectedTech, ...data }, confidence);
  }

  /**
   * Log Diátaxis framework operations
   */
  diataxis(docType: 'tutorial' | 'howto' | 'reference' | 'explanation', message: string, confidence: number, data?: any): void {
    this.log(LogLevel.INFO, 'DIATAXIS', message, { docType, ...data }, confidence);
  }

  /**
   * Log Red Hat AI Services integration
   */
  redhatAI(message: string, confidence: number, model: string, data?: any): void {
    this.log(LogLevel.INFO, 'REDHAT_AI', message, { model, ...data }, confidence);
  }

  setLogLevel(level: LogLevel): void {
    this.logLevel = level;
  }
}

// Export singleton logger instance
export const logger = new Logger(
  process.env['LOG_LEVEL'] ? parseInt(process.env['LOG_LEVEL']) : LogLevel.INFO
);
