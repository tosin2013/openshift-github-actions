# Red Hat AI Services (Granite) Integration Guide

This guide shows how to integrate the OpenShift GitHub Actions Repository Helper MCP Server with Red Hat AI Services using the Granite model.

## Configuration

### 1. Set up your API credentials

Create or update `config-granite.json`:

```json
{
  "diataxisConfig": {
    "enableTutorials": true,
    "enableHowTos": true,
    "enableReference": true,
    "enableExplanations": true,
    "outputFormats": ["markdown", "html"]
  },
  "developmentSupport": {
    "generateLLD": true,
    "generateAPIDocs": true,
    "generateArchitecture": true,
    "analyzeCodeStructure": true
  },
  "qaAndTesting": {
    "generateTestPlans": true,
    "specByExample": true,
    "qualityWorkflows": true,
    "coverageAnalysis": true
  },
  "redHatAIIntegration": {
    "endpoint": "https://granite-8b-code-instruct-maas-apicast-production.apps.prod.rhoai.rh-aiservices-bu.com:443",
    "model": "granite-8b-code-instruct-128k",
    "apiKey": "YOUR_ACTUAL_API_KEY_HERE",
    "specialization": "openshift-kubernetes-vault-documentation",
    "timeout": 30000,
    "maxRetries": 3
  }
}
```

### 2. Set environment variables (alternative to config file)

```bash
export REDHAT_AI_ENDPOINT="https://granite-8b-code-instruct-maas-apicast-production.apps.prod.rhoai.rh-aiservices-bu.com:443"
export REDHAT_AI_MODEL="granite-8b-code-instruct-128k"
export REDHAT_AI_API_KEY="your-api-key-here"
```

### 3. Start the MCP server with Granite configuration

```bash
# Using the config file
CONFIG_FILE=config-granite.json ./start-server.sh

# Or with environment variables
./start-server.sh
```

## Available AI-Enhanced Tools

### 1. AI Content Enhancement

Enhance existing documentation using the Granite model:

```json
{
  "tool": "repo-helper-ai-enhance-content",
  "arguments": {
    "content": "Vault is a secrets management tool. It stores passwords and keys.",
    "enhancementType": "technical-depth",
    "targetAudience": "intermediate"
  }
}
```

**Enhancement Types:**
- `clarity` - Improve readability and structure
- `completeness` - Add missing information and details
- `accuracy` - Verify and correct technical details
- `technical-depth` - Add deeper technical explanations

### 2. AI-Enhanced Documentation Generation

All existing tools now support AI enhancement when Granite is configured:

```json
{
  "tool": "repo-helper-generate-tutorial",
  "arguments": {
    "feature": "vault-ha-deployment",
    "targetAudience": "intermediate",
    "includeSetup": true,
    "aiEnhanced": true
  }
}
```

## Example API Integration

The MCP server uses the same API pattern as your Python example:

```python
# Your existing Python code
import requests

API_URL = "https://granite-8b-code-instruct-maas-apicast-production.apps.prod.rhoai.rh-aiservices-bu.com:443"
API_KEY = "***************************"

completion = requests.post(
    url=API_URL+'/v1/completions',
    json={
      "model": "granite-8b-code-instruct-128k",
      "prompt": "San Francisco is a",
      "max_tokens": 15,
      "temperature": 0
    },
    headers={'Authorization': 'Bearer '+API_KEY}
).json()
```

The MCP server implements this same pattern internally in TypeScript:

```typescript
// MCP server implementation (simplified)
const response = await fetch(`${this.config.endpoint}/v1/completions`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${this.config.apiKey}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    model: this.config.model || 'granite-8b-code-instruct-128k',
    prompt: prompt,
    max_tokens: this.calculateMaxTokens(request),
    temperature: 0.1,
    top_p: 0.9
  })
});
```

## Benefits of Integration

### 1. Repository-Specific AI Assistance
- **Context-Aware**: AI understands your OpenShift + Vault + GitHub Actions setup
- **Technology-Specific**: Prompts are tailored for your detected technologies
- **Pattern-Aware**: Incorporates your multi-cloud deployment patterns

### 2. Intelligent Documentation
- **Auto-Enhancement**: Existing docs are improved with AI insights
- **Technical Accuracy**: Granite model specializes in code and technical content
- **Consistency**: Maintains consistent style across all generated content

### 3. Quality Assurance
- **Content Validation**: AI reviews documentation for accuracy
- **Gap Analysis**: Identifies missing information
- **Best Practices**: Suggests improvements based on industry standards

## Testing the Integration

### 1. Test AI Service Health

```bash
# The server will automatically test AI connectivity on startup
./start-server.sh --verbose
```

Look for log messages like:
```
✅ Red Hat AI Service (granite-8b-code-instruct-128k) is operational
```

### 2. Test Content Enhancement

Create a simple test file:

```bash
echo "Vault stores secrets" > test-content.txt
```

Then use the MCP client to enhance it:

```json
{
  "tool": "repo-helper-ai-enhance-content",
  "arguments": {
    "content": "Vault stores secrets",
    "enhancementType": "technical-depth",
    "targetAudience": "intermediate"
  }
}
```

### 3. Expected Enhanced Output

The AI should transform simple content like "Vault stores secrets" into comprehensive technical documentation:

```markdown
# HashiCorp Vault Secrets Management

HashiCorp Vault is a comprehensive secrets management solution that provides:

## Core Capabilities
- **Dynamic Secrets**: Generate credentials on-demand with automatic rotation
- **Encryption as a Service**: Encrypt/decrypt data without storing encryption keys
- **Identity-Based Access**: Fine-grained access control with multiple auth methods
- **Audit Logging**: Comprehensive audit trail for all secret access

## OpenShift Integration
In your multi-cloud OpenShift environment, Vault serves as the central secrets store for:
- GitHub Actions JWT authentication
- Dynamic cloud provider credentials (AWS/Azure/GCP)
- TLS certificate management with cert-manager
- Application secrets and configuration

[... enhanced with repository-specific details ...]
```

## Troubleshooting

### Common Issues

1. **API Key Authentication**
   ```bash
   # Test your API key directly
   curl -X POST \
     -H "Authorization: Bearer YOUR_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"model":"granite-8b-code-instruct-128k","prompt":"Test","max_tokens":10}' \
     https://granite-8b-code-instruct-maas-apicast-production.apps.prod.rhoai.rh-aiservices-bu.com:443/v1/completions
   ```

2. **Network Connectivity**
   ```bash
   # Test endpoint connectivity
   curl -I https://granite-8b-code-instruct-maas-apicast-production.apps.prod.rhoai.rh-aiservices-bu.com:443
   ```

3. **Fallback Mode**
   If the AI service is unavailable, the MCP server automatically falls back to simulated responses while maintaining full functionality.

## Security Considerations

- **API Key Storage**: Store API keys securely, never commit to version control
- **Network Security**: Ensure HTTPS connections to the AI service
- **Content Privacy**: Be aware that content sent to AI services may be logged
- **Rate Limiting**: Respect API rate limits to avoid service disruption

---

This integration brings the power of Red Hat's Granite AI model directly into your OpenShift documentation and development workflow!
