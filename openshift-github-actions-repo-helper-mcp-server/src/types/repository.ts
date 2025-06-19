/**
 * Repository Detection Types
 * 
 * Interfaces and types for repository analysis and detection results
 * specific to the OpenShift GitHub Actions multi-cloud automation repository.
 */

/**
 * Main repository detection result interface
 */
export interface RepositoryDetectionResult {
  /** Repository name */
  name: string;
  
  /** Repository URL */
  url: string;
  
  /** Primary purpose/description */
  primaryPurpose: string;
  
  /** Detected technologies and frameworks */
  detectedTechnologies: string[];
  
  /** Architecture patterns identified */
  architecturePatterns: string[];
  
  /** Confidence score (0-100) */
  confidenceScore: number;
  
  /** Detailed technology analysis */
  technologyAnalysis?: TechnologyAnalysis;
  
  /** Repository structure analysis */
  structureAnalysis?: RepositoryStructure;
  
  /** Documentation analysis */
  documentationAnalysis?: DocumentationAnalysis;
}

/**
 * Detailed technology analysis
 */
export interface TechnologyAnalysis {
  /** Red Hat ecosystem components */
  redHatEcosystem: RedHatComponents;
  
  /** Security and secrets management */
  securityStack: SecurityComponents;
  
  /** Multi-cloud infrastructure */
  cloudInfrastructure: CloudComponents;
  
  /** CI/CD and automation */
  cicdAutomation: CICDComponents;
  
  /** Development tools */
  developmentTools: DevelopmentComponents;
}

/**
 * Red Hat ecosystem components
 */
export interface RedHatComponents {
  /** Operating system */
  operatingSystem: string;
  
  /** Container platform */
  containerPlatform: string;
  
  /** OpenShift version */
  openshiftVersion: string;
  
  /** Automation tools */
  automationTools: string[];
  
  /** Additional Red Hat tools */
  additionalTools: string[];
}

/**
 * Security and secrets management components
 */
export interface SecurityComponents {
  /** Primary secrets management */
  secretsManagement: string;
  
  /** Authentication methods */
  authenticationMethods: string[];
  
  /** Certificate management */
  certificateManagement: string[];
  
  /** Credential types */
  credentialTypes: string[];
  
  /** Security patterns */
  securityPatterns: string[];
}

/**
 * Multi-cloud infrastructure components
 */
export interface CloudComponents {
  /** Supported cloud providers */
  providers: CloudProvider[];
  
  /** Deployment method */
  deploymentMethod: string;
  
  /** Common services */
  commonServices: string[];
}

/**
 * Cloud provider configuration
 */
export interface CloudProvider {
  /** Provider name */
  name: 'AWS' | 'Azure' | 'GCP';
  
  /** Supported services */
  services: string[];
  
  /** Authentication method */
  authMethod: string;
  
  /** Configuration files */
  configFiles: string[];
}

/**
 * CI/CD and automation components
 */
export interface CICDComponents {
  /** Primary CI/CD platform */
  primaryPlatform: string;
  
  /** Workflow files */
  workflowFiles: string[];
  
  /** Configuration management */
  configManagement: string[];
  
  /** Scripting languages */
  scriptingLanguages: string[];
  
  /** Template engines */
  templateEngines: string[];
}

/**
 * Development tools and environment
 */
export interface DevelopmentComponents {
  /** Required tools */
  requiredTools: string[];
  
  /** IDE configurations */
  ideConfigurations: string[];
  
  /** Package managers */
  packageManagers: string[];
  
  /** Testing frameworks */
  testingFrameworks: string[];
}

/**
 * Repository structure analysis
 */
export interface RepositoryStructure {
  /** GitHub Actions workflows */
  githubActions: WorkflowAnalysis;
  
  /** Ansible automation */
  ansibleAutomation: AnsibleAnalysis;
  
  /** Scripts organization */
  scriptsOrganization: ScriptsAnalysis;
  
  /** Configuration management */
  configurationManagement: ConfigAnalysis;
  
