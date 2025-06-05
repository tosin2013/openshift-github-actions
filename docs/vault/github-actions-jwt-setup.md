# GitHub Actions JWT Authentication Setup Guide

This guide provides step-by-step instructions for setting up JWT authentication between GitHub Actions and Vault, enabling secure, token-less CI/CD workflows.

## Prerequisites

- ✅ Vault HA cluster deployed and operational
- ✅ AWS secrets engine configured
- ✅ Vault externally accessible via OpenShift route
- ✅ GitHub repository with Actions enabled
- ✅ OpenShift cluster access with admin privileges

## Phase 1: Vault JWT Authentication Configuration

### Step 1: Verify Vault External Access

```bash
# Test external Vault access
curl -k https://vault-vault-test-pragmatic.apps.cluster-67wft.67wft.sandbox1936.opentlc.com/v1/sys/health

# Expected response: {"initialized":true,"sealed":false,...}
```

### Step 2: Enable JWT Authentication Method

```bash
# Source your Vault credentials
source vault-keys.env

# Enable JWT auth method
oc exec vault-0 -n vault-test-pragmatic -- sh -c "
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN=$ROOT_TOKEN

echo 'Enabling JWT authentication method...'
vault auth enable jwt
"
```

### Step 3: Configure JWT Auth with GitHub OIDC

```bash
# Configure JWT auth method
oc exec vault-0 -n vault-test-pragmatic -- sh -c "
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN=$ROOT_TOKEN

echo 'Configuring JWT auth with GitHub OIDC...'
vault write auth/jwt/config \
  bound_issuer='https://token.actions.githubusercontent.com' \
  oidc_discovery_url='https://token.actions.githubusercontent.com'
"
```

### Step 4: Create OpenShift Deployment Policy

```bash
# Create policy for OpenShift deployments
oc exec vault-0 -n vault-test-pragmatic -- sh -c "
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN=$ROOT_TOKEN

echo 'Creating OpenShift deployment policy...'
vault policy write openshift-deployment - <<EOF
# AWS secrets engine access for dynamic credentials
path \"aws/creds/openshift-installer\" {
  capabilities = [\"read\"]
}

# OpenShift secrets access (pull secret, SSH keys)
path \"secret/data/openshift/*\" {
  capabilities = [\"read\"]
}

# Vault health check access
path \"sys/health\" {
  capabilities = [\"read\"]
}

# Auth token lookup (for debugging)
path \"auth/token/lookup-self\" {
  capabilities = [\"read\"]
}
EOF
"
```

### Step 5: Create GitHub Actions JWT Role

```bash
# Create JWT role for GitHub Actions
oc exec vault-0 -n vault-test-pragmatic -- sh -c "
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN=$ROOT_TOKEN

echo 'Creating GitHub Actions JWT role...'
vault write auth/jwt/role/github-actions-openshift \
  bound_audiences='https://github.com/tosin2013' \
  bound_subject='repo:tosin2013/openshift-github-actions:ref:refs/heads/main' \
  user_claim='actor' \
  role_type='jwt' \
  policies='openshift-deployment' \
  ttl=1h \
  max_ttl=2h
"
```

### Step 6: Create Environment-Specific Roles (Optional)

```bash
# Development environment role
oc exec vault-0 -n vault-test-pragmatic -- sh -c "
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN=$ROOT_TOKEN

echo 'Creating development environment role...'
vault write auth/jwt/role/github-actions-dev \
  bound_audiences='https://github.com/tosin2013' \
  bound_subject='repo:tosin2013/openshift-github-actions:environment:dev' \
  user_claim='actor' \
  role_type='jwt' \
  policies='openshift-deployment' \
  ttl=30m \
  max_ttl=1h
"

# Production environment role
oc exec vault-0 -n vault-test-pragmatic -- sh -c "
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN=$ROOT_TOKEN

echo 'Creating production environment role...'
vault write auth/jwt/role/github-actions-prod \
  bound_audiences='https://github.com/tosin2013' \
  bound_subject='repo:tosin2013/openshift-github-actions:environment:production' \
  user_claim='actor' \
  role_type='jwt' \
  policies='openshift-deployment' \
  ttl=15m \
  max_ttl=30m
"
```

### Step 7: Verify JWT Configuration

```bash
# Verify JWT auth configuration
oc exec vault-0 -n vault-test-pragmatic -- sh -c "
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN=$ROOT_TOKEN

echo 'Verifying JWT configuration...'
vault read auth/jwt/config
echo ''
echo 'Verifying GitHub Actions role...'
vault read auth/jwt/role/github-actions-openshift
"
```

## Phase 2: GitHub Repository Secrets Configuration

### Step 1: Navigate to Repository Secrets

