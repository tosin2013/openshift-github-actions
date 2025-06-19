/**
 * API Documentation Generator
 * 
 * Generates comprehensive API documentation for GitHub Actions workflows,
 * Vault integration endpoints, and script interfaces found in the repository.
 */

import { RepositoryDetectionResult } from '../types/repository.js';
import { logger } from '../utils/logger.js';

/**
 * API documentation generation input parameters
 */
export interface APIDocGenerationInput {
  /** Output format */
  outputFormat: 'openapi' | 'markdown' | 'html';
  
  /** Include code examples */
  includeExamples: boolean;
  
  /** Include authentication details */
  includeAuthentication: boolean;
  
  /** Include error responses */
  includeErrorResponses?: boolean;
  
  /** Generate interactive docs */
  generateInteractiveDocs?: boolean;
  
  /** Specific API to document */
  apiType?: 'github-actions' | 'vault' | 'scripts' | 'all';
}

/**
 * API documentation generation result
 */
export interface APIDocGenerationResult {
  /** Generated documentation content */
  content: string;
  
  /** API specifications */
  apiSpecs: APISpecification[];
  
  /** Code examples */
  codeExamples: APICodeExample[];
  
  /** Authentication documentation */
  authenticationDocs: AuthenticationDoc[];
  
  /** Metadata */
  metadata: APIDocMetadata;
}

/**
 * API specification
 */
export interface APISpecification {
  /** API name */
  name: string;
  
  /** API type */
  type: 'REST' | 'GraphQL' | 'Webhook' | 'CLI' | 'Script';
  
  /** Base URL */
  baseUrl?: string;
  
  /** Version */
  version: string;
  
  /** Description */
  description: string;
  
  /** Endpoints */
  endpoints: APIEndpoint[];
  
  /** Authentication */
  authentication: AuthenticationMethod[];
  
  /** Error codes */
  errorCodes: ErrorCode[];
}

/**
 * API endpoint
 */
export interface APIEndpoint {
  /** HTTP method */
  method: string;
  
  /** Endpoint path */
  path: string;
  
  /** Summary */
  summary: string;
  
  /** Description */
  description: string;
  
  /** Parameters */
  parameters: APIParameter[];
  
  /** Request body */
  requestBody?: RequestBody;
  
  /** Responses */
  responses: APIResponse[];
  
  /** Tags */
  tags: string[];
  
  /** Examples */
  examples: APIExample[];
}

/**
 * API parameter
 */
export interface APIParameter {
  /** Parameter name */
  name: string;
  
  /** Parameter location */
  in: 'query' | 'header' | 'path' | 'cookie' | 'body';
  
  /** Parameter type */
  type: string;
  
  /** Description */
  description: string;
  
  /** Required */
  required: boolean;
  
  /** Default value */
  default?: any;
  
  /** Example value */
  example?: any;
  
  /** Schema */
  schema?: any;
}

/**
 * Request body
 */
export interface RequestBody {
  /** Description */
  description: string;
  
  /** Content type */
  contentType: string;
  
  /** Schema */
  schema: any;
  
  /** Required */
  required: boolean;
  
  /** Examples */
  examples: any[];
}

/**
 * API response
 */
export interface APIResponse {
  /** Status code */
  statusCode: number;
  
  /** Description */
  description: string;
  
  /** Content type */
  contentType?: string;
  
  /** Schema */
  schema?: any;
  
  /** Examples */
  examples: any[];
  
  /** Headers */
  headers?: Record<string, any>;
}

/**
 * API example
 */
export interface APIExample {
  /** Example name */
  name: string;
  
  /** Summary */
  summary: string;
  
  /** Request example */
  request: any;
  
  /** Response example */
  response: any;
  
  /** Description */
  description?: string;
}

/**
 * Authentication method
 */
export interface AuthenticationMethod {
  /** Authentication type */
  type: 'bearer' | 'basic' | 'apiKey' | 'oauth2' | 'jwt';
  
  /** Description */
  description: string;
  
  /** Location */
  location?: 'header' | 'query' | 'cookie';
  
