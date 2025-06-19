/**
 * Tutorial Generator
 * 
 * Generates learning-oriented tutorials for OpenShift deployment, Vault setup,
 * and multi-cloud automation based on the actual repository workflows and scripts.
 * Follows the Diátaxis framework for tutorial creation.
 */

import { 
  DiataxisDocument, 
  DiataxisType, 
  AudienceType, 
  ComplexityLevel,
  TutorialDocument,
  TutorialStep,
  SetupRequirement,
  TroubleshootingSection,
  DocumentGenerationOptions
} from '../types/diataxis.js';
import { RepositoryDetectionResult } from '../types/repository.js';
import { DiataxisDocumentGenerator } from '../core/DiataxisDocumentGenerator.js';
import { logger } from '../utils/logger.js';

/**
 * Tutorial generation input parameters
 */
export interface TutorialGenerationInput {
  /** Feature to create tutorial for */
  feature: string;
  
  /** Target audience */
  targetAudience: 'beginner' | 'intermediate' | 'advanced';
  
  /** Include setup instructions */
  includeSetup: boolean;
  
  /** Step-by-step guidance */
  stepByStep?: boolean;
  
  /** Include troubleshooting */
  includeTroubleshooting?: boolean;
  
  /** Output format */
  outputFormat?: 'markdown' | 'html';
}

/**
 * Tutorial generation result
 */
export interface TutorialGenerationResult {
  /** Generated tutorial document */
  document: TutorialDocument;
  
  /** Tutorial steps */
  steps: TutorialStep[];
  
  /** Setup requirements */
  setupRequirements: SetupRequirement[];
  
  /** Expected outcomes */
  expectedOutcomes: string[];
  
  /** Metadata */
  metadata: TutorialMetadata;
}

/**
 * Tutorial metadata
 */
export interface TutorialMetadata {
  /** Generation timestamp */
  generationTimestamp: Date;
  
  /** Repository context */
  repositoryContext: RepositoryDetectionResult;
  
  /** Confidence score */
  confidenceScore: number;
  
  /** Feature covered */
  feature: string;
  
  /** Estimated completion time */
  estimatedCompletionTime: number;
  
  /** Prerequisites count */
  prerequisitesCount: number;
}

/**
 * Tutorial Generator class
 */
export class TutorialGenerator extends DiataxisDocumentGenerator {
  
  constructor(repositoryContext: RepositoryDetectionResult) {
    super(repositoryContext, DiataxisType.TUTORIAL);
  }

  /**
   * Generate tutorial
   */
  async generateTutorial(input: TutorialGenerationInput): Promise<TutorialGenerationResult> {
    logger.diataxis(
      'tutorial',
      `Generating tutorial for feature: ${input.feature}`,
      85,
      { targetAudience: input.targetAudience, includeSetup: input.includeSetup }
    );

    try {
      const options: DocumentGenerationOptions = {
        outputFormat: input.outputFormat || 'markdown',
        includeTableOfContents: true,
        includeCodeExamples: true,
        includeCrossReferences: true,
        validationOptions: {
          validateStructure: true,
          validateCodeExamples: true,
          validateCrossReferences: true,
          minimumQualityScore: 80,
          strictValidation: false
        }
      };

      // Generate base tutorial document
      const document = await this.generateDocument(
        this.generateTutorialTitle(input.feature),
        this.mapAudience(input.targetAudience),
        this.mapComplexity(input.targetAudience),
        options
      ) as TutorialDocument;

      // Generate tutorial-specific content
      const steps = await this.generateTutorialSteps(input);
      const setupRequirements = await this.generateSetupRequirements(input);
      const expectedOutcomes = await this.generateExpectedOutcomes(input);

      // Update document with tutorial-specific content
      document.steps = steps;
      document.setupRequirements = setupRequirements;
      document.expectedOutcomes = expectedOutcomes;

      if (input.includeTroubleshooting) {
        document.troubleshooting = await this.generateTroubleshooting(input);
      }

      const result: TutorialGenerationResult = {
        document,
        steps,
        setupRequirements,
        expectedOutcomes,
        metadata: {
          generationTimestamp: new Date(),
          repositoryContext: this.repositoryContext,
          confidenceScore: this.calculateTutorialConfidence(input, steps),
          feature: input.feature,
          estimatedCompletionTime: this.estimateCompletionTime(steps),
          prerequisitesCount: setupRequirements.length
        }
      };

      logger.diataxis(
        'tutorial',
        `Tutorial generation completed for ${input.feature}`,
        result.metadata.confidenceScore,
        { 
          stepsCount: steps.length,
          estimatedTime: result.metadata.estimatedCompletionTime 
        }
      );

      return result;

    } catch (error) {
      logger.error(`Failed to generate tutorial for feature: ${input.feature}`, error);
      throw error;
    }
  }

