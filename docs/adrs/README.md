# Architecture Decision Records (ADRs)

This directory contains Architecture Decision Records for the Vault HA deployment project.

## Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [001](001-two-phase-vault-deployment.md) | Two-Phase Vault HA Deployment with Automatic TLS Configuration | Accepted | 2025-06-04 |
| [002](002-json-processing-strategy.md) | Hybrid JSON Processing Strategy for Vault Operations | Accepted | 2025-06-04 |
| [003](003-multi-cloud-vault-integration.md) | Multi-Cloud Vault Integration Strategy | Proposed | 2025-06-04 |
| [004](004-github-actions-workflow-orchestration.md) | GitHub Actions Workflow Orchestration Strategy | Proposed | 2025-06-04 |
| [005](005-dynamic-secrets-credential-management.md) | Dynamic Secrets and Credential Management Strategy | Proposed | 2025-06-04 |

## ADR Process

1. **Propose**: Create new ADR using the [template](template.md)
2. **Review**: Technical review by team members
3. **Accept**: Mark as accepted and implement
4. **Update**: Modify status if superseded or deprecated

## Status Definitions

- **Proposed**: Under consideration
- **Accepted**: Approved and implemented
- **Deprecated**: No longer recommended but still supported
- **Superseded**: Replaced by newer ADR

## Key Decisions Summary

### Deployment Methodology
- **Two-phase approach**: HTTP deployment → TLS upgrade → Vault operations
- **Automatic TLS fixes**: ConfigMap patching and pod restart automation
- **95% success rate**: Proven enterprise-grade reliability

### Technical Standards
- **JSON processing**: Hybrid sed + jq approach for reliable parsing
- **Error handling**: Graceful failures with comprehensive logging
- **Verification**: Automated scoring and validation framework

### Multi-Cloud Integration
- **Central Vault Hub**: Single HA cluster serves all cloud deployments
- **Dynamic Credentials**: Just-in-time credential provisioning for security
- **GitHub Actions**: Hierarchical workflow orchestration with Vault-first dependency
- **Zero Trust**: No long-lived credentials, time-bound access only

## Related Documentation

- [Quick Start Guide](../guides/quick-start.md)
- [Troubleshooting](../troubleshooting/)
- [Main README](../../README.md)