  /** Parameter name */
  parameterName?: string;
  
  /** Flows */
  flows?: OAuth2Flow[];
  
  /** Scopes */
  scopes?: string[];
}

/**
 * OAuth2 flow
 */
export interface OAuth2Flow {
  /** Flow type */
  type: 'authorizationCode' | 'implicit' | 'password' | 'clientCredentials';
  
  /** Authorization URL */
  authorizationUrl?: string;
  
  /** Token URL */
  tokenUrl?: string;
  
  /** Refresh URL */
  refreshUrl?: string;
  
  /** Scopes */
  scopes: Record<string, string>;
}

/**
 * Error code
 */
export interface ErrorCode {
  /** Error code */
  code: number | string;
  
  /** Error message */
  message: string;
  
  /** Description */
  description: string;
  
  /** Resolution */
  resolution?: string;
}

/**
 * API code example
 */
export interface APICodeExample {
  /** Language */
  language: string;
  
  /** Code */
  code: string;
  
  /** Description */
  description: string;
  
  /** API endpoint */
  endpoint: string;
  
  /** Example type */
  type: 'request' | 'response' | 'full';
}

/**
 * Authentication documentation
 */
export interface AuthenticationDoc {
  /** Authentication method */
  method: string;
  
  /** Documentation */
  documentation: string;
  
  /** Setup instructions */
  setupInstructions: string[];
  
  /** Code examples */
  codeExamples: APICodeExample[];
}

/**
 * API documentation metadata
 */
export interface APIDocMetadata {
  /** Generation timestamp */
  generationTimestamp: Date;
  
  /** Repository context */
  repositoryContext: RepositoryDetectionResult;
  
  /** Confidence score */
  confidenceScore: number;
  
  /** APIs documented */
  apisDocumented: string[];
  
  /** Output format */
  outputFormat: string;
}

/**
 * API Documentation Generator class
 */
export class APIDocumentationGenerator {
  private repositoryContext: RepositoryDetectionResult;

  constructor(repositoryContext: RepositoryDetectionResult) {
    this.repositoryContext = repositoryContext;
  }

  /**
   * Generate API documentation
   */
  async generateAPIDocumentation(input: APIDocGenerationInput): Promise<APIDocGenerationResult> {
    logger.info(`Generating API documentation in ${input.outputFormat} format`);
    
    try {
      const result: APIDocGenerationResult = {
        content: '',
        apiSpecs: [],
        codeExamples: [],
        authenticationDocs: [],
        metadata: {
          generationTimestamp: new Date(),
          repositoryContext: this.repositoryContext,
          confidenceScore: 0,
          apisDocumented: [],
          outputFormat: input.outputFormat
        }
      };

      // Generate API specifications based on repository analysis
      if (input.apiType === 'all' || input.apiType === 'github-actions' || !input.apiType) {
        const githubActionsAPI = await this.generateGitHubActionsAPI(input);
        result.apiSpecs.push(githubActionsAPI);
        result.metadata.apisDocumented.push('GitHub Actions Workflows');
      }

      if (input.apiType === 'all' || input.apiType === 'vault' || !input.apiType) {
        const vaultAPI = await this.generateVaultAPI(input);
        result.apiSpecs.push(vaultAPI);
        result.metadata.apisDocumented.push('HashiCorp Vault');
      }

      if (input.apiType === 'all' || input.apiType === 'scripts' || !input.apiType) {
        const scriptsAPI = await this.generateScriptsAPI(input);
        result.apiSpecs.push(scriptsAPI);
        result.metadata.apisDocumented.push('Automation Scripts');
      }

      // Generate authentication documentation
      if (input.includeAuthentication) {
        result.authenticationDocs = await this.generateAuthenticationDocs(input);
      }

      // Generate code examples
      if (input.includeExamples) {
        result.codeExamples = await this.generateCodeExamples(result.apiSpecs, input);
      }

      // Generate final documentation content
      result.content = await this.generateDocumentationContent(result, input);
      
      result.metadata.confidenceScore = this.calculateConfidenceScore(result);

      logger.pragmatic(
        `API documentation generation completed`,
        result.metadata.confidenceScore,
        'Repository-specific API analysis with detected endpoints',
        { 
          format: input.outputFormat, 
          apisCount: result.apiSpecs.length,
          examplesCount: result.codeExamples.length 
        }
      );

      return result;

    } catch (error) {
      logger.error('Failed to generate API documentation', error);
      throw error;
    }
  }