  /**
   * Generate type-specific content (implementation of abstract method)
   */
  protected async generateTypeSpecificContent(
    document: DiataxisDocument,
    _options: DocumentGenerationOptions
  ): Promise<void> {
    // Tutorial-specific content generation is handled in generateTutorial method
    document.content = `# ${document.title}

This is a hands-on tutorial that will guide you through ${document.title.toLowerCase()}.

## What You'll Learn

By the end of this tutorial, you will be able to:
- Understand the core concepts
- Complete practical exercises
- Apply the knowledge to real scenarios

## Prerequisites

Before starting this tutorial, ensure you have the necessary prerequisites installed and configured.

## Tutorial Steps

Follow the step-by-step instructions below to complete this tutorial.
`;
  }

  /**
   * Generate tutorial steps based on feature
   */
  private async generateTutorialSteps(input: TutorialGenerationInput): Promise<TutorialStep[]> {
    const steps: TutorialStep[] = [];

    switch (input.feature.toLowerCase()) {
      case 'vault-ha-deployment':
      case 'vault-setup':
        steps.push(...await this.generateVaultTutorialSteps(input));
        break;
      case 'openshift-deployment':
      case 'multi-cloud-deployment':
        steps.push(...await this.generateOpenShiftTutorialSteps(input));
        break;
      case 'github-actions-setup':
      case 'ci-cd-setup':
        steps.push(...await this.generateGitHubActionsTutorialSteps(input));
        break;
      default:
        steps.push(...await this.generateGenericTutorialSteps(input));
    }

    return steps;
  }

  /**
   * Generate Vault HA deployment tutorial steps
   */
  private async generateVaultTutorialSteps(_input: TutorialGenerationInput): Promise<TutorialStep[]> {
    const steps: TutorialStep[] = [
      {
        stepNumber: 1,
        title: 'Prepare OpenShift Environment',
        description: 'Set up the OpenShift environment for Vault HA deployment',
        instructions: [
          'Log in to your OpenShift cluster using the oc CLI',
          'Create a new project for Vault: `oc new-project vault-production`',
          'Verify you have cluster-admin privileges',
          'Ensure cert-manager is installed and operational'
        ],
        codeExamples: [
          {
            language: 'bash',
            code: `# Login to OpenShift cluster
oc login --token=<your-token> --server=<cluster-url>

# Create Vault namespace
oc new-project vault-production

# Verify permissions
oc auth can-i create clusterroles`,
            description: 'OpenShift cluster preparation commands',
            runnable: true,
            expectedOutput: 'Project "vault-production" created successfully'
          }
        ],
        expectedResult: 'OpenShift environment ready for Vault deployment',
        verificationSteps: [
          'Verify project creation: `oc get projects | grep vault-production`',
          'Check cert-manager status: `oc get pods -n cert-manager`'
        ]
      },
      {
        stepNumber: 2,
        title: 'Deploy Vault HA with Helm',
        description: 'Deploy HashiCorp Vault in High Availability mode using Helm',
        instructions: [
          'Add the HashiCorp Helm repository',
          'Create Vault configuration values file',
          'Deploy Vault using Helm with HA configuration',
          'Wait for all Vault pods to be ready'
        ],
        codeExamples: [
          {
            language: 'bash',
            code: `# Add HashiCorp Helm repo
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Deploy Vault HA
helm install vault hashicorp/vault \\
  --namespace vault-production \\
  --values vault-ha-values.yaml

# Check deployment status
oc get pods -n vault-production`,
            description: 'Vault HA deployment with Helm',
            runnable: true,
            expectedOutput: 'vault-0, vault-1, vault-2 pods running'
          }
        ],
        expectedResult: 'Vault HA cluster deployed with 3 replicas',
        verificationSteps: [
          'Check pod status: `oc get pods -n vault-production`',
          'Verify StatefulSet: `oc get statefulset vault -n vault-production`'
        ]
      },
      {
        stepNumber: 3,
        title: 'Initialize and Unseal Vault',
        description: 'Initialize the Vault cluster and unseal all replicas',
        instructions: [
          'Initialize Vault on the first pod (vault-0)',
          'Save the unseal keys and root token securely',
          'Unseal all three Vault replicas',
          'Verify cluster status and leader election'
        ],
        codeExamples: [
          {
            language: 'bash',
            code: `# Initialize Vault
oc exec vault-0 -n vault-production -- vault operator init \\
  -key-shares=5 \\
  -key-threshold=3 \\
  -format=json > vault-init.json

# Unseal vault-0
oc exec vault-0 -n vault-production -- vault operator unseal <unseal-key-1>
oc exec vault-0 -n vault-production -- vault operator unseal <unseal-key-2>
oc exec vault-0 -n vault-production -- vault operator unseal <unseal-key-3>

# Unseal vault-1 and vault-2 (repeat unseal commands)`,
            description: 'Vault initialization and unsealing process',
            runnable: true,
            expectedOutput: 'All Vault replicas unsealed and ready'
          }
        ],
        expectedResult: 'Vault cluster initialized and all replicas unsealed',
        verificationSteps: [
          'Check seal status: `oc exec vault-0 -n vault-production -- vault status`',
          'Verify HA status: `oc exec vault-0 -n vault-production -- vault operator raft list-peers`'
        ]
      }
    ];

    return steps;
  }

