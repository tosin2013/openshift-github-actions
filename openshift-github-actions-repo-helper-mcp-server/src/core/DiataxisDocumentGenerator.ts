/**
 * Diátaxis Document Generator Base Class
 * 
 * Abstract base class for generating Diátaxis framework documents
 * with repository-specific context and methodological pragmatism.
 */

import { 
  DiataxisDocument, 
  DiataxisType, 
  AudienceType, 
  ComplexityLevel,
  DocumentGenerationOptions,
  ValidationOptions,
  ValidationStatus
} from '../types/diataxis.js';
import { RepositoryDetectionResult } from '../types/repository.js';
import { logger } from '../utils/logger.js';

/**
 * Abstract base class for Diátaxis document generators
 */
export abstract class DiataxisDocumentGenerator {
  protected repositoryContext: RepositoryDetectionResult;
  protected documentType: DiataxisType;

  constructor(repositoryContext: RepositoryDetectionResult, documentType: DiataxisType) {
    this.repositoryContext = repositoryContext;
    this.documentType = documentType;
  }

  /**
   * Generate a Diátaxis document
   */
  async generateDocument(
    title: string,
    audience: AudienceType,
    complexity: ComplexityLevel,
    options: DocumentGenerationOptions
  ): Promise<DiataxisDocument> {
    logger.diataxis(
      this.documentType as 'tutorial' | 'howto' | 'reference' | 'explanation',
      `Generating ${this.documentType} document: ${title}`,
      85,
      { audience, complexity }
    );

    try {
      // Generate base document structure
      const document = await this.createBaseDocument(title, audience, complexity);
      
      // Generate type-specific content
      await this.generateTypeSpecificContent(document, options);
      
      // Add code examples if requested
      if (options.includeCodeExamples) {
        await this.addCodeExamples(document);
      }
      
      // Add cross-references if requested
      if (options.includeCrossReferences) {
        await this.addCrossReferences(document);
      }
      
      // Validate document if validation options provided
      if (options.validationOptions) {
        document.validationStatus = await this.validateDocument(document, options.validationOptions);
      }
      
      logger.diataxis(
        this.documentType as 'tutorial' | 'howto' | 'reference' | 'explanation',
        `Successfully generated ${this.documentType} document`,
        90,
        { title, validationScore: document.validationStatus?.score }
      );
      
      return document;
      
    } catch (error) {
      logger.error(`Failed to generate ${this.documentType} document: ${title}`, error);
      throw error;
    }
  }

  /**
   * Create base document structure
   */
  protected async createBaseDocument(
    title: string,
    audience: AudienceType,
    complexity: ComplexityLevel
  ): Promise<DiataxisDocument> {
    const document: DiataxisDocument = {
      type: this.documentType,
      title,
      audience,
      complexity,
      repositoryContext: this.repositoryContext,
      content: '',
      relatedDocs: [],
      codeExamples: [],
      lastUpdated: new Date(),
      metadata: {
        id: this.generateDocumentId(title),
        tags: this.generateTags(),
        categories: this.generateCategories(),
        prerequisites: this.generatePrerequisites(complexity),
        learningObjectives: this.generateLearningObjectives(title, audience),
        successCriteria: this.generateSuccessCriteria(title, complexity)
      }
    };

    return document;
  }

  /**
   * Generate type-specific content (abstract method)
   */
  protected abstract generateTypeSpecificContent(
    document: DiataxisDocument,
    options: DocumentGenerationOptions
  ): Promise<void>;

  /**
   * Add code examples to document
   */
  protected async addCodeExamples(document: DiataxisDocument): Promise<void> {
    // This will be implemented by specific generators
    logger.debug(`Adding code examples for ${document.type} document: ${document.title}`);
  }

  /**
   * Add cross-references to document
   */
  protected async addCrossReferences(document: DiataxisDocument): Promise<void> {
    // Generate cross-references based on repository context
    const relatedDocs = this.findRelatedDocuments(document);
    document.relatedDocs = relatedDocs;
    
    logger.debug(`Added ${relatedDocs.length} cross-references to document: ${document.title}`);
  }

  /**
   * Validate document
   */
  protected async validateDocument(
    document: DiataxisDocument,
    options: ValidationOptions
  ): Promise<ValidationStatus> {
    const validationStatus: ValidationStatus = {
      isValid: true,
      score: 0,
      errors: [],
      warnings: [],
      lastValidated: new Date()
    };

    let score = 100;

    // Validate structure
    if (options.validateStructure) {
      const structureScore = this.validateDocumentStructure(document);
      score = Math.min(score, structureScore);
    }

    // Validate code examples
    if (options.validateCodeExamples && document.codeExamples.length > 0) {
      const codeScore = await this.validateCodeExamples(document);
      score = Math.min(score, codeScore);
    }

    // Validate cross-references
    if (options.validateCrossReferences) {
      const refScore = this.validateCrossReferences(document);
      score = Math.min(score, refScore);
    }

    validationStatus.score = score;
    validationStatus.isValid = score >= options.minimumQualityScore;

    return validationStatus;
  }

  /**
   * Generate document ID
   */
  protected generateDocumentId(title: string): string {
    const timestamp = Date.now();
    const titleSlug = title.toLowerCase().replace(/[^a-z0-9]+/g, '-');
    return `${this.documentType}-${titleSlug}-${timestamp}`;
  }