  /** Testing structure */
  testingStructure: TestingAnalysis;
}

/**
 * GitHub Actions workflow analysis
 */
export interface WorkflowAnalysis {
  /** Workflow files */
  workflowFiles: string[];
  
  /** Deployment workflows */
  deploymentWorkflows: string[];
  
  /** Operational workflows */
  operationalWorkflows: string[];
  
  /** Testing workflows */
  testingWorkflows: string[];
  
  /** Workflow patterns */
  patterns: string[];
}

/**
 * Ansible automation analysis
 */
export interface AnsibleAnalysis {
  /** Playbook files */
  playbookFiles: string[];
  
  /** Roles */
  roles: AnsibleRole[];
  
  /** Inventory files */
  inventoryFiles: string[];
  
  /** Configuration files */
  configFiles: string[];
}

/**
 * Ansible role definition
 */
export interface AnsibleRole {
  /** Role name */
  name: string;
  
  /** Role purpose */
  purpose: string;
  
  /** Dependencies */
  dependencies: string[];
  
  /** Configuration files */
  configFiles: string[];
}

/**
 * Scripts organization analysis
 */
export interface ScriptsAnalysis {
  /** Script directories */
  directories: string[];
  
  /** Cloud-specific scripts */
  cloudSpecificScripts: Record<string, string[]>;
  
  /** Common utilities */
  commonUtilities: string[];
  
  /** Vault management scripts */
  vaultScripts: string[];
  
  /** Scripting languages used */
  languages: string[];
}

/**
 * Configuration management analysis
 */
export interface ConfigAnalysis {
  /** Configuration directories */
  directories: string[];
  
  /** Template files */
  templateFiles: string[];
  
  /** Environment-specific configs */
  environmentConfigs: Record<string, string[]>;
  
  /** Configuration patterns */
  patterns: string[];
}

/**
 * Testing structure analysis
 */
export interface TestingAnalysis {
  /** Test directories */
  testDirectories: string[];
  
  /** Test types */
  testTypes: string[];
  
  /** Validation scripts */
  validationScripts: string[];
  
  /** Testing frameworks */
  frameworks: string[];
}

/**
 * Documentation analysis
 */
export interface DocumentationAnalysis {
  /** Documentation structure */
  structure: DocumentationStructure;
  
  /** Diátaxis compliance */
  diataxisCompliance: DiataxisCompliance;
  
  /** Architecture Decision Records */
  adrs: ADRAnalysis;
  
  /** Quality metrics */
  qualityMetrics: DocumentationQuality;
}

/**
 * Documentation structure
 */
export interface DocumentationStructure {
  /** Main documentation files */
  mainFiles: string[];
  
  /** Documentation directories */
  directories: string[];
  
  /** Guide files */
  guides: string[];
  
  /** Reference documentation */
  references: string[];
}

/**
 * Diátaxis framework compliance analysis
 */
export interface DiataxisCompliance {
  /** Has tutorials */
  hasTutorials: boolean;
  
  /** Has how-to guides */
  hasHowToGuides: boolean;
  
  /** Has reference documentation */
  hasReference: boolean;
  
  /** Has explanations */
  hasExplanations: boolean;
  
  /** Compliance score (0-100) */
  complianceScore: number;
  
  /** Recommendations */
  recommendations: string[];
}

/**
 * Architecture Decision Records analysis
 */
export interface ADRAnalysis {
  /** ADR files */
  adrFiles: string[];
  
  /** Total ADRs */
  totalADRs: number;
  
  /** ADR topics */
  topics: string[];
  
  /** ADR quality score */
  qualityScore: number;
}

/**
 * Documentation quality metrics
 */
export interface DocumentationQuality {
  /** Coverage score (0-100) */
  coverageScore: number;
  
  /** Completeness score (0-100) */
  completenessScore: number;
  
  /** Consistency score (0-100) */
  consistencyScore: number;
  
  /** Overall quality score (0-100) */
  overallScore: number;
  
  /** Areas for improvement */
  improvementAreas: string[];
}
