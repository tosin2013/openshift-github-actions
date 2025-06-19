/**
 * Configuration Types
 * 
 * Configuration interfaces for the OpenShift GitHub Actions Repository Helper MCP Server
 */

import { RepositoryDetectionResult } from './repository.js';

/**
 * Main repository helper configuration
 */
export interface RepoHelperConfig {
  /** Repository information */
  repositoryInfo: RepositoryDetectionResult;
  
  /** Diátaxis framework configuration */
  diataxisConfig: DiataxisConfig;
  
  /** Development support configuration */
  developmentSupport: DevelopmentSupportConfig;
  
  /** QA and testing configuration */
  qaAndTesting: QATestingConfig;
  
  /** Red Hat AI Services integration */
  redHatAIIntegration: RedHatAIConfig;
}

/**
 * Diátaxis framework configuration
 */
export interface DiataxisConfig {
  /** Enable tutorial generation */
  enableTutorials: boolean;
  
  /** Enable how-to guide generation */
  enableHowTos: boolean;
  
  /** Enable reference documentation generation */
  enableReference: boolean;
  
  /** Enable explanation generation */
  enableExplanations: boolean;
  
  /** Supported output formats */
  outputFormats: ('markdown' | 'html' | 'pdf')[];
  
  /** Template customization */
  templateCustomization?: TemplateCustomization;
  
  /** Content organization */
  contentOrganization?: ContentOrganization;
}

/**
 * Template customization options
 */
export interface TemplateCustomization {
  /** Custom template directory */
  templateDirectory?: string;
  
  /** Brand customization */
  branding?: BrandingConfig;
  
  /** Style customization */
  styling?: StylingConfig;
}

/**
 * Branding configuration
 */
export interface BrandingConfig {
  /** Organization name */
  organizationName: string;
  
  /** Logo URL */
  logoUrl?: string;
  
  /** Brand colors */
  colors?: {
    primary: string;
    secondary: string;
    accent: string;
  };
}

/**
 * Styling configuration
 */
export interface StylingConfig {
  /** CSS theme */
  theme: 'light' | 'dark' | 'auto';
  
  /** Font family */
  fontFamily?: string;
  
  /** Custom CSS */
  customCSS?: string;
}

/**
 * Content organization configuration
 */
export interface ContentOrganization {
  /** Directory structure */
  directoryStructure: 'flat' | 'hierarchical' | 'diataxis';
  
  /** File naming convention */
  fileNaming: 'kebab-case' | 'snake_case' | 'camelCase';
  
  /** Index generation */
  generateIndexes: boolean;
  
  /** Cross-references */
  enableCrossReferences: boolean;
}

/**
 * Development support configuration
 */
export interface DevelopmentSupportConfig {
  /** Enable LLD generation */
  generateLLD: boolean;
  
  /** Enable API documentation generation */
  generateAPIDocs: boolean;
  
  /** Enable architecture documentation generation */
  generateArchitecture: boolean;
  
  /** Enable code structure analysis */
  analyzeCodeStructure: boolean;
  
  /** LLD configuration */
  lldConfig?: LLDConfig;
  
  /** API documentation configuration */
  apiDocsConfig?: APIDocsConfig;
  
  /** Architecture documentation configuration */
  architectureConfig?: ArchitectureConfig;
}

/**
 * Low-Level Design configuration
 */
export interface LLDConfig {
  /** Include component diagrams */
  includeComponentDiagrams: boolean;
  
  /** Include sequence diagrams */
  includeSequenceDiagrams: boolean;
  
  /** Include data flow diagrams */
  includeDataFlowDiagrams: boolean;
  
  /** Diagram format */
  diagramFormat: 'mermaid' | 'plantuml' | 'drawio';
  
  /** Detail level */
  detailLevel: 'high' | 'medium' | 'low';
}

/**
 * API documentation configuration
 */
export interface APIDocsConfig {
  /** API specification format */
  specificationFormat: 'openapi' | 'asyncapi' | 'graphql';
  
  /** Include examples */
  includeExamples: boolean;
  
  /** Include authentication details */
  includeAuthentication: boolean;
  
  /** Include error responses */
  includeErrorResponses: boolean;
  
  /** Generate interactive docs */
  generateInteractiveDocs: boolean;
}

/**
 * Architecture documentation configuration
 */
export interface ArchitectureConfig {
  /** Include system overview */
  includeSystemOverview: boolean;
  
  /** Include deployment architecture */
  includeDeploymentArchitecture: boolean;
  
  /** Include integration patterns */
  includeIntegrationPatterns: boolean;
  
  /** Include security architecture */
  includeSecurityArchitecture: boolean;
  
  /** Architecture views */
  architectureViews: ArchitectureView[];
}

/**
 * Architecture view types
 */
export type ArchitectureView = 
  | 'logical'
  | 'physical'
  | 'process'
  | 'development'
  | 'deployment'
  | 'security';

/**
 * QA and testing configuration
 */
export interface QATestingConfig {
  /** Enable test plan generation */
  generateTestPlans: boolean;
  
  /** Enable spec-by-example generation */
  specByExample: boolean;
  
