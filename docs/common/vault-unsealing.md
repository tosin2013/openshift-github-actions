# Vault Unsealing Process

This document outlines the process for unsealing HashiCorp Vault deployed on OpenShift using our GitHub Actions workflow.

## Understanding the Vault Deployment State

When Vault is deployed using our GitHub Actions workflow (`deploy-vault-on-openshift.yml`), it reaches a state where:

1. All pods are running and show as "Ready" in Kubernetes (1/1)
2. The first pod (`vault-0`) is initialized but sealed
3. The remaining pods (`vault-1`, `vault-2`, etc.) are uninitialized and sealed

This state represents a **partially operational** deployment. While the infrastructure is correctly deployed, Vault requires unsealing to become fully operational.

## Unsealing Methods

### Method 1: Manual Unsealing (Recommended for Development)

For development environments, you can use the provided script to manually unseal Vault:

```bash
# Make the script executable
chmod +x /tmp/unseal-vault.sh

# Run the script and follow the prompts
/tmp/unseal-vault.sh
```

The script will:
1. Check if Vault is initialized
2. Prompt for unseal keys
3. Apply the keys to each pod
4. Verify the unsealing was successful

### Method 2: Auto-Unsealing (Recommended for Production)

For production environments, consider implementing auto-unsealing using a cloud KMS:

1. **GCP Cloud KMS**: [Documentation](https://developer.hashicorp.com/vault/docs/configuration/seal/gcpckms)
2. **AWS KMS**: [Documentation](https://developer.hashicorp.com/vault/docs/configuration/seal/awskms)
3. **Azure Key Vault**: [Documentation](https://developer.hashicorp.com/vault/docs/configuration/seal/azurekeyvault)

To implement auto-unsealing, modify the Helm values in the GitHub Actions workflow:

```yaml
server:
  # Other configuration...
  
  seal:
    type: gcpckms
    gcpckms:
      credentials: /path/to/credentials.json
      project: my-project
      region: global
      key_ring: vault-keyring
      crypto_key: vault-key
```

## Impact on GitHub Actions Workflow

Our current workflow (`deploy-vault-on-openshift.yml`) attempts to initialize and unseal Vault automatically, but has limitations:

1. **Security Limitations**: The workflow stores unseal keys in GitHub Actions environment variables, which is not secure for production
2. **Operational Gap**: If the workflow fails to unseal Vault, manual intervention is required
3. **Key Management**: There's no secure mechanism for storing and retrieving unseal keys

## Best Practices

1. **Development Environments**: 
   - Use the GitHub Actions workflow for deployment
   - Use manual unsealing with the provided script
   - Store unseal keys securely (not in version control)

2. **Production Environments**:
   - Modify the workflow to use auto-unsealing with a cloud KMS
   - Implement proper secret management for any credentials
   - Document the recovery procedures

## Troubleshooting

If Vault pods remain sealed after deployment:

1. Check if Vault is initialized:
   ```bash
   oc exec -n vault vault-0 -- sh -c "VAULT_ADDR=http://localhost:8200 vault status"
   ```

2. If initialized but sealed, use the unsealing script or manually unseal:
   ```bash
   oc exec -n vault vault-0 -- sh -c "VAULT_ADDR=http://localhost:8200 vault operator unseal <key>"
   ```

3. If not initialized, initialize Vault first:
   ```bash
   oc exec -n vault vault-0 -- sh -c "VAULT_ADDR=http://localhost:8200 vault operator init"
   ```

## Conclusion

The deployment of Vault on OpenShift requires understanding the gap between Kubernetes readiness and Vault's operational state. By following these procedures, you can ensure a fully operational Vault deployment while maintaining security best practices.