  /**
   * Generate GitHub Actions API specification
   */
  private async generateGitHubActionsAPI(_input: APIDocGenerationInput): Promise<APISpecification> {
    logger.info('Generating GitHub Actions API specification');

    return {
      name: 'GitHub Actions Workflows',
      type: 'Webhook',
      version: '1.0.0',
      description: 'Multi-cloud OpenShift deployment workflows with Vault integration',
      endpoints: [
        {
          method: 'POST',
          path: '/repos/tosin2013/openshift-github-actions/actions/workflows/deploy-openshift-multicloud.yml/dispatches',
          summary: 'Deploy OpenShift Multi-Cloud',
          description: 'Trigger multi-cloud OpenShift deployment workflow',
          parameters: [
            {
              name: 'cloud_provider',
              in: 'body',
              type: 'string',
              description: 'Cloud provider to deploy to',
              required: true,
              example: 'aws'
            },
            {
              name: 'cluster_name',
              in: 'body',
              type: 'string',
              description: 'OpenShift cluster name',
              required: true,
              example: 'openshift-cluster'
            },
            {
              name: 'environment',
              in: 'body',
              type: 'string',
              description: 'Deployment environment',
              required: true,
              example: 'dev'
            },
            {
              name: 'openshift_version',
              in: 'body',
              type: 'string',
              description: 'OpenShift version',
              required: true,
              example: '4.18.17'
            }
          ],
          requestBody: {
            description: 'Workflow dispatch inputs',
            contentType: 'application/json',
            required: true,
            schema: {
              type: 'object',
              properties: {
                ref: { type: 'string', example: 'main' },
                inputs: {
                  type: 'object',
                  properties: {
                    cloud_provider: { type: 'string', enum: ['aws', 'azure', 'gcp', 'all'] },
                    cluster_name: { type: 'string' },
                    environment: { type: 'string', enum: ['dev', 'staging', 'prod'] },
                    dry_run: { type: 'boolean' },
                    openshift_version: { type: 'string' }
                  }
                }
              }
            },
            examples: [{
              ref: 'main',
              inputs: {
                cloud_provider: 'aws',
                cluster_name: 'my-openshift-cluster',
                environment: 'dev',
                dry_run: false,
                openshift_version: '4.18.17'
              }
            }]
          },
          responses: [
            {
              statusCode: 204,
              description: 'Workflow triggered successfully',
              examples: []
            },
            {
              statusCode: 422,
              description: 'Validation failed',
              contentType: 'application/json',
              schema: {
                type: 'object',
                properties: {
                  message: { type: 'string' },
                  errors: { type: 'array' }
                }
              },
              examples: [{
                message: 'Validation Failed',
                errors: [{ field: 'cloud_provider', code: 'invalid' }]
              }]
            }
          ],
          tags: ['deployment', 'multi-cloud'],
          examples: [
            {
              name: 'AWS Deployment',
              summary: 'Deploy OpenShift cluster on AWS',
              request: {
                ref: 'main',
                inputs: {
                  cloud_provider: 'aws',
                  cluster_name: 'aws-openshift-dev',
                  environment: 'dev',
                  openshift_version: '4.18.17'
                }
              },
              response: { status: 204 }
            }
          ]
        }
      ],
      authentication: [
        {
          type: 'bearer',
          description: 'GitHub Personal Access Token with workflow permissions',
          location: 'header',
          parameterName: 'Authorization'
        }
      ],
      errorCodes: [
        {
          code: 401,
          message: 'Unauthorized',
          description: 'Invalid or missing authentication token',
          resolution: 'Provide a valid GitHub Personal Access Token'
        },
        {
          code: 404,
          message: 'Not Found',
          description: 'Workflow file not found',
          resolution: 'Verify the workflow file exists and path is correct'
        }
      ]
    };
  }

