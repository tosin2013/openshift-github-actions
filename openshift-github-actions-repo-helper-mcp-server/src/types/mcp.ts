/**
 * MCP Schema Types
 * 
 * Local type definitions for MCP schemas to avoid import issues
 */

export interface Tool {
  name: string;
  description: string;
  inputSchema: {
    type: string;
    properties?: Record<string, any>;
    required?: string[];
  };
}

export interface Resource {
  uri: string;
  name: string;
  description: string;
  mimeType: string;
}

export interface Prompt {
  name: string;
  description: string;
  arguments?: Array<{
    name: string;
    description: string;
    required?: boolean;
  }>;
}