1. Go to your GitHub repository: `https://github.com/tosin2013/openshift-github-actions`
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**

### Step 2: Add Required Secrets

Add the following secrets one by one:

#### Vault Configuration Secrets

```bash
# Secret Name: VAULT_URL
# Secret Value: 
https://vault-vault-test-pragmatic.apps.cluster-67wft.67wft.sandbox1936.opentlc.com

# Secret Name: VAULT_JWT_AUDIENCE
# Secret Value:
https://github.com/tosin2013

# Secret Name: VAULT_ROLE
# Secret Value:
github-actions-openshift
```

#### OpenShift Configuration Secrets (for oc exec fallback)

```bash
# Secret Name: OPENSHIFT_SERVER
# Secret Value:
https://api.cluster-67wft.67wft.sandbox1936.opentlc.com:6443

# Secret Name: OPENSHIFT_TOKEN
# Secret Value: (Generate using the command below)
```

### Step 3: Generate OpenShift Service Account Token

```bash
# Create service account for GitHub Actions
oc create serviceaccount github-actions-vault -n vault-test-pragmatic

# Grant necessary permissions
oc adm policy add-cluster-role-to-user cluster-admin -z github-actions-vault -n vault-test-pragmatic

# Generate token (valid for 24 hours)
TOKEN=$(oc create token github-actions-vault -n vault-test-pragmatic --duration=24h)
echo "OpenShift Token: $TOKEN"

# Copy this token and add it as OPENSHIFT_TOKEN secret in GitHub
```

## Phase 3: Test and Validation

### Step 1: Run Quick Validation Test

```bash
# Push the test workflow if not already done
git add .github/workflows/test-vault-action-quick.yml
git commit -m "Add JWT authentication test workflow"
git push origin main
```

### Step 2: Execute Test Workflow

1. Go to **Actions** tab in your GitHub repository
2. Click **Quick Vault Action Test** workflow
3. Click **Run workflow**
4. Select **both** for test method
5. Click **Run workflow**

### Step 3: Monitor Test Results

The workflow will test both approaches and provide a comparison:

- **Vault Action Score**: JWT authentication success rate
- **OC Exec Score**: Container-based approach success rate
- **Recommendation**: Which approach to use for production

### Expected Results

**Successful JWT Setup:**
```
✅ Vault Action authentication successful
✅ AWS credentials retrieved  
✅ AWS credentials validated
Vault Action Score: 100/100

🏆 WINNER: Vault Action approach (Score: 100 vs 100)
RECOMMENDATION: Use vault-action@v2 for production
```

**JWT Setup Issues:**
```
❌ Vault Action authentication failed
Vault Action Score: 0/100

🏆 WINNER: OC Exec approach (Score: 100 vs 0)  
RECOMMENDATION: Use proven oc exec pattern for production
```

## Troubleshooting

### Common Issues

#### 1. JWT Authentication Fails

**Error**: `permission denied` or `invalid JWT`

**Solutions**:
```bash
# Check JWT configuration
vault read auth/jwt/config

# Verify role configuration  
vault read auth/jwt/role/github-actions-openshift

# Check GitHub repository URL matches bound_subject
# Ensure workflow runs from main branch
```

#### 2. Network Connectivity Issues

**Error**: `connection refused` or `timeout`

**Solutions**:
```bash
# Verify Vault route is accessible
curl -k https://vault-vault-test-pragmatic.apps.cluster-67wft.67wft.sandbox1936.opentlc.com/v1/sys/health

# Check OpenShift route configuration
oc get route vault -n vault-test-pragmatic -o yaml
```

#### 3. Policy Permission Issues

**Error**: `permission denied` when accessing secrets

**Solutions**:
```bash
# Verify policy exists
vault policy read openshift-deployment

# Check role policy assignment
vault read auth/jwt/role/github-actions-openshift
```

## Security Considerations

1. **Token TTL**: Keep JWT token TTL as short as practical (15-60 minutes)
2. **Audience Binding**: Always bind to specific GitHub organization
3. **Subject Binding**: Bind to specific repository and branch
4. **Policy Principle**: Grant minimum required permissions
5. **Audit Logging**: Monitor authentication events in Vault logs

## Next Steps

After successful JWT setup:

1. **Update Existing Workflows**: Replace vault-action usage in deploy-*.yml
2. **Environment Roles**: Configure dev/staging/prod specific roles
3. **Monitoring**: Set up alerts for authentication failures
4. **Documentation**: Update team runbooks with new authentication flow

## References

- [ADR-009: GitHub Actions JWT Authentication Strategy](../adrs/009-github-actions-jwt-authentication-strategy.md)
- [GitHub OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Vault JWT Auth Method](https://developer.hashicorp.com/vault/docs/auth/jwt)
