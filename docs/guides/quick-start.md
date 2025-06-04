# Vault HA Quick Start Guide

**Deployment Score: 95/100 | Time: 8-10 minutes**

## Prerequisites

- OpenShift cluster with admin access
- cert-manager installed and operational
- Helm 3.x installed
- Python 3.x with Jinja2

## Quick Deployment

### Option 1: Single Command (Recommended)
```bash
export VAULT_NAMESPACE="vault-production"
./deploy_vault_ha_tls_complete.sh && ./verify_vault_deployment.sh
```

### Option 2: Step-by-Step
```bash
# Step 1: Set namespace
export VAULT_NAMESPACE="vault-production"

# Step 2: Deploy infrastructure with automatic TLS fix
./deploy_vault_ha_tls_complete.sh

# Step 3: Verify deployment
./verify_vault_deployment.sh
```

## Expected Results

```
🎉 OUTSTANDING: 95/100 (95%) - Highly Successful!

✅ Infrastructure: All pods, services, routes operational
✅ TLS Integration: HTTPS working end-to-end  
✅ Vault Leader: vault-0 initialized and unsealed
✅ HA Cluster: Leader + standby nodes operational
✅ External Access: UI accessible via HTTPS
```

## Access Your Vault

```bash
# Get external URL
VAULT_URL=$(oc get route vault -n $VAULT_NAMESPACE -o jsonpath='{.spec.host}')
echo "Vault UI: https://$VAULT_URL"

# CLI access
export VAULT_ADDR="https://$VAULT_URL"
export VAULT_SKIP_VERIFY=true
vault status
```

## Unseal Keys

Keys are automatically saved to `vault-keys.env`:
```bash
# View saved keys
cat vault-keys.env

# Use keys for additional operations
source vault-keys.env
echo "Root token: $ROOT_TOKEN"
```

## Troubleshooting

### Common Issues

**Pods not starting:**
```bash
oc get pods -n $VAULT_NAMESPACE
oc logs vault-0 -n $VAULT_NAMESPACE
```

**TLS issues:**
```bash
oc get secret vault-tls -n $VAULT_NAMESPACE
oc describe certificate vault-tls -n $VAULT_NAMESPACE
```

**Verification failures:**
```bash
./verify_vault_deployment.sh
# Review specific test failures and apply fixes
```

## Next Steps

1. **Configure Authentication**: Set up LDAP, OIDC, or other auth methods
2. **Create Policies**: Define access policies for different user groups  
3. **Enable Secrets Engines**: Configure KV, PKI, database secrets
4. **Set Up Monitoring**: Integrate with Prometheus/Grafana
5. **Backup Strategy**: Implement Raft snapshot automation

## Architecture

See [ADR-001](../adrs/001-two-phase-vault-deployment.md) for detailed technical decisions and methodology.