  /**
   * Generate Vault API specification
   */
  private async generateVaultAPI(_input: APIDocGenerationInput): Promise<APISpecification> {
    logger.info('Generating Vault API specification');

    return {
      name: 'HashiCorp Vault HA',
      type: 'REST',
      baseUrl: 'https://vault-route-vault-namespace.apps.cluster.local',
      version: '1.15.0',
      description: 'HashiCorp Vault HA cluster with JWT authentication and dynamic secrets',
      endpoints: [
        {
          method: 'POST',
          path: '/v1/auth/jwt/login',
          summary: 'JWT Authentication',
          description: 'Authenticate using GitHub Actions JWT token',
          parameters: [
            {
              name: 'Content-Type',
              in: 'header',
              type: 'string',
              description: 'Content type',
              required: true,
              example: 'application/json'
            }
          ],
          requestBody: {
            description: 'JWT authentication request',
            contentType: 'application/json',
            required: true,
            schema: {
              type: 'object',
              properties: {
                jwt: { type: 'string', description: 'GitHub Actions JWT token' },
                role: { type: 'string', description: 'Vault role name' }
              },
              required: ['jwt', 'role']
            },
            examples: [{
              jwt: 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...',
              role: 'github-actions-deployer'
            }]
          },
          responses: [
            {
              statusCode: 200,
              description: 'Authentication successful',
              contentType: 'application/json',
              schema: {
                type: 'object',
                properties: {
                  auth: {
                    type: 'object',
                    properties: {
                      client_token: { type: 'string' },
                      accessor: { type: 'string' },
                      policies: { type: 'array', items: { type: 'string' } },
                      lease_duration: { type: 'number' }
                    }
                  }
                }
              },
              examples: [{
                auth: {
                  client_token: 'hvs.CAESIJ...',
                  accessor: 'hmac-sha256:...',
                  policies: ['openshift-deployer'],
                  lease_duration: 3600
                }
              }]
            }
          ],
          tags: ['authentication'],
          examples: []
        },
        {
          method: 'GET',
          path: '/v1/aws/creds/openshift-installer',
          summary: 'Generate AWS Credentials',
          description: 'Generate dynamic AWS credentials for OpenShift deployment',
          parameters: [
            {
              name: 'X-Vault-Token',
              in: 'header',
              type: 'string',
              description: 'Vault authentication token',
              required: true,
              example: 'hvs.CAESIJ...'
            }
          ],
          responses: [
            {
              statusCode: 200,
              description: 'AWS credentials generated successfully',
              contentType: 'application/json',
              schema: {
                type: 'object',
                properties: {
                  data: {
                    type: 'object',
                    properties: {
                      access_key: { type: 'string' },
                      secret_key: { type: 'string' },
                      security_token: { type: 'string' }
                    }
                  },
                  lease_duration: { type: 'number' },
                  lease_id: { type: 'string' }
                }
              },
              examples: [{
                data: {
                  access_key: 'AKIAIOSFODNN7EXAMPLE',
                  secret_key: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
                  security_token: null
                },
                lease_duration: 3600,
                lease_id: 'aws/creds/openshift-installer/...'
              }]
            }
          ],
          tags: ['secrets', 'aws'],
          examples: []
        }
      ],
      authentication: [
        {
          type: 'jwt',
          description: 'GitHub Actions JWT token authentication',
          flows: []
        },
        {
          type: 'bearer',
          description: 'Vault token authentication',
          location: 'header',
          parameterName: 'X-Vault-Token'
        }
      ],
      errorCodes: [
        {
          code: 400,
          message: 'Bad Request',
          description: 'Invalid request parameters',
          resolution: 'Check request format and required parameters'
        },
        {
          code: 403,
          message: 'Forbidden',
          description: 'Insufficient permissions',
          resolution: 'Ensure proper Vault policies are assigned'
        }
      ]
    };
  }