  /**
   * Generate tags based on repository context
   */
  protected generateTags(): string[] {
    const tags: string[] = [this.documentType];

    // Add technology-specific tags
    if (this.repositoryContext.detectedTechnologies.includes('OpenShift 4.18')) {
      tags.push('openshift', 'kubernetes', 'containers');
    }

    if (this.repositoryContext.detectedTechnologies.includes('HashiCorp Vault HA')) {
      tags.push('vault', 'secrets-management', 'security');
    }

    if (this.repositoryContext.detectedTechnologies.includes('GitHub Actions')) {
      tags.push('github-actions', 'ci-cd', 'automation');
    }

    if (this.repositoryContext.architecturePatterns.includes('Multi-cloud deployment')) {
      tags.push('multi-cloud', 'aws', 'azure', 'gcp');
    }

    return tags;
  }

  /**
   * Generate categories based on document type and repository
   */
  protected generateCategories(): string[] {
    const categories = [];
    
    switch (this.documentType) {
      case DiataxisType.TUTORIAL:
        categories.push('learning', 'hands-on', 'step-by-step');
        break;
      case DiataxisType.HOW_TO:
        categories.push('problem-solving', 'practical', 'goal-oriented');
        break;
      case DiataxisType.REFERENCE:
        categories.push('information', 'lookup', 'comprehensive');
        break;
      case DiataxisType.EXPLANATION:
        categories.push('understanding', 'conceptual', 'theoretical');
        break;
    }
    
    // Add repository-specific categories
    categories.push('openshift-automation', 'multi-cloud', 'devops');
    
    return categories;
  }

  /**
   * Generate prerequisites based on complexity
   */
  protected generatePrerequisites(complexity: ComplexityLevel): string[] {
    const prerequisites = [];
    
    // Base prerequisites for all documents
    prerequisites.push('Basic understanding of containerization concepts');
    
    if (complexity !== ComplexityLevel.BEGINNER) {
      prerequisites.push('Familiarity with Kubernetes/OpenShift');
      prerequisites.push('Experience with CI/CD pipelines');
    }
    
    if (complexity === ComplexityLevel.ADVANCED || complexity === ComplexityLevel.EXPERT) {
      prerequisites.push('Advanced knowledge of cloud platforms (AWS/Azure/GCP)');
      prerequisites.push('Experience with HashiCorp Vault');
      prerequisites.push('Understanding of infrastructure as code');
    }
    
    return prerequisites;
  }

  /**
   * Generate learning objectives
   */
  protected generateLearningObjectives(title: string, _audience: AudienceType): string[] {
    const objectives = [];
    
    switch (this.documentType) {
      case DiataxisType.TUTORIAL:
        objectives.push(`Complete a hands-on ${title.toLowerCase()} exercise`);
        objectives.push('Gain practical experience with the technology');
        break;
      case DiataxisType.HOW_TO:
        objectives.push(`Solve specific problems related to ${title.toLowerCase()}`);
        objectives.push('Apply solutions to real-world scenarios');
        break;
      case DiataxisType.REFERENCE:
        objectives.push(`Find comprehensive information about ${title.toLowerCase()}`);
        objectives.push('Use as a lookup resource during development');
        break;
      case DiataxisType.EXPLANATION:
        objectives.push(`Understand the concepts behind ${title.toLowerCase()}`);
        objectives.push('Gain deeper insight into design decisions');
        break;
    }
    
    return objectives;
  }

  /**
   * Generate success criteria
   */
  protected generateSuccessCriteria(_title: string, _complexity: ComplexityLevel): string[] {
    const criteria = [];
    
    switch (this.documentType) {
      case DiataxisType.TUTORIAL:
        criteria.push('Successfully complete all tutorial steps');
        criteria.push('Achieve expected outcomes');
        break;
      case DiataxisType.HOW_TO:
        criteria.push('Resolve the specific problem addressed');
        criteria.push('Apply the solution successfully');
        break;
      case DiataxisType.REFERENCE:
        criteria.push('Find required information quickly');
        criteria.push('Understand the reference material');
        break;
      case DiataxisType.EXPLANATION:
        criteria.push('Understand the underlying concepts');
        criteria.push('Explain the concepts to others');
        break;
    }
    
    return criteria;
  }

  /**
   * Find related documents
   */
  protected findRelatedDocuments(_document: DiataxisDocument): string[] {
    // This would implement logic to find related documents
    // based on tags, categories, and repository context
    return [];
  }

  /**
   * Validate document structure
   */
  protected validateDocumentStructure(document: DiataxisDocument): number {
    let score = 100;
    
    // Check required fields
    if (!document.title || document.title.length < 5) score -= 10;
    if (!document.content || document.content.length < 100) score -= 20;
    if (!document.metadata.tags || document.metadata.tags.length === 0) score -= 5;
    if (!document.metadata.categories || document.metadata.categories.length === 0) score -= 5;
    
    return Math.max(0, score);
  }

  /**
   * Validate code examples
   */
  protected async validateCodeExamples(document: DiataxisDocument): Promise<number> {
    let score = 100;
    
    for (const example of document.codeExamples) {
      if (!example.description || example.description.length < 10) score -= 5;
      if (!example.language) score -= 5;
      if (!example.code || example.code.length < 10) score -= 10;
    }
    
    return Math.max(0, score);
  }

  /**
   * Validate cross-references
   */
  protected validateCrossReferences(document: DiataxisDocument): number {
    let score = 100;
    
    // Check if related documents exist and are accessible
    for (const relatedDoc of document.relatedDocs) {
      if (!relatedDoc || relatedDoc.length === 0) score -= 5;
    }
    
    return Math.max(0, score);
  }
}
