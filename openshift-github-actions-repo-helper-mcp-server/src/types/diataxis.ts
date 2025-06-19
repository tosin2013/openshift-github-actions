/**
 * Diátaxis Framework Types
 * 
 * Core types and interfaces for the Diátaxis documentation framework
 * implementation in the OpenShift GitHub Actions Repository Helper.
 */

import { RepositoryDetectionResult } from './repository.js';

/**
 * Diátaxis document types enum
 */
export enum DiataxisType {
  TUTORIAL = 'tutorial',      // Learning-oriented (hands-on)
  HOW_TO = 'how-to',         // Problem-oriented (goal-oriented)
  REFERENCE = 'reference',    // Information-oriented (lookup)
  EXPLANATION = 'explanation' // Understanding-oriented (theoretical)
}

/**
 * Target audience types
 */
export enum AudienceType {
  DEVELOPER = 'developer',
  USER = 'user',
  CONTRIBUTOR = 'contributor',
  MAINTAINER = 'maintainer',
  OPERATOR = 'operator',
  ARCHITECT = 'architect'
}

/**
 * Complexity levels
 */
export enum ComplexityLevel {
  BEGINNER = 'beginner',
  INTERMEDIATE = 'intermediate',
  ADVANCED = 'advanced',
  EXPERT = 'expert'
}

/**
 * Main Diátaxis document interface
 */
export interface DiataxisDocument {
  /** Document type */
  type: DiataxisType;
  
  /** Document title */
  title: string;
  
  /** Target audience */
  audience: AudienceType;
  
  /** Complexity level */
  complexity: ComplexityLevel;
  
  /** Repository context */
  repositoryContext: RepositoryDetectionResult;
  
  /** Document content */
  content: string;
  
  /** Related documents */
  relatedDocs: string[];
  
  /** Code examples */
  codeExamples: CodeExample[];
  
  /** Last updated timestamp */
  lastUpdated: Date;
  
  /** Document metadata */
  metadata: DocumentMetadata;
  
  /** Validation status */
  validationStatus?: ValidationStatus;
}

/**
 * Code example interface
 */
export interface CodeExample {
  /** Programming language */
  language: string;
  
  /** Code content */
  code: string;
  
  /** Example description */
  description: string;
  
  /** Whether example is runnable */
  runnable: boolean;
  
  /** Expected output */
  expectedOutput?: string;
  
  /** Prerequisites */
  prerequisites?: string[];
  
  /** Example metadata */
  metadata?: CodeExampleMetadata;
}

/**
 * Code example metadata
 */
export interface CodeExampleMetadata {
  /** File path in repository */
  filePath?: string;
  
  /** Line numbers */
  lineNumbers?: {
    start: number;
    end: number;
  };
  
  /** Dependencies */
  dependencies?: string[];
  
  /** Environment requirements */
  environmentRequirements?: string[];
}

/**
 * Document metadata
 */
export interface DocumentMetadata {
  /** Document ID */
  id: string;
  
  /** Author */
  author?: string;
  
  /** Contributors */
  contributors?: string[];
  
  /** Tags */
  tags: string[];
  
  /** Categories */
  categories: string[];
  
  /** Estimated reading time (minutes) */
  estimatedReadingTime?: number;
  
  /** Prerequisites */
  prerequisites?: string[];
  
  /** Learning objectives */
  learningObjectives?: string[];
  
  /** Success criteria */
  successCriteria?: string[];
}

/**
 * Validation status
 */
export interface ValidationStatus {
  /** Is valid */
  isValid: boolean;
  
  /** Validation score (0-100) */
  score: number;
  
  /** Validation errors */
  errors: ValidationError[];
  
  /** Validation warnings */
  warnings: ValidationWarning[];
  
  /** Last validated */
  lastValidated: Date;
}

/**
 * Validation error
 */
export interface ValidationError {
  /** Error code */
  code: string;
  
  /** Error message */
  message: string;
  
  /** Severity */
  severity: 'error' | 'warning' | 'info';
  
  /** Location in document */
  location?: DocumentLocation;
}

/**
 * Validation warning
 */
export interface ValidationWarning {
  /** Warning code */
  code: string;
  
  /** Warning message */
  message: string;
  
  /** Suggestion */
  suggestion?: string;
  
  /** Location in document */
  location?: DocumentLocation;
}

/**
 * Document location
 */
export interface DocumentLocation {
  /** Line number */
  line: number;
  
  /** Column number */
  column?: number;
  
  /** Section */
  section?: string;
}

/**
 * Tutorial-specific interface
 */
export interface TutorialDocument extends DiataxisDocument {
  type: DiataxisType.TUTORIAL;
  
