# ADR-010: OpenShift Secrets Vault Integration Strategy

**Status**: Accepted  
**Date**: 2025-06-06  
**Authors**: Tosin Akinosho  
**Reviewers**: Development Team  

## Context

OpenShift cluster deployments require sensitive information including pull secrets and SSH keys. These secrets must be securely stored and accessible to GitHub Actions workflows while maintaining security best practices and automation capabilities.

## Problem Statement

The deployment workflows need access to:
1. **OpenShift Pull Secret**: Required for downloading OpenShift container images
2. **SSH Key Pairs**: Required for cluster node access and troubleshooting
3. **Secure Storage**: Secrets must be stored securely and not exposed in logs
4. **Automation**: Secret setup must be automated and repeatable

## Decision

We will implement an automated OpenShift secrets management system using HashiCorp Vault with the following approach:

### 1. Vault KV Secrets Engine

- **Path**: `secret/data/openshift/`
- **Engine**: KV version 2 for versioning and metadata
- **Structure**:
  - `secret/data/openshift/pull-secret` - OpenShift pull secret
  - `secret/data/openshift/ssh-keys/{environment}` - SSH key pairs per environment

### 2. Automated Setup Script

**Script**: `scripts/vault/add-openshift-secrets.sh`

**Capabilities**:
- Validates Vault connectivity and authentication
- Enables KV secrets engine if not present
- Reads pull secret from `~/pull-secret.json`
- Generates RSA 4096-bit SSH key pairs
- Stores secrets in Vault with proper paths
- Verifies all secrets are correctly stored

### 3. Security Implementation

**Authentication**:
- Uses Vault root token from `vault-keys.env`
- Validates token before operations
- All operations use authenticated sessions

**Data Protection**:
- Pull secret read from local file (not terminal input)
- SSH keys generated with strong encryption (RSA 4096)
- All secrets stored in Vault's encrypted backend
- No secrets exposed in logs or terminal output

## Implementation Details

### Script Architecture

```bash
# Main functions
check_vault_status()     # Validates Vault and authenticates
add_pull_secret()        # Reads and stores pull secret
add_ssh_keys()          # Generates and stores SSH keys
verify_secrets()        # Confirms all secrets present
```

### Prerequisites

1. **OpenShift Cluster**: Running with Vault deployed
2. **Pull Secret File**: `~/pull-secret.json` from Red Hat
3. **Vault Access**: Root token available in `vault-keys.env`
4. **Tools**: `oc`, `ssh-keygen`, `jq` available

### Workflow Integration

GitHub Actions workflows access secrets via:
```yaml
- name: Authenticate to HashiCorp Vault
  uses: hashicorp/vault-action@v2
  with:
    url: ${{ secrets.VAULT_URL }}
    method: jwt
    jwtGithubAudience: ${{ secrets.VAULT_JWT_AUDIENCE }}
    role: ${{ secrets.VAULT_ROLE }}
    tlsSkipVerify: true
    secrets: |
      secret/data/openshift/pull-secret pullSecret | PULL_SECRET ;
      secret/data/openshift/ssh-keys/dev private_key | SSH_PRIVATE_KEY ;
      secret/data/openshift/ssh-keys/dev public_key | SSH_PUBLIC_KEY
```

## Alternatives Considered

### 1. GitHub Secrets Only
**Rejected**: Limited size, no versioning, difficult to manage across multiple workflows

### 2. External Secret Management
**Rejected**: Adds complexity, requires additional infrastructure

### 3. Manual Vault Configuration
**Rejected**: Not repeatable, error-prone, doesn't scale

## Benefits

### 1. Security
- ✅ Centralized secret management
- ✅ No secrets in code or logs
- ✅ Encrypted storage with Vault
- ✅ Access control and audit trails

### 2. Automation
- ✅ Single command setup
- ✅ Repeatable across environments
- ✅ Integrated with deployment workflows
- ✅ Validation and verification built-in

### 3. Maintainability
- ✅ Clear secret organization
- ✅ Environment-specific SSH keys
- ✅ Version control for secret schemas
- ✅ Easy to update and rotate secrets

## Risks and Mitigations

### Risk: Vault Root Token Exposure
**Mitigation**: 
- Root token stored in secure file
- File excluded from version control
- Used only for initial setup

### Risk: Pull Secret File Security
**Mitigation**:
- File stored in user home directory
- Script validates file permissions
- File can be deleted after setup

### Risk: SSH Key Management
**Mitigation**:
- Keys generated with strong encryption
- Separate keys per environment
- Public keys logged for reference

## Success Metrics

1. **Setup Time**: < 2 minutes for complete secret setup
2. **Success Rate**: 100% success rate for secret storage
3. **Security**: No secrets exposed in logs or terminal
4. **Automation**: Zero manual steps required after pull secret download

## Implementation Status

- ✅ Script developed and tested
- ✅ Vault integration working
- ✅ GitHub Actions integration confirmed
- ✅ Documentation updated
- ✅ Prerequisites clearly defined

## Future Considerations

1. **Secret Rotation**: Automated rotation of SSH keys
2. **Multi-Environment**: Support for staging/production environments
3. **Backup Strategy**: Vault secret backup and recovery
4. **Monitoring**: Secret access monitoring and alerting

## References

- [Vault KV Secrets Engine](https://www.vaultproject.io/docs/secrets/kv/kv-v2)
- [GitHub Actions Vault Integration](https://github.com/hashicorp/vault-action)
- [OpenShift Pull Secret Documentation](https://docs.openshift.com/container-platform/4.18/installing/installing_aws/installing-aws-default.html#installation-obtaining-installer_installing-aws-default)
- [ADR-005: Dynamic Secrets Credential Management](005-dynamic-secrets-credential-management.md)