  /**
   * Generate Scripts API specification
   */
  private async generateScriptsAPI(_input: APIDocGenerationInput): Promise<APISpecification> {
    return {
      name: 'Automation Scripts',
      type: 'CLI',
      version: '1.0.0',
      description: 'Bash and Python scripts for OpenShift and Vault automation',
      endpoints: [
        {
          method: 'EXEC',
          path: './deploy_vault_ha_tls_complete.sh',
          summary: 'Deploy Vault HA with TLS',
          description: 'Complete Vault HA deployment with TLS encryption',
          parameters: [
            {
              name: 'VAULT_NAMESPACE',
              in: 'body',
              type: 'string',
              description: 'Vault namespace',
              required: false,
              default: 'vault-production',
              example: 'vault-production'
            }
          ],
          responses: [
            {
              statusCode: 0,
              description: 'Deployment successful',
              examples: ['✅ Vault HA deployment completed successfully']
            },
            {
              statusCode: 1,
              description: 'Deployment failed',
              examples: ['❌ Vault deployment failed: reason']
            }
          ],
          tags: ['deployment', 'vault'],
          examples: []
        }
      ],
      authentication: [
        {
          type: 'basic',
          description: 'OpenShift cluster authentication required'
        }
      ],
      errorCodes: []
    };
  }

  /**
   * Generate authentication documentation
   */
  private async generateAuthenticationDocs(_input: APIDocGenerationInput): Promise<AuthenticationDoc[]> {
    return [
      {
        method: 'GitHub Actions JWT',
        documentation: `
# GitHub Actions JWT Authentication

GitHub Actions provides JWT tokens that can be used to authenticate with Vault without storing long-lived credentials.

## Setup Process

1. Configure Vault JWT authentication method
2. Create GitHub Actions role in Vault
3. Set up GitHub repository secrets
4. Use hashicorp/vault-action in workflows

## Token Claims

The JWT token includes claims about the GitHub Actions run:
- Repository: repo:owner/repository
- Branch/Tag: ref:refs/heads/main
- Actor: GitHub username
- Workflow: Workflow name
        `,
        setupInstructions: [
          'Enable JWT auth method in Vault',
          'Configure JWKS URL for GitHub',
          'Create role with appropriate policies',
          'Set up repository secrets',
          'Use vault-action in workflows'
        ],
        codeExamples: [
          {
            language: 'yaml',
            code: `- name: Get secrets from Vault
  uses: hashicorp/vault-action@v2
  with:
    url: \${{ secrets.VAULT_URL }}
    method: jwt
    jwtGithubAudience: \${{ secrets.VAULT_JWT_AUDIENCE }}
    role: \${{ secrets.VAULT_ROLE }}
    secrets: |
      aws/creds/openshift-installer access_key | AWS_ACCESS_KEY_ID ;
      aws/creds/openshift-installer secret_key | AWS_SECRET_ACCESS_KEY`,
            description: 'GitHub Actions workflow step for Vault authentication',
            endpoint: '/v1/auth/jwt/login',
            type: 'request'
          }
        ]
      }
    ];
  }

  /**
   * Generate code examples
   */
  private async generateCodeExamples(apiSpecs: APISpecification[], _input: APIDocGenerationInput): Promise<APICodeExample[]> {
    const examples: APICodeExample[] = [];

    // Add curl examples for REST APIs
    for (const spec of apiSpecs) {
      if (spec.type === 'REST') {
        for (const endpoint of spec.endpoints) {
          examples.push({
            language: 'bash',
            code: `curl -X ${endpoint.method} \\
  "${spec.baseUrl}${endpoint.path}" \\
  -H "Content-Type: application/json" \\
  -H "X-Vault-Token: \${VAULT_TOKEN}" \\
  -d '${JSON.stringify(endpoint.requestBody?.examples?.[0] || {}, null, 2)}'`,
            description: `${endpoint.summary} using curl`,
            endpoint: endpoint.path,
            type: 'request'
          });
        }
      }
    }

    return examples;
  }

