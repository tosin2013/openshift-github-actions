# OpenShift Secrets Setup for Vault

This guide covers the automated setup of OpenShift secrets in HashiCorp Vault using the `add-openshift-secrets.sh` script.

## Overview

Before deploying OpenShift clusters, you must configure the required secrets in Vault. The automated setup script handles all necessary secrets including pull secrets and SSH keys.

## Prerequisites

### Required Components
- ✅ OpenShift cluster with admin access
- ✅ HashiCorp Vault deployed and accessible
- ✅ Vault root token available in `vault-keys.env`
- ✅ OpenShift pull secret downloaded from Red Hat

### Required Tools
- `oc` - OpenShift CLI
- `ssh-keygen` - SSH key generation
- `jq` - JSON processing
- `vault` - Vault CLI (available in Vault pod)

### Required Files
- `~/pull-secret.json` - OpenShift pull secret from Red Hat
- `vault-keys.env` - Vault root token and configuration

## Quick Start

### 1. Download Pull Secret

Visit [Red Hat Console](https://console.redhat.com/openshift/install/pull-secret) and download your pull secret:

```bash
# Save the downloaded pull secret as ~/pull-secret.json
# The file should contain JSON like:
# {"auths":{"cloud.openshift.com":{"auth":"..."},"quay.io":{"auth":"..."}}}
```

### 2. Run Setup Script

```bash
# Execute the automated setup
./scripts/vault/add-openshift-secrets.sh
```

### 3. Verify Setup

The script automatically verifies all secrets, but you can manually check:

```bash
# Source vault configuration
source vault-keys.env

# Check pull secret
oc exec vault-0 -n vault-test-pragmatic -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv get secret/openshift/pull-secret

# Check SSH keys
oc exec vault-0 -n vault-test-pragmatic -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv get secret/openshift/ssh-keys/dev
```

## What the Script Does

### Phase 1: Validation
1. **Vault Connectivity**: Confirms Vault is accessible via OpenShift
2. **Authentication**: Validates root token from `vault-keys.env`
3. **KV Engine**: Enables KV secrets engine if not present

### Phase 2: Pull Secret Setup
1. **File Validation**: Reads and validates `~/pull-secret.json`
2. **JSON Validation**: Ensures proper JSON format
3. **Vault Storage**: Stores at `secret/data/openshift/pull-secret`

### Phase 3: SSH Key Generation
1. **Key Generation**: Creates RSA 4096-bit key pair
2. **Secure Storage**: Stores both private and public keys
3. **Environment Isolation**: Separate keys per environment (dev/staging/prod)

### Phase 4: Verification
1. **Existence Check**: Confirms all secrets are present
2. **Access Test**: Validates secret retrieval
3. **Summary Report**: Provides setup completion status

## Secret Structure in Vault

### Pull Secret
```
Path: secret/data/openshift/pull-secret
Data:
  pullSecret: {"auths":{"cloud.openshift.com":...}}
```

### SSH Keys
```
Path: secret/data/openshift/ssh-keys/dev
Data:
  private_key: -----BEGIN OPENSSH PRIVATE KEY-----...
  public_key: ssh-rsa AAAAB3NzaC1yc2E...
```

## Script Output Example

```bash
[2025-06-06 17:54:46] Adding OpenShift secrets to Vault...
[2025-06-06 17:54:46] Starting OpenShift secrets setup for Vault...
[2025-06-06 17:54:46] Checking Vault status...
[2025-06-06 17:54:46] [SUCCESS] Vault is accessible and ready
[2025-06-06 17:54:46] Authenticating with Vault...
[2025-06-06 17:54:47] [SUCCESS] Successfully authenticated with Vault
[2025-06-06 17:54:47] Checking if KV secrets engine is enabled...
[2025-06-06 17:54:48] Enabling KV secrets engine at secret/ path...
[2025-06-06 17:54:49] [SUCCESS] KV secrets engine enabled successfully
[2025-06-06 17:54:49] Adding OpenShift pull secret to Vault...
[2025-06-06 17:54:49] Reading pull secret from: /Users/user/pull-secret.json
[2025-06-06 17:54:49] Pull secret file validated successfully
[2025-06-06 17:54:50] [SUCCESS] Pull secret added to Vault successfully
[2025-06-06 17:54:50] Adding SSH keys for environment: dev
[2025-06-06 17:54:51] Generating SSH key pair...
[2025-06-06 17:54:52] [SUCCESS] SSH keys for dev added to Vault successfully
[2025-06-06 17:54:53] Verifying secrets in Vault...
[2025-06-06 17:54:53] [SUCCESS] ✅ Pull secret exists
[2025-06-06 17:54:54] [SUCCESS] ✅ SSH keys for dev environment exist
[2025-06-06 17:54:54] [SUCCESS] All required secrets are present in Vault!
[2025-06-06 17:54:54] [SUCCESS] OpenShift secrets setup completed!
[2025-06-06 17:54:54] You can now run the multi-cloud deployment workflow.
```

## Troubleshooting

### Common Issues

#### 1. Pull Secret File Not Found
```
[ERROR] Pull secret file not found at: /Users/user/pull-secret.json
```
**Solution**: Download pull secret from Red Hat and save as `~/pull-secret.json`

#### 2. Invalid JSON Format
```
[ERROR] Invalid JSON format in pull secret file
```
**Solution**: Ensure the pull secret file contains valid JSON from Red Hat

#### 3. Vault Authentication Failed
```
[ERROR] Failed to authenticate with Vault
```
**Solution**: Check that `vault-keys.env` exists and contains valid `ROOT_TOKEN`

#### 4. Permission Denied
```
Code: 403. Errors: * permission denied
```
**Solution**: Ensure you're using the root token and Vault is properly unsealed

### Manual Recovery

If the script fails, you can manually add secrets:

```bash
# Source vault configuration
source vault-keys.env

# Enable KV engine (if needed)
oc exec vault-0 -n vault-test-pragmatic -- env VAULT_TOKEN="$ROOT_TOKEN" vault secrets enable -path=secret kv-v2

# Add pull secret manually
PULL_SECRET=$(cat ~/pull-secret.json)
oc exec vault-0 -n vault-test-pragmatic -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv put secret/openshift/pull-secret pullSecret="$PULL_SECRET"

# Generate and add SSH keys manually
ssh-keygen -t rsa -b 4096 -f /tmp/openshift_rsa -N ""
PRIVATE_KEY=$(cat /tmp/openshift_rsa)
PUBLIC_KEY=$(cat /tmp/openshift_rsa.pub)
oc exec vault-0 -n vault-test-pragmatic -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv put secret/openshift/ssh-keys/dev private_key="$PRIVATE_KEY" public_key="$PUBLIC_KEY"
rm /tmp/openshift_rsa /tmp/openshift_rsa.pub
```

## Security Considerations

### File Security
- Pull secret file should have restricted permissions (600)
- Delete pull secret file after setup if desired
- SSH keys are generated fresh for each environment

### Vault Security
- Root token is only used for initial setup
- All secrets are encrypted at rest in Vault
- Access is logged and auditable

### Network Security
- All communication with Vault uses TLS
- No secrets are transmitted in plain text
- GitHub Actions use JWT authentication for Vault access

## Next Steps

After successful secret setup:

1. **Configure GitHub Secrets**: Add Vault URL and JWT authentication details
2. **Run Deployment**: Execute multi-cloud deployment workflows
3. **Monitor Access**: Review Vault audit logs for secret access

## Related Documentation

- [ADR-010: OpenShift Secrets Vault Integration Strategy](../adrs/010-openshift-secrets-vault-integration.md)
- [Vault Setup Guide](vault-setup.md)
- [GitHub Actions JWT Setup](github-actions-jwt-setup.md)
- [Main README](../../README.md)