  /**
   * Generate OpenShift deployment tutorial steps
   */
  private async generateOpenShiftTutorialSteps(_input: TutorialGenerationInput): Promise<TutorialStep[]> {
    return [
      {
        stepNumber: 1,
        title: 'Configure GitHub Actions Secrets',
        description: 'Set up the required secrets in GitHub repository for OpenShift deployment',
        instructions: [
          'Navigate to your GitHub repository settings',
          'Add Vault URL, JWT audience, and role secrets',
          'Configure cloud provider specific settings',
          'Test the secret configuration'
        ],
        codeExamples: [
          {
            language: 'yaml',
            code: `# Required GitHub Secrets:
VAULT_URL: https://vault-route-vault-production.apps.cluster.local
VAULT_JWT_AUDIENCE: https://github.com/your-org
VAULT_ROLE: github-actions-deployer
OPENSHIFT_VERSION: 4.18.17`,
            description: 'GitHub repository secrets configuration',
            runnable: false
          }
        ],
        expectedResult: 'GitHub repository configured with required secrets',
        verificationSteps: [
          'Verify secrets are set in repository settings',
          'Test workflow dispatch with dry-run option'
        ]
      }
    ];
  }

  /**
   * Generate GitHub Actions tutorial steps
   */
  private async generateGitHubActionsTutorialSteps(_input: TutorialGenerationInput): Promise<TutorialStep[]> {
    return [
      {
        stepNumber: 1,
        title: 'Set Up GitHub Actions Workflow',
        description: 'Create and configure GitHub Actions workflow for multi-cloud deployment',
        instructions: [
          'Create .github/workflows directory in your repository',
          'Copy the multi-cloud deployment workflow',
          'Customize the workflow for your environment',
          'Test the workflow with a dry run'
        ],
        codeExamples: [
          {
            language: 'yaml',
            code: `name: Deploy OpenShift Multi-Cloud
on:
  workflow_dispatch:
    inputs:
      cloud_provider:
        description: 'Cloud provider'
        required: true
        type: choice
        options: ['aws', 'azure', 'gcp', 'all']
      cluster_name:
        description: 'Cluster name'
        required: true
        type: string`,
            description: 'GitHub Actions workflow configuration',
            runnable: false
          }
        ],
        expectedResult: 'GitHub Actions workflow configured and ready',
        verificationSteps: [
          'Workflow appears in Actions tab',
          'Manual trigger works correctly'
        ]
      }
    ];
  }

  /**
   * Generate generic tutorial steps
   */
  private async generateGenericTutorialSteps(input: TutorialGenerationInput): Promise<TutorialStep[]> {
    return [
      {
        stepNumber: 1,
        title: `Getting Started with ${input.feature}`,
        description: `Introduction to ${input.feature} in the OpenShift GitHub Actions context`,
        instructions: [
          'Review the repository structure',
          'Understand the component relationships',
          'Identify the key configuration files',
          'Prepare your development environment'
        ],
        codeExamples: [],
        expectedResult: `Basic understanding of ${input.feature}`,
        verificationSteps: [
          'Can navigate the repository structure',
          'Understands the main components'
        ]
      }
    ];
  }

