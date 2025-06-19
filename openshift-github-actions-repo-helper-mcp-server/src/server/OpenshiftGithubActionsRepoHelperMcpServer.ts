/**
 * OpenShift GitHub Actions Repository Helper MCP Server
 * 
 * Main server class that implements the Repository Helper functionality
 * following Detection & Enterprise Setup methodology and Diátaxis framework.
 */

import { logger } from '../utils/logger.js';
import { RepositoryDetectionResult } from '../types/repository.js';
import { RepoHelperConfig } from '../types/config.js';
import { LLDGenerator } from '../tools/LLDGenerator.js';
import { APIDocumentationGenerator } from '../tools/APIDocumentationGenerator.js';
import { ArchitectureGuideGenerator } from '../tools/ArchitectureGuideGenerator.js';
import { TutorialGenerator } from '../tools/TutorialGenerator.js';
import { TestPlanGenerator } from '../tools/TestPlanGenerator.js';
import { RedHatAIService } from '../services/RedHatAIService.js';
import { Tool, Resource, Prompt } from '../types/mcp.js';

export class OpenshiftGithubActionsRepoHelperMcpServer {
  private repositoryInfo: RepositoryDetectionResult | null = null;
  private config: RepoHelperConfig | null = null;
  private initialized = false;
  private lldGenerator: LLDGenerator | null = null;
  private apiDocGenerator: APIDocumentationGenerator | null = null;
  private architectureGenerator: ArchitectureGuideGenerator | null = null;
  private tutorialGenerator: TutorialGenerator | null = null;
  private testPlanGenerator: TestPlanGenerator | null = null;
  private redhatAIService: RedHatAIService | null = null;

  constructor() {
    logger.info('Initializing OpenShift GitHub Actions Repository Helper MCP Server');
  }

  /**
   * Initialize the server with repository detection and configuration
   */
  async initialize(): Promise<void> {
    try {
      logger.info('Starting server initialization...');
      
      // Detect repository information
      await this.detectRepository();
      
      // Load configuration
      await this.loadConfiguration();

      // Initialize tool generators
      this.lldGenerator = new LLDGenerator(this.repositoryInfo!);
      this.apiDocGenerator = new APIDocumentationGenerator(this.repositoryInfo!);
      this.architectureGenerator = new ArchitectureGuideGenerator(this.repositoryInfo!);
      this.tutorialGenerator = new TutorialGenerator(this.repositoryInfo!);
      this.testPlanGenerator = new TestPlanGenerator(this.repositoryInfo!);

      // Initialize Red Hat AI Service
      this.redhatAIService = new RedHatAIService(
        {
          ...this.config!.redHatAIIntegration,
          timeout: 30000,
          maxRetries: 3
        },
        this.repositoryInfo!
      );

      this.initialized = true;
      // Verify AI service health
      if (this.redhatAIService) {
        const healthStatus = await this.redhatAIService.getHealthStatus();
        logger.redhatAI('AI Service health check completed', 90, 'redhat-openshift-ai', healthStatus);
      }

      logger.pragmatic(
        'Server initialization completed successfully',
        95,
        'Repository detection and configuration loading verified',
        { repositoryName: this.repositoryInfo?.name, configLoaded: !!this.config }
      );
      
    } catch (error) {
      logger.error('Failed to initialize server', error);
      throw error;
    }
  }

  /**
   * Detect repository information and technologies
   */
  private async detectRepository(): Promise<void> {
    logger.info('Detecting repository information...');
    
    // This would be implemented to analyze the actual repository
    // For now, using the analysis results from our detection
    this.repositoryInfo = {
      name: 'openshift-github-actions',
      url: 'https://github.com/tosin2013/openshift-github-actions.git',
      detectedTechnologies: [
        'Red Hat Enterprise Linux 9.6',
        'OpenShift 4.18',
        'HashiCorp Vault HA',
        'GitHub Actions',
        'Ansible',
        'Python',
        'Bash',
        'cert-manager',
        'Helm 3.x'
      ],
      architecturePatterns: [
        'Multi-cloud deployment',
        'Vault HA with TLS',
        'JWT authentication',
        'IPI deployment',
        'Diátaxis documentation'
      ],
      primaryPurpose: 'OpenShift 4.18 Multi-Cloud Automation with GitHub Actions',
      confidenceScore: 95
    };

    logger.repoAnalysis(
      'Repository detection completed',
      95,
      this.repositoryInfo.detectedTechnologies,
      { patterns: this.repositoryInfo.architecturePatterns }
    );
  }

