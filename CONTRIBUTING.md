# Contributing to OpenShift Multi-Cloud Automation

Thank you for your interest in contributing to the OpenShift 4.18 Multi-Cloud Automation project! This document provides guidelines and information for contributors.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Contributing Guidelines](#contributing-guidelines)
- [Pull Request Process](#pull-request-process)
- [Testing](#testing)
- [Documentation](#documentation)
- [Issue Reporting](#issue-reporting)

## Code of Conduct

This project adheres to a code of conduct that promotes a welcoming and inclusive environment. By participating, you are expected to uphold this code.

### Our Standards

- Use welcoming and inclusive language
- Be respectful of differing viewpoints and experiences
- Gracefully accept constructive criticism
- Focus on what is best for the community
- Show empathy towards other community members

## Getting Started

### Prerequisites

Before contributing, ensure you have:

- Git installed and configured
- GitHub account
- Basic understanding of:
  - OpenShift/Kubernetes
  - GitHub Actions
  - HashiCorp Vault
  - Cloud platforms (AWS, Azure, GCP)
  - Bash scripting

### Repository Structure

```
openshift-github-actions/
├── .github/workflows/     # GitHub Actions workflows
├── scripts/              # Automation scripts
│   ├── aws/             # AWS-specific scripts
│   ├── azure/           # Azure-specific scripts
│   ├── gcp/             # GCP-specific scripts
│   └── common/          # Common utilities
├── config/              # Configuration templates
├── docs/                # Documentation
├── tests/               # Test scripts
└── README.md
```

## Development Setup

### 1. Fork and Clone

```bash
# Fork the repository on GitHub
# Clone your fork
git clone https://github.com/YOUR_USERNAME/openshift-github-actions.git
cd openshift-github-actions

# Add upstream remote
git remote add upstream https://github.com/ORIGINAL_OWNER/openshift-github-actions.git
```

### 2. Create Development Branch

```bash
git checkout -b feature/your-feature-name
```

### 3. Set Up Development Environment

```bash
# Install required tools
# - OpenShift CLI (oc)
# - Cloud provider CLIs (aws, az, gcloud)
# - HashiCorp Vault CLI
# - shellcheck (for script linting)

# Make scripts executable
find scripts -name "*.sh" -exec chmod +x {} \;
```

## Contributing Guidelines

### Code Style

#### Shell Scripts
- Use `#!/bin/bash` shebang
- Enable strict mode: `set -euo pipefail`
- Use meaningful variable names
- Add comments for complex logic
- Follow the existing code style

#### YAML Files
- Use 2-space indentation
- Keep lines under 120 characters
- Use meaningful names for jobs and steps

#### Documentation
- Use Markdown format
- Include code examples
- Keep language clear and concise
- Update table of contents when needed

### Commit Messages

Follow conventional commit format:

```
type(scope): description

[optional body]

[optional footer]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes
- `refactor`: Code refactoring
- `test`: Test additions or modifications
- `chore`: Maintenance tasks

Examples:
```
feat(aws): add support for custom VPC configuration
fix(vault): resolve authentication timeout issue
docs(readme): update installation instructions
```

### Branch Naming

Use descriptive branch names:
- `feature/add-gcp-support`
- `fix/vault-auth-issue`
- `docs/update-troubleshooting`
- `refactor/common-utilities`

## Pull Request Process

### 1. Before Submitting

- [ ] Code follows project style guidelines
- [ ] Scripts pass shellcheck linting
- [ ] Documentation is updated
- [ ] Tests pass (if applicable)
- [ ] Commit messages follow convention

### 2. Pull Request Template

When creating a pull request, include:

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Refactoring
- [ ] Other (specify)

## Cloud Provider(s)
- [ ] AWS
- [ ] Azure
- [ ] GCP
- [ ] Common (affects all providers)

## Testing
Describe testing performed

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No new warnings introduced
```

### 3. Review Process

1. Automated checks must pass
2. At least one maintainer review required
3. Address review feedback
4. Maintain clean commit history

## Testing

### Script Testing

```bash
# Lint shell scripts
shellcheck scripts/**/*.sh

# Test script syntax
bash -n scripts/common/utils.sh

# Run validation tests
./tests/validation/validate-cluster.sh --help
```

### Workflow Testing

1. Test workflows in your fork
2. Use development environment
3. Verify all cloud providers work
4. Test error scenarios

### Integration Testing

1. Deploy test clusters
2. Verify all features work
3. Test cleanup procedures
4. Document any issues

## Documentation

### Types of Documentation

1. **Code Comments**: Explain complex logic
2. **README Updates**: Keep installation/usage current
3. **API Documentation**: Document script parameters
4. **Troubleshooting**: Add common issues and solutions

### Documentation Standards

- Use clear, concise language
- Include practical examples
- Keep information current
- Cross-reference related topics

### Updating Documentation

When making changes:
- Update relevant documentation
- Add new troubleshooting entries
- Update configuration examples
- Review for accuracy

## Issue Reporting

### Before Creating an Issue

1. Search existing issues
2. Check troubleshooting guide
3. Verify with latest version
4. Gather relevant information

### Issue Template

```markdown
## Description
Clear description of the issue

## Environment
- Cloud Provider: [AWS/Azure/GCP]
- OpenShift Version: [4.18.x]
- Region: [region-name]
- Environment: [dev/staging/production]

## Steps to Reproduce
1. Step one
2. Step two
3. Step three

## Expected Behavior
What should happen

## Actual Behavior
What actually happens

## Logs/Screenshots
Include relevant logs or screenshots

## Additional Context
Any other relevant information
```

### Issue Labels

- `bug`: Something isn't working
- `enhancement`: New feature request
- `documentation`: Documentation improvements
- `good first issue`: Good for newcomers
- `help wanted`: Extra attention needed
- `aws`: AWS-specific issue
- `azure`: Azure-specific issue
- `gcp`: GCP-specific issue

## Release Process

### Versioning

We use [Semantic Versioning](https://semver.org/):
- MAJOR: Incompatible API changes
- MINOR: Backward-compatible functionality
- PATCH: Backward-compatible bug fixes

### Release Checklist

- [ ] All tests pass
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] Version tagged
- [ ] Release notes created

## Getting Help

### Communication Channels

1. GitHub Issues: Bug reports and feature requests
2. GitHub Discussions: General questions and ideas
3. Documentation: Comprehensive guides and references

### Maintainer Contact

For urgent issues or security concerns, contact the maintainers directly.

## Recognition

Contributors will be recognized in:
- README.md contributors section
- Release notes
- Project documentation

Thank you for contributing to OpenShift Multi-Cloud Automation!

---

**Questions?** Feel free to open an issue or start a discussion. We're here to help!