  /** Tutorial steps */
  steps: TutorialStep[];
  
  /** Setup requirements */
  setupRequirements: SetupRequirement[];
  
  /** Expected outcomes */
  expectedOutcomes: string[];
  
  /** Troubleshooting section */
  troubleshooting?: TroubleshootingSection;
}

/**
 * Tutorial step
 */
export interface TutorialStep {
  /** Step number */
  stepNumber: number;
  
  /** Step title */
  title: string;
  
  /** Step description */
  description: string;
  
  /** Instructions */
  instructions: string[];
  
  /** Code examples */
  codeExamples?: CodeExample[];
  
  /** Expected result */
  expectedResult?: string;
  
  /** Verification steps */
  verificationSteps?: string[];
}

/**
 * Setup requirement
 */
export interface SetupRequirement {
  /** Requirement name */
  name: string;
  
  /** Description */
  description: string;
  
  /** Installation instructions */
  installationInstructions?: string;
  
  /** Version requirements */
  versionRequirements?: string;
  
  /** Optional requirement */
  optional: boolean;
}

/**
 * How-to guide specific interface
 */
export interface HowToDocument extends DiataxisDocument {
  type: DiataxisType.HOW_TO;
  
  /** Problem statement */
  problemStatement: string;
  
  /** Solution overview */
  solutionOverview: string;
  
  /** Solution steps */
  solutionSteps: SolutionStep[];
  
  /** Alternative approaches */
  alternativeApproaches?: AlternativeApproach[];
  
  /** Troubleshooting */
  troubleshooting?: TroubleshootingSection;
}

/**
 * Solution step
 */
export interface SolutionStep {
  /** Step number */
  stepNumber: number;
  
  /** Step title */
  title: string;
  
  /** Instructions */
  instructions: string;
  
  /** Code examples */
  codeExamples?: CodeExample[];
  
  /** Notes */
  notes?: string[];
  
  /** Warnings */
  warnings?: string[];
}

/**
 * Alternative approach
 */
export interface AlternativeApproach {
  /** Approach name */
  name: string;
  
  /** Description */
  description: string;
  
  /** When to use */
  whenToUse: string;
  
  /** Pros and cons */
  prosAndCons?: {
    pros: string[];
    cons: string[];
  };
  
  /** Implementation steps */
  implementationSteps?: string[];
}

/**
 * Reference document specific interface
 */
export interface ReferenceDocument extends DiataxisDocument {
  type: DiataxisType.REFERENCE;
  
  /** Reference sections */
  sections: ReferenceSection[];
  
  /** API references */
  apiReferences?: APIReference[];
  
  /** Configuration references */
  configurationReferences?: ConfigurationReference[];
  
  /** Command references */
  commandReferences?: CommandReference[];
}

/**
 * Reference section
 */
export interface ReferenceSection {
  /** Section title */
  title: string;
  
  /** Section content */
  content: string;
  
  /** Subsections */
  subsections?: ReferenceSection[];
  
  /** Cross-references */
  crossReferences?: string[];
}

/**
 * API reference
 */
export interface APIReference {
  /** API name */
  name: string;
  
  /** Description */
  description: string;
  
  /** Endpoints */
  endpoints?: APIEndpoint[];
  
  /** Authentication */
  authentication?: AuthenticationInfo;
  
  /** Examples */
  examples?: APIExample[];
}

/**
 * API endpoint
 */
export interface APIEndpoint {
  /** HTTP method */
  method: string;
  
  /** Endpoint path */
  path: string;
  
  /** Description */
  description: string;
  
  /** Parameters */
  parameters?: APIParameter[];
  
  /** Response format */
  responseFormat?: string;
  
  /** Status codes */
  statusCodes?: StatusCode[];
}

/**
 * API parameter
 */
export interface APIParameter {
  /** Parameter name */
  name: string;
  
  /** Parameter type */
  type: string;
  
  /** Description */
  description: string;
  
  /** Required */
  required: boolean;
  
  /** Default value */
  defaultValue?: any;
  
  /** Example value */
  exampleValue?: any;
}

/**
 * Status code
 */
export interface StatusCode {
  /** HTTP status code */
  code: number;
  
  /** Description */
  description: string;
  
  /** Example response */
  exampleResponse?: string;
}

/**
 * Authentication info
 */
export interface AuthenticationInfo {
  /** Authentication type */
  type: string;
  
  /** Description */
  description: string;
  
  /** Required headers */
  requiredHeaders?: string[];
  
  /** Example */
  example?: string;
}

/**
 * API example
 */
export interface APIExample {
  /** Example title */
  title: string;
  
  /** Request example */
  request: string;
  
  /** Response example */
  response: string;
  