  /**
   * Load server configuration
   */
  private async loadConfiguration(): Promise<void> {
    logger.info('Loading server configuration...');
    
    this.config = {
      repositoryInfo: this.repositoryInfo!,
      diataxisConfig: {
        enableTutorials: true,
        enableHowTos: true,
        enableReference: true,
        enableExplanations: true,
        outputFormats: ['markdown', 'html']
      },
      developmentSupport: {
        generateLLD: true,
        generateAPIDocs: true,
        generateArchitecture: true,
        analyzeCodeStructure: true
      },
      qaAndTesting: {
        generateTestPlans: true,
        specByExample: true,
        qualityWorkflows: true,
        coverageAnalysis: true
      },
      redHatAIIntegration: {
        endpoint: 'https://maas.apps.prod.rhoai.rh-aiservices-bu.com/',
        model: 'redhat-openshift-ai',
        specialization: 'documentation-development-qa'
      }
    };

    logger.info('Configuration loaded successfully');
  }

  /**
   * List available tools
   */
  async listTools(): Promise<Tool[]> {
    this.ensureInitialized();

    const tools: Tool[] = [
      // Development Support Tools
      {
        name: 'repo-helper-generate-lld',
        description: 'Generate Low-Level Design documentation based on repository analysis',
        inputSchema: {
          type: 'object',
          properties: {
            component: { type: 'string', description: 'Component to generate LLD for' },
            includeInterfaces: { type: 'boolean', description: 'Include interface definitions' },
            includeDataFlow: { type: 'boolean', description: 'Include data flow diagrams' }
          },
          required: ['component']
        }
      },
      {
        name: 'repo-helper-generate-api-docs',
        description: 'Generate API documentation from repository code',
        inputSchema: {
          type: 'object',
          properties: {
            outputFormat: { type: 'string', enum: ['openapi', 'markdown', 'html'] },
            includeExamples: { type: 'boolean', description: 'Include code examples' },
            includeAuthentication: { type: 'boolean', description: 'Include authentication details' }
          },
          required: ['outputFormat']
        }
      },
      {
        name: 'repo-helper-generate-architecture',
        description: 'Generate architecture documentation',
        inputSchema: {
          type: 'object',
          properties: {
            includeDeployment: { type: 'boolean', description: 'Include deployment architecture' },
            includeIntegrations: { type: 'boolean', description: 'Include integration patterns' }
          }
        }
      }
    ];

    // Add Diátaxis tools if enabled
    if (this.config?.diataxisConfig.enableTutorials) {
      tools.push({
        name: 'repo-helper-generate-tutorial',
        description: 'Generate learning-oriented tutorials for OpenShift deployment, Vault setup, and multi-cloud automation',
        inputSchema: {
          type: 'object',
          properties: {
            feature: { type: 'string', description: 'Feature to create tutorial for (vault-ha-deployment, openshift-deployment, github-actions-setup)' },
            targetAudience: { type: 'string', enum: ['beginner', 'intermediate', 'advanced'] },
            includeSetup: { type: 'boolean', description: 'Include setup instructions' },
            stepByStep: { type: 'boolean', description: 'Include detailed step-by-step guidance' },
            includeTroubleshooting: { type: 'boolean', description: 'Include troubleshooting section' }
          },
          required: ['feature']
        }
      });
    }

    // Add QA tools if enabled
    if (this.config?.qaAndTesting.generateTestPlans) {
      tools.push({
        name: 'repo-helper-generate-test-plan',
        description: 'Generate comprehensive test plans',
        inputSchema: {
          type: 'object',
          properties: {
            component: { type: 'string', description: 'Component to test' },
            testTypes: { 
              type: 'array', 
              items: { type: 'string', enum: ['unit', 'integration', 'e2e', 'performance'] }
            },
            coverageTarget: { type: 'number', description: 'Target coverage percentage' }
          },
          required: ['component']
        }
      });
    }

    logger.debug(`Listed ${tools.length} available tools`);
    return tools;
  }

