# 🤖 AI-Powered Workflow Validator

An intelligent GitHub Actions workflow validator that uses Red Hat Granite AI to automatically detect and fix common workflow issues.

## ✨ Features

- **🧠 AI-Powered Analysis**: Uses Red Hat Granite AI for intelligent issue detection
- **🔧 Auto-Fix Capability**: Automatically repairs common YAML and workflow issues
- **🔍 Comprehensive Validation**: Checks syntax, structure, and best practices
- **📊 Detailed Reports**: Generates JSON reports with findings and fixes
- **🛡️ Security Scanning**: Detects exposed secrets and validates secret references
- **🔄 CI/CD Integration**: Runs automatically on workflow changes

## 🚀 Quick Start

### Local Usage

```bash
# Validate all workflows (read-only)
./scripts/common/validate-workflows.sh .github/workflows/

# Validate and auto-fix issues
./scripts/common/validate-workflows.sh --fix .github/workflows/deploy-aws.yml

# With custom API key
./scripts/common/validate-workflows.sh --api-key "your-key" .github/workflows/
```

### Environment Setup

1. Copy the environment template:
```bash
cp scripts/common/ai-validator.env.template scripts/common/ai-validator.env
```

2. Edit `ai-validator.env` and add your Red Hat AI API key:
```bash
REDHAT_AI_API_KEY=your_actual_api_key_here
```

3. Run validation:
```bash
./scripts/common/validate-workflows.sh .github/workflows/
```

## 🔧 Common Issues Detected & Fixed

### 1. YAML Boolean Key Issue
**Problem**: The `on` key is parsed as boolean `True`
```yaml
# ❌ Problematic
on:
  workflow_dispatch:
```

**AI Fix**:
```yaml
# ✅ Fixed
"on":
  workflow_dispatch:
```

### 2. Missing Required Fields
**Problem**: Workflow missing essential fields
**AI Fix**: Automatically adds missing `name`, `on`, or `jobs` sections

### 3. Invalid Job Structure
**Problem**: Jobs missing `runs-on` or `steps`
**AI Fix**: Adds proper job structure with default values

### 4. Indentation Issues
**Problem**: Inconsistent YAML indentation
**AI Fix**: Corrects spacing and alignment

## 📋 Validation Rules

The validator checks for:

- ✅ **YAML Syntax**: Valid YAML formatting
- ✅ **Required Fields**: `name`, `on`, `jobs`
- ✅ **Job Structure**: Proper `runs-on` and `steps`
- ✅ **Boolean Keys**: Detects `on` parsed as `True`
- ✅ **Security**: No hardcoded secrets
- ✅ **References**: Valid secret references

## 🤖 AI Integration

### Red Hat Granite AI Configuration

The validator uses Red Hat's Granite AI model for intelligent analysis:

- **Model**: `granite-8b-code-instruct-128k`
- **Endpoint**: Red Hat AI Services production environment
- **Capabilities**: Code analysis, YAML parsing, structure validation

### AI Prompts

The system uses specialized prompts for:

1. **Issue Detection**: Analyzing workflow files for problems
2. **Fix Generation**: Creating corrected YAML content
3. **Best Practices**: Suggesting improvements

## 📊 Reports

### JSON Report Format

```json
{
  "total_issues": 2,
  "status": "failed",
  "issues": [
    "YAML syntax error in deploy-aws.yml: Boolean key detected",
    "Missing required fields: ['on']"
  ]
}
```

### GitHub Actions Integration

The validator runs automatically on:
- ✅ Push to workflow files
- ✅ Pull requests affecting workflows
- ✅ Manual workflow dispatch

## 🛠️ Advanced Usage

### Python API

```python
from ai_workflow_validator import GraniteAIClient, WorkflowValidator

# Initialize
client = GraniteAIClient(api_url, api_key)
validator = WorkflowValidator(client)

# Validate file
success = validator.validate_file("workflow.yml", auto_fix=True)

# Get report
report = validator.get_report()
```

### Custom AI Prompts

You can customize the AI analysis by modifying the prompts in `ai-workflow-validator.py`:

```python
def ai_analyze_workflow(self, file_path: str, file_content: str) -> str:
    prompt = f"""Custom analysis prompt for {file_path}..."""
    return self.ai_client.complete(prompt)
```

## 🔒 Security Considerations

- ✅ **API Key Protection**: Never commit API keys to repository
- ✅ **Secret Scanning**: Automatically detects exposed secrets
- ✅ **Backup Files**: Creates backups before making changes
- ✅ **Permission Validation**: Checks workflow permissions

## 🐛 Troubleshooting

### Common Issues

1. **API Key Not Found**
   ```bash
   ❌ Error: API key required
   ```
   **Solution**: Set `REDHAT_AI_API_KEY` environment variable

2. **Dependencies Missing**
   ```bash
   ModuleNotFoundError: No module named 'yaml'
   ```
   **Solution**: Run `pip install pyyaml requests urllib3 numpy`

3. **AI Service Unavailable**
   ```bash
   ❌ AI completion failed: Connection timeout
   ```
   **Solution**: Check network connectivity and API endpoint

### Debug Mode

Enable detailed logging:
```bash
export DEBUG=1
./scripts/common/validate-workflows.sh .github/workflows/
```

## 📈 Integration Examples

### Pre-commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit
./scripts/common/validate-workflows.sh --fix .github/workflows/
```

### CI/CD Pipeline

```yaml
- name: Validate Workflows
  run: |
    scripts/common/validate-workflows.sh .github/workflows/
  env:
    REDHAT_AI_API_KEY: ${{ secrets.REDHAT_AI_API_KEY }}
```

## 🎯 Best Practices

1. **Regular Validation**: Run on every workflow change
2. **Auto-fix in Development**: Use `--fix` flag in development branches
3. **Manual Review**: Always review AI-generated fixes
4. **Backup Monitoring**: Check `.backup` files after auto-fixes
5. **Secret Management**: Use GitHub Secrets for sensitive data

## 🔗 Related Tools

- [GitHub Super Linter](https://github.com/github/super-linter)
- [actionlint](https://github.com/rhysd/actionlint)
- [YAML Lint](https://www.yamllint.com/)

## 📞 Support

For issues or questions:
1. Check the troubleshooting section
2. Review validation reports in `validation-report.json`
3. Check GitHub Actions logs for detailed error messages
4. Ensure Red Hat AI API key is valid and has sufficient quota

---

**Built with ❤️ using Red Hat Granite AI**
