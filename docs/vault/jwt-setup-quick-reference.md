# JWT Authentication Quick Reference

## 🚀 **Quick Setup (5 Minutes)**

### Step 1: Run Automated Setup Script
```bash
cd /Users/takinosh/workspace/openshift-github-actions
./scripts/vault/setup-github-jwt-auth.sh
```

### Step 2: Configure GitHub Secrets
Add these secrets to your GitHub repository (`Settings → Secrets and variables → Actions`):

```bash
VAULT_URL=https://vault-vault-test-pragmatic.apps.cluster-67wft.67wft.sandbox1936.opentlc.com
VAULT_JWT_AUDIENCE=https://github.com/tosin2013
VAULT_ROLE=github-actions-openshift
VAULT_ROOT_TOKEN=<from-vault-keys.env-file>
OPENSHIFT_SERVER=https://api.cluster-67wft.67wft.sandbox1936.opentlc.com:6443
OPENSHIFT_TOKEN=<generate-using-command-below>
```

### Step 3: Generate OpenShift Token
```bash
# Create service account
oc create serviceaccount github-actions-vault -n vault-test-pragmatic

# Grant permissions
oc adm policy add-cluster-role-to-user cluster-admin -z github-actions-vault -n vault-test-pragmatic

# Generate 24-hour token
oc create token github-actions-vault -n vault-test-pragmatic --duration=24h
```

### Step 4: Test Both Approaches
```bash
# Push test workflow
git add .github/workflows/test-vault-action-quick.yml
git commit -m "Add JWT authentication test"
git push origin main

# Run test in GitHub Actions:
# Actions → Quick Vault Action Test → Run workflow → Select "both"
```

## 📊 **Expected Test Results**

### Successful JWT Setup
```
✅ Vault Action authentication successful
✅ AWS credentials retrieved
✅ AWS credentials validated
Vault Action Score: 100/100

🏆 WINNER: Vault Action approach
RECOMMENDATION: Use vault-action@v2 for production
```

### JWT Issues (Fallback to oc exec)
```
❌ Vault Action authentication failed
Vault Action Score: 0/100

🏆 WINNER: OC Exec approach (Score: 100 vs 0)
RECOMMENDATION: Use proven oc exec pattern
```

## 🔧 **Troubleshooting**

### JWT Authentication Fails
```bash
# Check JWT configuration
oc exec vault-0 -n vault-test-pragmatic -- sh -c "
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN=$ROOT_TOKEN
vault read auth/jwt/config
vault read auth/jwt/role/github-actions-openshift
"
```

### Network Issues
```bash
# Test external Vault access
curl -k https://vault-vault-test-pragmatic.apps.cluster-67wft.67wft.sandbox1936.opentlc.com/v1/sys/health
```

### Policy Issues
```bash
# Verify policy
oc exec vault-0 -n vault-test-pragmatic -- sh -c "
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN=$ROOT_TOKEN
vault policy read openshift-deployment
"
```

## 📋 **Manual JWT Setup (If Script Fails)**

```bash
# 1. Enable JWT auth
vault auth enable jwt

# 2. Configure GitHub OIDC
vault write auth/jwt/config \
  bound_issuer="https://token.actions.githubusercontent.com" \
  oidc_discovery_url="https://token.actions.githubusercontent.com"

# 3. Create policy
vault policy write openshift-deployment - <<EOF
path "aws/creds/openshift-installer" {
  capabilities = ["read"]
}
path "secret/data/openshift/*" {
  capabilities = ["read"]
}
path "sys/health" {
  capabilities = ["read"]
}
EOF

# 4. Create role
vault write auth/jwt/role/github-actions-openshift \
  bound_audiences="https://github.com/tosin2013" \
  bound_subject="repo:tosin2013/openshift-github-actions:ref:refs/heads/main" \
  user_claim="actor" \
  role_type="jwt" \
  policies="openshift-deployment" \
  ttl=1h
```

## 🎯 **Success Criteria**

- **JWT Setup Score**: 95/100 (automated script)
- **GitHub Secrets**: All 5 secrets configured
- **Test Results**: Clear winner identified
- **Production Ready**: Approach selected for workflows

## 📚 **References**

- [Full Setup Guide](github-actions-jwt-setup.md)
- [ADR-009](../adrs/009-github-actions-jwt-authentication-strategy.md)
- [GitHub OIDC Docs](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