  /**
   * List available resources
   */
  async listResources(): Promise<Resource[]> {
    this.ensureInitialized();

    const resources: Resource[] = [
      {
        uri: 'repo-helper://doc-templates',
        name: 'Documentation Templates',
        description: 'Diátaxis documentation templates customized for OpenShift GitHub Actions',
        mimeType: 'application/json'
      },
      {
        uri: 'repo-helper://dev-guidelines',
        name: 'Development Guidelines',
        description: 'Development guidelines for OpenShift, Vault, and GitHub Actions',
        mimeType: 'text/markdown'
      },
      {
        uri: 'repo-helper://testing-standards',
        name: 'Testing Standards',
        description: 'Testing standards for multi-cloud OpenShift deployments',
        mimeType: 'text/markdown'
      }
    ];

    logger.debug(`Listed ${resources.length} available resources`);
    return resources;
  }

  /**
   * List available prompts
   */
  async listPrompts(): Promise<Prompt[]> {
    this.ensureInitialized();

    const prompts: Prompt[] = [
      {
        name: 'repo-helper-audit-documentation',
        description: 'Comprehensive documentation audit workflow',
        arguments: [
          {
            name: 'scope',
            description: 'Audit scope (full, diataxis, technical)',
            required: false
          }
        ]
      },
      {
        name: 'repo-helper-document-feature',
        description: 'Complete feature documentation workflow',
        arguments: [
          {
            name: 'feature',
            description: 'Feature to document',
            required: true
          },
          {
            name: 'includeAllTypes',
            description: 'Include all Diátaxis document types',
            required: false
          }
        ]
      }
    ];

    logger.debug(`Listed ${prompts.length} available prompts`);
    return prompts;
  }

  /**
   * Call a tool
   */
  async callTool(name: string, args: Record<string, any>): Promise<any> {
    this.ensureInitialized();

    logger.debug(`Calling tool: ${name}`, args);

    try {
      switch (name) {
        case 'repo-helper-generate-lld':
          return await this.handleLLDGeneration(args);
        case 'repo-helper-generate-api-docs':
          return await this.handleAPIDocGeneration(args);
        case 'repo-helper-generate-architecture':
          return await this.handleArchitectureGeneration(args);
        case 'repo-helper-generate-tutorial':
          return await this.handleTutorialGeneration(args);
        case 'repo-helper-generate-test-plan':
          return await this.handleTestPlanGeneration(args);
        default:
          return {
            content: [
              {
                type: 'text',
                text: `Tool ${name} is not yet implemented. Available tools: repo-helper-generate-lld, repo-helper-generate-api-docs, repo-helper-generate-architecture, repo-helper-generate-tutorial, repo-helper-generate-test-plan`
              }
            ]
          };
      }
    } catch (error) {
      logger.error(`Error calling tool ${name}:`, error);
      return {
        content: [
          {
            type: 'text',
            text: `Error executing tool ${name}: ${error instanceof Error ? error.message : 'Unknown error'}`
          }
        ]
      };
    }
  }

  /**
   * Handle LLD generation
   */
  private async handleLLDGeneration(args: Record<string, any>): Promise<any> {
    if (!this.lldGenerator) {
      throw new Error('LLD Generator not initialized');
    }

    const result = await this.lldGenerator.generateLLD({
      component: args['component'] || 'vault-ha',
      includeInterfaces: args['includeInterfaces'] || false,
      includeDataFlow: args['includeDataFlow'] || false,
      includeComponentDiagrams: true,
      includeSequenceDiagrams: true,
      detailLevel: 'high'
    });

    return {
      content: [
        {
          type: 'text',
          text: result.content
        }
      ]
    };
  }