  /** Description */
  description?: string;
}

/**
 * Configuration reference
 */
export interface ConfigurationReference {
  /** Configuration name */
  name: string;
  
  /** Description */
  description: string;
  
  /** Configuration options */
  options: ConfigurationOption[];
  
  /** Example configuration */
  exampleConfiguration?: string;
}

/**
 * Configuration option
 */
export interface ConfigurationOption {
  /** Option name */
  name: string;
  
  /** Option type */
  type: string;
  
  /** Description */
  description: string;
  
  /** Default value */
  defaultValue?: any;
  
  /** Possible values */
  possibleValues?: any[];
  
  /** Required */
  required: boolean;
}

/**
 * Command reference
 */
export interface CommandReference {
  /** Command name */
  name: string;
  
  /** Description */
  description: string;
  
  /** Syntax */
  syntax: string;
  
  /** Options */
  options?: CommandOption[];
  
  /** Examples */
  examples?: CommandExample[];
}

/**
 * Command option
 */
export interface CommandOption {
  /** Option name */
  name: string;
  
  /** Short form */
  shortForm?: string;
  
  /** Description */
  description: string;
  
  /** Required */
  required: boolean;
  
  /** Default value */
  defaultValue?: string;
}

/**
 * Command example
 */
export interface CommandExample {
  /** Example command */
  command: string;
  
  /** Description */
  description: string;
  
  /** Expected output */
  expectedOutput?: string;
}

/**
 * Explanation document specific interface
 */
export interface ExplanationDocument extends DiataxisDocument {
  type: DiataxisType.EXPLANATION;
  
  /** Concept overview */
  conceptOverview: string;
  
  /** Key concepts */
  keyConcepts: KeyConcept[];
  
  /** Design decisions */
  designDecisions?: DesignDecision[];
  
  /** Trade-offs */
  tradeOffs?: TradeOff[];
  
  /** Related concepts */
  relatedConcepts?: string[];
}

/**
 * Key concept
 */
export interface KeyConcept {
  /** Concept name */
  name: string;
  
  /** Definition */
  definition: string;
  
  /** Explanation */
  explanation: string;
  
  /** Examples */
  examples?: string[];
  
  /** Related concepts */
  relatedConcepts?: string[];
}

/**
 * Design decision
 */
export interface DesignDecision {
  /** Decision title */
  title: string;
  
  /** Context */
  context: string;
  
  /** Decision */
  decision: string;
  
  /** Rationale */
  rationale: string;
  
  /** Consequences */
  consequences?: string[];
  
  /** Alternatives considered */
  alternativesConsidered?: string[];
}

/**
 * Trade-off
 */
export interface TradeOff {
  /** Trade-off title */
  title: string;
  
  /** Description */
  description: string;
  
  /** Benefits */
  benefits: string[];
  
  /** Drawbacks */
  drawbacks: string[];
  
  /** When to choose */
  whenToChoose: string;
}

/**
 * Troubleshooting section
 */
export interface TroubleshootingSection {
  /** Common issues */
  commonIssues: TroubleshootingIssue[];
  
  /** General troubleshooting steps */
  generalSteps?: string[];
  
  /** Support resources */
  supportResources?: SupportResource[];
}

/**
 * Troubleshooting issue
 */
export interface TroubleshootingIssue {
  /** Issue title */
  title: string;
  
  /** Symptoms */
  symptoms: string[];
  
  /** Possible causes */
  possibleCauses: string[];
  
  /** Solutions */
  solutions: string[];
  
  /** Prevention */
  prevention?: string[];
}

/**
 * Support resource
 */
export interface SupportResource {
  /** Resource name */
  name: string;

  /** Resource type */
  type: 'documentation' | 'forum' | 'chat' | 'email' | 'issue-tracker';

  /** URL */
  url: string;

  /** Description */
  description?: string;
}

/**
 * Document generation options
 */
export interface DocumentGenerationOptions {
  /** Output format */
  outputFormat: 'markdown' | 'html' | 'pdf';

  /** Include table of contents */
  includeTableOfContents: boolean;

  /** Include code examples */
  includeCodeExamples: boolean;

  /** Include cross-references */
  includeCrossReferences: boolean;

  /** Template customization */
  templateCustomization?: Record<string, any>;

  /** Validation options */
  validationOptions?: ValidationOptions;
}

/**
 * Validation options
 */
export interface ValidationOptions {
  /** Validate content structure */
  validateStructure: boolean;

  /** Validate code examples */
  validateCodeExamples: boolean;

  /** Validate cross-references */
  validateCrossReferences: boolean;

  /** Minimum quality score */
  minimumQualityScore: number;

  /** Strict validation */
  strictValidation: boolean;
}