  /** Enable quality workflow generation */
  qualityWorkflows: boolean;
  
  /** Enable coverage analysis */
  coverageAnalysis: boolean;
  
  /** Test plan configuration */
  testPlanConfig?: TestPlanConfig;
  
  /** Spec-by-example configuration */
  specByExampleConfig?: SpecByExampleConfig;
  
  /** Quality workflow configuration */
  qualityWorkflowConfig?: QualityWorkflowConfig;
}

/**
 * Test plan configuration
 */
export interface TestPlanConfig {
  /** Test types to include */
  testTypes: TestType[];
  
  /** Coverage targets */
  coverageTargets: CoverageTargets;
  
  /** Test frameworks */
  testFrameworks: string[];
  
  /** Include performance tests */
  includePerformanceTests: boolean;
  
  /** Include security tests */
  includeSecurityTests: boolean;
}

/**
 * Test types
 */
export type TestType = 
  | 'unit'
  | 'integration'
  | 'e2e'
  | 'performance'
  | 'security'
  | 'accessibility'
  | 'compatibility';

/**
 * Coverage targets
 */
export interface CoverageTargets {
  /** Unit test coverage target */
  unit: number;
  
  /** Integration test coverage target */
  integration: number;
  
  /** End-to-end test coverage target */
  e2e: number;
  
  /** Overall coverage target */
  overall: number;
}

/**
 * Spec-by-example configuration
 */
export interface SpecByExampleConfig {
  /** Specification format */
  specificationFormat: 'gherkin' | 'markdown' | 'json' | 'yaml';
  
  /** Include edge cases */
  includeEdgeCases: boolean;
  
  /** Include error scenarios */
  includeErrorScenarios: boolean;
  
  /** Generate executable specs */
  generateExecutableSpecs: boolean;
  
  /** Scenario organization */
  scenarioOrganization: 'feature' | 'component' | 'user-journey';
}

/**
 * Quality workflow configuration
 */
export interface QualityWorkflowConfig {
  /** CI/CD integration */
  cicdIntegration: boolean;
  
  /** Quality gates */
  qualityGates: QualityGate[];
  
  /** Automation level */
  automationLevel: 'basic' | 'intermediate' | 'advanced';
  
  /** Notification settings */
  notifications: NotificationConfig;
}

/**
 * Quality gate definition
 */
export interface QualityGate {
  /** Gate name */
  name: string;
  
  /** Gate type */
  type: 'coverage' | 'performance' | 'security' | 'quality' | 'custom';
  
  /** Threshold */
  threshold: number;
  
  /** Required for deployment */
  required: boolean;
  
  /** Custom criteria */
  customCriteria?: string;
}

/**
 * Notification configuration
 */
export interface NotificationConfig {
  /** Enable notifications */
  enabled: boolean;
  
  /** Notification channels */
  channels: NotificationChannel[];
  
  /** Notification triggers */
  triggers: NotificationTrigger[];
}

/**
 * Notification channel
 */
export interface NotificationChannel {
  /** Channel type */
  type: 'email' | 'slack' | 'teams' | 'webhook';
  
  /** Channel configuration */
  config: Record<string, any>;
  
  /** Enabled */
  enabled: boolean;
}

/**
 * Notification trigger
 */
export type NotificationTrigger = 
  | 'test-failure'
  | 'coverage-drop'
  | 'quality-gate-failure'
  | 'deployment-failure'
  | 'security-issue';

/**
 * Red Hat AI Services configuration
 */
export interface RedHatAIConfig {
  /** AI service endpoint */
  endpoint: string;
  
  /** AI model to use */
  model: string;
  
  /** Specialization area */
  specialization: string;
  
  /** API configuration */
  apiConfig?: AIAPIConfig;
  
  /** Integration settings */
  integrationSettings?: AIIntegrationSettings;
}

/**
 * AI API configuration
 */
export interface AIAPIConfig {
  /** API key (if required) */
  apiKey?: string;
  
  /** Request timeout */
  timeout: number;
  
  /** Retry configuration */
  retryConfig: RetryConfig;
  
  /** Rate limiting */
  rateLimiting?: RateLimitConfig;
}

/**
 * Retry configuration
 */
export interface RetryConfig {
  /** Maximum retries */
  maxRetries: number;
  
  /** Retry delay */
  retryDelay: number;
  
  /** Exponential backoff */
  exponentialBackoff: boolean;
}

/**
 * Rate limiting configuration
 */
export interface RateLimitConfig {
  /** Requests per minute */
  requestsPerMinute: number;
  
  /** Burst limit */
  burstLimit: number;
}

/**
 * AI integration settings
 */
export interface AIIntegrationSettings {
  /** Enable AI-assisted documentation */
  enableAIDocumentation: boolean;
  
  /** Enable AI-assisted testing */
  enableAITesting: boolean;
  
  /** Enable AI-assisted code analysis */
  enableAICodeAnalysis: boolean;
  
  /** Confidence threshold */
  confidenceThreshold: number;
  
  /** Human review required */
  humanReviewRequired: boolean;
}