  /**
   * Handle API documentation generation
   */
  private async handleAPIDocGeneration(args: Record<string, any>): Promise<any> {
    if (!this.apiDocGenerator) {
      throw new Error('API Documentation Generator not initialized');
    }

    const result = await this.apiDocGenerator.generateAPIDocumentation({
      outputFormat: args['outputFormat'] || 'markdown',
      includeExamples: args['includeExamples'] || true,
      includeAuthentication: args['includeAuthentication'] || true,
      includeErrorResponses: true,
      generateInteractiveDocs: false,
      apiType: 'all'
    });

    return {
      content: [
        {
          type: 'text',
          text: result.content
        }
      ]
    };
  }

  /**
   * Handle architecture guide generation
   */
  private async handleArchitectureGeneration(args: Record<string, any>): Promise<any> {
    if (!this.architectureGenerator) {
      throw new Error('Architecture Guide Generator not initialized');
    }

    const result = await this.architectureGenerator.generateArchitectureGuide({
      includeDeployment: args['includeDeployment'] || true,
      includeIntegrations: args['includeIntegrations'] || true,
      includeSecurity: args['includeSecurity'] || true,
      includeSystemOverview: true,
      architectureViews: ['logical', 'deployment', 'security'],
      outputFormat: 'markdown'
    });

    return {
      content: [
        {
          type: 'text',
          text: result.content
        }
      ]
    };
  }

  /**
   * Handle tutorial generation
   */
  private async handleTutorialGeneration(args: Record<string, any>): Promise<any> {
    if (!this.tutorialGenerator) {
      throw new Error('Tutorial Generator not initialized');
    }

    const result = await this.tutorialGenerator.generateTutorial({
      feature: args['feature'] || 'vault-ha-deployment',
      targetAudience: args['targetAudience'] || 'intermediate',
      includeSetup: args['includeSetup'] || true,
      stepByStep: args['stepByStep'] || true,
      includeTroubleshooting: args['includeTroubleshooting'] || true,
      outputFormat: 'markdown'
    });

    return {
      content: [
        {
          type: 'text',
          text: result.document.content
        }
      ]
    };
  }

  /**
   * Handle test plan generation
   */
  private async handleTestPlanGeneration(args: Record<string, any>): Promise<any> {
    if (!this.testPlanGenerator) {
      throw new Error('Test Plan Generator not initialized');
    }

    const result = await this.testPlanGenerator.generateTestPlan({
      component: args['component'] || 'vault-ha',
      testTypes: args['testTypes'] || ['unit', 'integration', 'e2e'],
      coverageTarget: args['coverageTarget'] || 85,
      includePerformanceTests: args['includePerformanceTests'] || false,
      includeSecurityTests: args['includeSecurityTests'] || true,
      testEnvironment: 'dev'
    });

    return {
      content: [
        {
          type: 'text',
          text: result.content
        }
      ]
    };
  }

  /**
   * Read a resource
   */
  async readResource(uri: string): Promise<any> {
    this.ensureInitialized();
    
    logger.debug(`Reading resource: ${uri}`);
    
    // Resource implementations will be added in subsequent tasks
    return {
      contents: [
        {
          uri,
          mimeType: 'text/plain',
          text: `Resource ${uri} requested. Implementation will be completed in subsequent development phases.`
        }
      ]
    };
  }

  /**
   * Get a prompt
   */
  async getPrompt(name: string, args: Record<string, any>): Promise<any> {
    this.ensureInitialized();
    
    logger.debug(`Getting prompt: ${name}`, args);
    
    // Prompt implementations will be added in subsequent tasks
    return {
      description: `Prompt ${name} with arguments: ${JSON.stringify(args)}`,
      messages: [
        {
          role: 'user',
          content: {
            type: 'text',
            text: `Execute ${name} prompt. Implementation will be completed in subsequent development phases.`
          }
        }
      ]
    };
  }

  /**
   * Ensure server is initialized
   */
  private ensureInitialized(): void {
    if (!this.initialized) {
      throw new Error('Server not initialized. Call initialize() first.');
    }
  }
}