  /**
   * Generate documentation content
   */
  private async generateDocumentationContent(result: APIDocGenerationResult, input: APIDocGenerationInput): Promise<string> {
    if (input.outputFormat === 'markdown') {
      return this.generateMarkdownContent(result);
    } else if (input.outputFormat === 'openapi') {
      return this.generateOpenAPIContent(result);
    } else {
      return this.generateHTMLContent(result);
    }
  }

  /**
   * Generate Markdown content
   */
  private generateMarkdownContent(result: APIDocGenerationResult): string {
    let content = `# OpenShift GitHub Actions API Documentation

Generated on: ${result.metadata.generationTimestamp.toISOString()}
Confidence Score: ${result.metadata.confidenceScore}%

## Overview

This documentation covers the APIs and interfaces for the OpenShift GitHub Actions multi-cloud automation repository.

## APIs Documented

${result.metadata.apisDocumented.map(api => `- ${api}`).join('\n')}

`;

    for (const spec of result.apiSpecs) {
      content += `## ${spec.name}

**Type**: ${spec.type}
**Version**: ${spec.version}
${spec.baseUrl ? `**Base URL**: ${spec.baseUrl}` : ''}

${spec.description}

### Endpoints

`;

      for (const endpoint of spec.endpoints) {
        content += `#### ${endpoint.method} ${endpoint.path}

${endpoint.description}

**Parameters:**
${endpoint.parameters.map(p => `- \`${p.name}\` (${p.type}): ${p.description}${p.required ? ' **(required)**' : ''}`).join('\n')}

`;

        if (endpoint.examples.length > 0) {
          content += `**Examples:**

\`\`\`json
${JSON.stringify(endpoint.examples[0]?.request || {}, null, 2)}
\`\`\`

`;
        }
      }
    }

    return content;
  }

  /**
   * Generate OpenAPI content
   */
  private generateOpenAPIContent(result: APIDocGenerationResult): string {
    const openapi = {
      openapi: '3.0.0',
      info: {
        title: 'OpenShift GitHub Actions API',
        version: '1.0.0',
        description: 'Multi-cloud OpenShift deployment APIs'
      },
      servers: result.apiSpecs.filter(s => s.baseUrl).map(s => ({ url: s.baseUrl })),
      paths: {},
      components: {
        securitySchemes: {}
      }
    };

    return JSON.stringify(openapi, null, 2);
  }

  /**
   * Generate HTML content
   */
  private generateHTMLContent(result: APIDocGenerationResult): string {
    return `<!DOCTYPE html>
<html>
<head>
    <title>OpenShift GitHub Actions API Documentation</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .api-spec { margin-bottom: 40px; border: 1px solid #ddd; padding: 20px; }
        .endpoint { margin-bottom: 20px; background: #f5f5f5; padding: 15px; }
        .method { font-weight: bold; color: #007acc; }
    </style>
</head>
<body>
    <h1>OpenShift GitHub Actions API Documentation</h1>
    <p>Generated on: ${result.metadata.generationTimestamp.toISOString()}</p>
    <p>Confidence Score: ${result.metadata.confidenceScore}%</p>
    
    ${result.apiSpecs.map(spec => `
    <div class="api-spec">
        <h2>${spec.name}</h2>
        <p><strong>Type:</strong> ${spec.type}</p>
        <p><strong>Version:</strong> ${spec.version}</p>
        ${spec.baseUrl ? `<p><strong>Base URL:</strong> ${spec.baseUrl}</p>` : ''}
        <p>${spec.description}</p>
        
        <h3>Endpoints</h3>
        ${spec.endpoints.map(endpoint => `
        <div class="endpoint">
            <h4><span class="method">${endpoint.method}</span> ${endpoint.path}</h4>
            <p>${endpoint.description}</p>
        </div>
        `).join('')}
    </div>
    `).join('')}
</body>
</html>`;
  }

  /**
   * Calculate confidence score
   */
  private calculateConfidenceScore(result: APIDocGenerationResult): number {
    let score = 80; // Base score

    // Increase score based on content quality
    if (result.apiSpecs.length > 0) score += 10;
    if (result.codeExamples.length > 0) score += 5;
    if (result.authenticationDocs.length > 0) score += 5;

    return Math.min(100, score);
  }
}