  /**
   * Generate setup requirements
   */
  private async generateSetupRequirements(input: TutorialGenerationInput): Promise<SetupRequirement[]> {
    const requirements: SetupRequirement[] = [
      {
        name: 'OpenShift CLI (oc)',
        description: 'Command-line interface for OpenShift',
        installationInstructions: 'Download from OpenShift console or use package manager',
        versionRequirements: '4.18+',
        optional: false
      },
      {
        name: 'Helm 3.x',
        description: 'Kubernetes package manager',
        installationInstructions: 'Install via package manager or download binary',
        versionRequirements: '3.0+',
        optional: false
      }
    ];

    if (input.feature.toLowerCase().includes('vault')) {
      requirements.push({
        name: 'Vault CLI',
        description: 'HashiCorp Vault command-line interface',
        installationInstructions: 'Download from HashiCorp releases page',
        versionRequirements: '1.15+',
        optional: true
      });
    }

    return requirements;
  }

  /**
   * Generate expected outcomes
   */
  private async generateExpectedOutcomes(input: TutorialGenerationInput): Promise<string[]> {
    const outcomes = [
      `Successfully complete ${input.feature} setup`,
      'Understand the underlying concepts and architecture',
      'Be able to troubleshoot common issues',
      'Apply the knowledge to similar scenarios'
    ];

    if (input.feature.toLowerCase().includes('vault')) {
      outcomes.push('Deploy and manage Vault HA cluster');
      outcomes.push('Configure JWT authentication for GitHub Actions');
    }

    if (input.feature.toLowerCase().includes('openshift')) {
      outcomes.push('Deploy OpenShift clusters across multiple cloud providers');
      outcomes.push('Understand multi-cloud deployment patterns');
    }

    return outcomes;
  }

  /**
   * Generate troubleshooting section
   */
  private async generateTroubleshooting(_input: TutorialGenerationInput): Promise<TroubleshootingSection> {
    return {
      commonIssues: [
        {
          title: 'Permission Denied Errors',
          symptoms: ['Access denied when running commands', 'Insufficient privileges errors'],
          possibleCauses: ['Missing cluster-admin role', 'Incorrect service account permissions'],
          solutions: [
            'Verify cluster-admin access with `oc auth can-i create clusterroles`',
            'Contact cluster administrator for proper permissions'
          ],
          prevention: ['Always verify permissions before starting', 'Use dedicated service accounts']
        }
      ],
      generalSteps: [
        'Check OpenShift cluster connectivity',
        'Verify all required tools are installed',
        'Review logs for specific error messages',
        'Consult the repository documentation'
      ],
      supportResources: [
        {
          name: 'OpenShift Documentation',
          type: 'documentation',
          url: 'https://docs.openshift.com/',
          description: 'Official OpenShift documentation'
        },
        {
          name: 'Repository Issues',
          type: 'issue-tracker',
          url: 'https://github.com/tosin2013/openshift-github-actions/issues',
          description: 'Report issues and get community support'
        }
      ]
    };
  }

  /**
   * Helper methods
   */
  private generateTutorialTitle(feature: string): string {
    return `Tutorial: ${feature.split('-').map(word => 
      word.charAt(0).toUpperCase() + word.slice(1)
    ).join(' ')}`;
  }

  private mapAudience(targetAudience: string): AudienceType {
    switch (targetAudience) {
      case 'beginner': return AudienceType.USER;
      case 'intermediate': return AudienceType.DEVELOPER;
      case 'advanced': return AudienceType.ARCHITECT;
      default: return AudienceType.DEVELOPER;
    }
  }

  private mapComplexity(targetAudience: string): ComplexityLevel {
    switch (targetAudience) {
      case 'beginner': return ComplexityLevel.BEGINNER;
      case 'intermediate': return ComplexityLevel.INTERMEDIATE;
      case 'advanced': return ComplexityLevel.ADVANCED;
      default: return ComplexityLevel.INTERMEDIATE;
    }
  }

  private calculateTutorialConfidence(input: TutorialGenerationInput, steps: TutorialStep[]): number {
    let confidence = 80; // Base confidence

    // Increase confidence based on repository-specific features
    if (input.feature.toLowerCase().includes('vault') || 
        input.feature.toLowerCase().includes('openshift')) {
      confidence += 10; // Repository-specific features
    }

    if (steps.length >= 3) confidence += 5; // Comprehensive steps
    if (input.includeSetup) confidence += 5; // Complete setup

    return Math.min(100, confidence);
  }

  private estimateCompletionTime(steps: TutorialStep[]): number {
    // Estimate 15-30 minutes per step based on complexity
    return steps.length * 20; // 20 minutes average per step
  }
}
