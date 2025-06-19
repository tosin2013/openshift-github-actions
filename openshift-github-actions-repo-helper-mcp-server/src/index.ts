#!/usr/bin/env node

/**
 * OpenShift GitHub Actions Repository Helper MCP Server
 * 
 * A comprehensive Repository Helper MCP Server that provides:
 * - Development Support (LLD, API docs, Architecture)
 * - Usage & Support following Diátaxis framework (Tutorials, How-tos, References, Explanations)
 * - QA & Testing (Test plans, Spec-by-example, Quality workflows)
 * - Red Hat AI Services integration
 * 
 * Based on Detection & Enterprise Setup methodology for the openshift-github-actions repository.
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
  ListPromptsRequestSchema,
  GetPromptRequestSchema
} from '@modelcontextprotocol/sdk/types.js';

import { OpenshiftGithubActionsRepoHelperMcpServer } from './server/OpenshiftGithubActionsRepoHelperMcpServer.js';
import { logger } from './utils/logger.js';

/**
 * Main entry point for the OpenShift GitHub Actions Repository Helper MCP Server
 */
async function main(): Promise<void> {
  try {
    logger.info('Starting OpenShift GitHub Actions Repository Helper MCP Server...');
    
    // Initialize the MCP server
    const server = new Server(
      {
        name: 'openshift-github-actions-repo-helper',
        version: '1.0.0',
      },
      {
        capabilities: {
          tools: {},
          resources: {},
          prompts: {},
        },
      }
    );

    // Initialize the repository helper server
    const repoHelper = new OpenshiftGithubActionsRepoHelperMcpServer();
    await repoHelper.initialize();

    // Register tool handlers
    server.setRequestHandler(ListToolsRequestSchema, async () => {
      logger.debug('Listing available tools');
      return {
        tools: await repoHelper.listTools(),
      };
    });

    server.setRequestHandler(CallToolRequestSchema, async (request) => {
      logger.debug(`Calling tool: ${request.params.name}`);
      return await repoHelper.callTool(request.params.name, request.params.arguments || {});
    });

    // Register resource handlers
    server.setRequestHandler(ListResourcesRequestSchema, async () => {
      logger.debug('Listing available resources');
      return {
        resources: await repoHelper.listResources(),
      };
    });

    server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
      logger.debug(`Reading resource: ${request.params.uri}`);
      return await repoHelper.readResource(request.params.uri);
    });

    // Register prompt handlers
    server.setRequestHandler(ListPromptsRequestSchema, async () => {
      logger.debug('Listing available prompts');
      return {
        prompts: await repoHelper.listPrompts(),
      };
    });

    server.setRequestHandler(GetPromptRequestSchema, async (request) => {
      logger.debug(`Getting prompt: ${request.params.name}`);
      return await repoHelper.getPrompt(request.params.name, request.params.arguments || {});
    });

    // Start the server
    const transport = new StdioServerTransport();
    await server.connect(transport);
    
    logger.info('OpenShift GitHub Actions Repository Helper MCP Server started successfully');
    logger.info('Server capabilities: Development Support, Diátaxis Documentation, QA & Testing, Red Hat AI Integration');
    
  } catch (error) {
    logger.error('Failed to start OpenShift GitHub Actions Repository Helper MCP Server:', error);
    process.exit(1);
  }
}

// Handle graceful shutdown
process.on('SIGINT', () => {
  logger.info('Received SIGINT, shutting down gracefully...');
  process.exit(0);
});

process.on('SIGTERM', () => {
  logger.info('Received SIGTERM, shutting down gracefully...');
  process.exit(0);
});

// Start the server
main().catch((error) => {
  logger.error('Unhandled error in main:', error);
  process.exit(1);
});
